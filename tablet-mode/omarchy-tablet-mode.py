#!/usr/bin/env python3
"""Publish Surface tablet-mode state, and run hooks when it changes.

Two distinct conditions, and device presence alone only sees one of them:

  * the Type Cover is detached, and
  * the Type Cover is folded back behind the screen -- still attached, still
    enumerated, so a presence check misses the most common tablet posture.

Fold-back is reported as SW_TABLET_MODE on an EV_SW device. Where that device
lives differs by model, which is why nothing here matches on a device name:

  * Surface Go: chassis-level ("Intel HID switches"). It persists when the
    cover is detached, so the two conditions stay independent.
  * Surface Pro 7+: provided by the Type Cover itself ("Microsoft Surface Type
    Cover Tablet Mode Switch", a name shared by ten kernel devices there, only
    one of which exposes SW_TABLET_MODE). Detaching removes the switch, so the
    two conditions collapse into one.

A missing switch therefore means "no cover", not "not in tablet mode" -- which
the predicate below already handles, since it asks whether a usable keyboard is
present rather than trusting the switch alone.

This publishes hardware state rather than acting on it: /run/omarchy-tablet-mode
holds the current values and every executable in /etc/omarchy-tablet-mode.d/ is
run on each transition with them in the environment. An on-screen keyboard is
the first consumer, shipped as a hook; rotation lock and the lock screen
plausibly want the same signal.

Runs as root from a system unit so it can read /dev/input directly.
"""

import glob
import os
import pwd
import select
import shlex
import signal
import subprocess
import sys
from ctypes import CDLL, c_int, c_char_p, c_uint32, get_errno

import evdev
from evdev import ecodes as e

TARGET_UID = int(os.environ.get("TARGET_UID", "1000"))
# Not TARGET_UID: a primary group is not reliably the same id as the user
# (useradd -g users gives the shared users group).
try:
    TARGET_GID = pwd.getpwuid(TARGET_UID).pw_gid
except KeyError:
    TARGET_GID = TARGET_UID
RUNTIME_DIR = os.environ.get("USER_XDG_RUNTIME_DIR", f"/run/user/{TARGET_UID}")

# Buses a keyboard can actually be detached from. An x86 machine enumerates an
# "AT Translated Set 2 keyboard" on i8042 whether or not anything is plugged
# into it, so matching alphabetic keys alone reports a keyboard that is not
# there.
HOTPLUG_BUSES = (0x03, 0x05)  # BUS_USB, BUS_BLUETOOTH
ALPHA_KEYS = {e.KEY_A, e.KEY_Q, e.KEY_Z}

STATE_FILE = os.environ.get("TABLET_MODE_STATE_FILE", "/run/omarchy-tablet-mode")
HOOK_DIR = os.environ.get("TABLET_MODE_HOOK_DIR", "/etc/omarchy-tablet-mode.d")

def log(*a):
    print(*a, flush=True)


def _devices():
    for path in evdev.list_devices():
        try:
            yield evdev.InputDevice(path)
        except OSError:
            continue


def find_tablet_switch():
    """The one EV_SW device exposing SW_TABLET_MODE, by capability not name."""
    for dev in _devices():
        caps = dev.capabilities().get(e.EV_SW) or []
        if e.SW_TABLET_MODE in caps:
            return dev
    return None


def read_tablet_mode(dev):
    """Current switch state. EVIOCGSW, because events only report changes."""
    import array
    import fcntl
    buf = array.array("B", [0] * 8)
    fcntl.ioctl(dev.fd, 0x8008451B, buf)  # EVIOCGSW(8)
    bits = int.from_bytes(buf.tobytes(), "little")
    return bool((bits >> e.SW_TABLET_MODE) & 1)


def keyboard_attached():
    """A keyboard with letters, on a bus it could be unplugged from."""
    for dev in _devices():
        keys = set(dev.capabilities().get(e.EV_KEY, []))
        if ALPHA_KEYS <= keys and dev.info.bustype in HOTPLUG_BUSES:
            return True
    return False


def publish(state):
    """Write the state where anything else can read it, atomically."""
    body = "".join(f"{k}={v}\n" for k, v in state.items())
    tmp = f"{STATE_FILE}.tmp"
    with open(tmp, "w") as fh:
        fh.write(body)
    os.replace(tmp, STATE_FILE)
    os.chmod(STATE_FILE, 0o644)


# sysexits.h EX_TEMPFAIL. A hook returns this to say "I understood the state but
# could not act on it yet" -- typically because no graphical session exists. The
# daemon then re-runs hooks on its next wake even if the hardware has not
# changed, which is what makes booting with the cover already folded work: the
# first run cannot start a keyboard, and nothing about the hardware changes when
# the user later logs in.
EX_TEMPFAIL = 75


def run_hooks(state):
    """Run every executable in HOOK_DIR with the state in the environment.

    Hooks are how anything else reacts to tablet mode: the on-screen keyboard
    is simply the first one. A hook that fails is logged and does not stop the
    others.

    Returns True if any hook deferred (EX_TEMPFAIL).
    """
    deferred = False
    try:
        names = sorted(os.listdir(HOOK_DIR))
    except FileNotFoundError:
        return False
    env = {**os.environ, **{k: str(v) for k, v in state.items()},
           "TARGET_UID": str(TARGET_UID), "TARGET_GID": str(TARGET_GID),
           "USER_XDG_RUNTIME_DIR": RUNTIME_DIR}
    for name in names:
        path = os.path.join(HOOK_DIR, name)
        if not os.access(path, os.X_OK) or os.path.isdir(path):
            continue
        try:
            r = subprocess.run([path], env=env, capture_output=True, text=True, timeout=15)
            if r.returncode == EX_TEMPFAIL:
                deferred = True
                log(f"hook {name} deferred: {(r.stdout or r.stderr).strip()[:160]}")
            elif r.returncode != 0:
                log(f"hook {name} exited {r.returncode}: {r.stderr.strip()[:200]}")
        except Exception as exc:
            log(f"hook {name} failed: {exc}")
    return deferred


_last = None
_deferred = False


def apply(switch):
    """Publish state; run hooks on change, or again while one is deferred."""
    global _last, _deferred
    tablet = read_tablet_mode(switch) if switch else False
    kbd = keyboard_attached()
    state = {
        "TABLET_MODE": int(tablet),
        "KEYBOARD_ATTACHED": int(kbd),
        # The question consumers usually want answered, derived once here so
        # every hook agrees: a missing switch means "no cover", not "not folded".
        "KEYBOARD_USABLE": int(kbd and not tablet),
    }
    publish(state)
    changed = state != _last
    if changed:
        log(f"tablet={state['TABLET_MODE']} keyboard_attached={state['KEYBOARD_ATTACHED']} "
            f"keyboard_usable={state['KEYBOARD_USABLE']}")
        _last = state
    # Re-running while deferred is what covers booting with the cover already
    # folded: the hardware never changes when the user logs in, so waiting for a
    # state change would leave the machine with no keyboard and no way to ask
    # for one. logind touches /dev/input at session start, which wakes us.
    if changed or _deferred:
        _deferred = run_hooks(state)


def inotify_devinput():
    """Watch /dev/input so attach and detach need no udev dependency."""
    libc = CDLL("libc.so.6", use_errno=True)
    libc.inotify_init1.restype = c_int
    libc.inotify_add_watch.argtypes = [c_int, c_char_p, c_uint32]
    fd = libc.inotify_init1(0o4000)  # IN_NONBLOCK
    if fd < 0:
        raise OSError(get_errno(), "inotify_init1")
    IN_CREATE, IN_DELETE, IN_ATTRIB = 0x100, 0x200, 0x4
    if libc.inotify_add_watch(fd, b"/dev/input", IN_CREATE | IN_DELETE | IN_ATTRIB) < 0:
        raise OSError(get_errno(), "inotify_add_watch")
    return fd


def main():
    # Let the kernel reap the keyboard process when it exits. Without this the
    # daemon leaves a zombie behind, and pgrep matches zombies -- so osk_running()
    # would report the keyboard as running forever and never start it again.
    signal.signal(signal.SIGCHLD, signal.SIG_IGN)

    ino = inotify_devinput()
    switch = find_tablet_switch()
    log(f"tablet switch: {switch.name if switch else 'none (treating as no cover)'}")
    apply(switch)

    while True:
        fds = [ino] + ([switch.fd] if switch else [])
        try:
            ready, _, _ = select.select(fds, [], [], None)
        except (OSError, ValueError):
            switch = find_tablet_switch()
            continue

        if ino in ready:
            os.read(ino, 4096)
            # A device appeared or vanished: the switch itself may be gone on
            # models where it lives in the cover.
            new = find_tablet_switch()
            if (new is None) != (switch is None) or (
                new and switch and new.path != switch.path
            ):
                log(f"tablet switch now: {new.name if new else 'none'}")
                switch = new

        if switch and switch.fd in ready:
            try:
                for _ in switch.read():
                    pass
            except OSError:
                switch = find_tablet_switch()

        apply(switch)


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(0)
