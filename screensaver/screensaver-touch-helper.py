#!/usr/bin/env python3
"""Two jobs while the Omarchy screensaver (a terminal running omarchy-screensaver,
window class org.omarchy.screensaver) is up:

1. Hide the OSK and virtual trackpad panels -- they're on the Overlay layer,
   above the screensaver's regular toplevel window, so they'd otherwise stay
   visible on top of it.
2. Dismiss the screensaver on any touch. omarchy-screensaver only reads
   keyboard/mouse input to exit (`read -n1 -t 1` in its own loop) -- touch
   alone can't reach that, so this injects a keypress via the trackpad
   injector's virtual keyboard device instead.
"""
import glob
import os
import select
import socket
import subprocess
import threading
import time

import evdev
from evdev import ecodes as e

TOUCH_DEVICE_NAME = os.environ.get("TOUCH_DEVICE_NAME")  # optional override
SOCKET_PATH = "/run/trackpad.sock"

# This runs as root (see the unit), so nothing about the user's session is in
# the environment and every process lookup would otherwise match all users.
RUNTIME_DIR = os.environ.get("USER_XDG_RUNTIME_DIR", "/run/user/1000")
TARGET_UID = os.environ.get("TARGET_UID")
OSK_STATE_FILE = "/tmp/osk-visible"
TRACKPAD_MARKER = "omarchy/trackpad/shell.qml"

# Devices this project creates through uinput. Watching them would let the
# on-screen trackpad panel dismiss the screensaver it is hidden behind, and
# risks a loop with the very injector this helper sends Escape through.
OWN_UINPUT_NAMES = {"virtual-trackpad", "two-finger-right-click"}

# How far a pointer must travel before it counts as deliberate. A palm resting
# on the touchpad or a jittery sensor should not dismiss the screensaver; a
# jiggle should. Expressed in millimetres because absolute devices report a
# resolution in units/mm (20 on a Surface Type Cover).
POINTER_MOVE_MM = float(os.environ.get("POINTER_MOVE_MM", "5.0"))
# Relative devices report arbitrary counts with no physical scale.
REL_MOVE_COUNTS = int(os.environ.get("REL_MOVE_COUNTS", "25"))
CLICK_BUTTONS = {e.BTN_LEFT, e.BTN_RIGHT, e.BTN_MIDDLE}
# How long to wait before noticing a mouse that was plugged in later.
RESCAN_SECONDS = 2.0
# The screensaver takes a moment to exit after the first Escape. Without a
# guard, continued motion keeps injecting Escape, and those extra presses land
# in whatever application the screensaver was covering.
DISMISS_COOLDOWN = 1.5


def log(msg):
    print(msg, flush=True)


def _uid_scope():
    """Restrict pgrep/pkill to the session user, since root sees every process."""
    return ["-u", TARGET_UID] if TARGET_UID else []


def hyprctl_eval(lua):
    """Run `hyprctl eval` against the user's compositor.

    As root there is no HYPRLAND_INSTANCE_SIGNATURE in the environment, so find
    the instance on disk and pass it in -- the same approach
    two-finger-right-click.py uses. Returns False when no compositor is up yet,
    which is normal at boot: this unit is ordered after multi-user.target, not
    after the graphical session.
    """
    for sock_dir in glob.glob(f"{RUNTIME_DIR}/hypr/*"):
        try:
            r = subprocess.run(
                ["hyprctl", "eval", lua],
                env={**os.environ,
                     "HYPRLAND_INSTANCE_SIGNATURE": os.path.basename(sock_dir),
                     "XDG_RUNTIME_DIR": RUNTIME_DIR},
                capture_output=True, text=True, timeout=2,
            )
            if r.returncode == 0:
                return True
        except Exception:
            continue
    return False


def screensaver_active():
    r = subprocess.run(["pgrep", *_uid_scope(), "-f", "org.omarchy.screensaver"],
                       capture_output=True)
    return r.returncode == 0


def send_injector(cmd):
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(1)
        s.connect(SOCKET_PATH)
        s.sendall((cmd + "\n").encode())
        s.close()
    except Exception as ex:
        log(f"injector send failed: {ex}")


def hide_osk_and_trackpad():
    log("screensaver activated -- hiding OSK/trackpad")
    subprocess.run(["pkill", "--signal", "USR1", *_uid_scope(), "wvkbd-deskintl"])
    try:
        os.remove(OSK_STATE_FILE)
    except FileNotFoundError:
        pass
    subprocess.run(["pkill", *_uid_scope(), "-f", TRACKPAD_MARKER])
    hyprctl_eval("hl.config({ cursor = { hide_on_touch = true } })")


def _multitouch_devices():
    """Direct-input multitouch devices, i.e. touchscreens.

    ABS_MT_SLOT alone is not enough -- a precision touchpad reports it too, so
    on a Surface with the Type Cover attached there are two matches and neither
    is unambiguous. The kernel separates them with INPUT_PROP_DIRECT (the
    surface you touch is the display) versus INPUT_PROP_POINTER (an indirect
    pointing device), which is the same signal libinput keys off.
    """
    found = []
    for path in evdev.list_devices():
        try:
            d = evdev.InputDevice(path)
        except OSError:
            continue
        caps = d.capabilities().get(e.EV_ABS) or []
        if not any(code == e.ABS_MT_SLOT for code, _ in caps):
            continue
        try:
            if e.INPUT_PROP_DIRECT not in d.input_props():
                continue
        except Exception:
            pass  # no property info from this driver; keep it as a candidate
        found.append(d)
    return found


def _all_device_names():
    names = []
    for path in evdev.list_devices():
        try:
            names.append(evdev.InputDevice(path).name)
        except OSError:
            continue
    return names


def find_touch_device():
    if TOUCH_DEVICE_NAME:
        for path in evdev.list_devices():
            try:
                d = evdev.InputDevice(path)
            except OSError:
                continue
            if d.name == TOUCH_DEVICE_NAME:
                return d
        return None
    candidates = _multitouch_devices()
    return candidates[0] if len(candidates) == 1 else None


def _report_no_device():
    """Say what was expected, what was found, and -- crucially -- why.

    The old code logged only "waiting for touch device ..." every 2s forever,
    which is indistinguishable from the service working. There are two very
    different causes and the message separates them: a device name that matches
    nothing (different Surface model), and no read access to /dev/input at all
    (which should only happen now if this ends up running unprivileged).
    """
    visible = evdev.list_devices()
    if not visible and glob.glob("/dev/input/event*"):
        log("ERROR: cannot read any /dev/input/event* node.")
        if os.geteuid() != 0:
            log("  Not running as root. This must be installed as a system unit")
            log("  (screensaver/install.sh does that) -- /dev/input/* is root:input,")
            log("  and logind hands the compositor its devices over D-Bus rather than")
            log("  through file permissions, so as your user nothing is visible here.")
        else:
            log("  Running as root but still seeing nothing, which is unexpected --")
            log("  check that the touchscreen driver is up (iptsd, hid-multitouch).")
        return

    if TOUCH_DEVICE_NAME:
        log(f"ERROR: no input device is named {TOUCH_DEVICE_NAME!r} (from TOUCH_DEVICE_NAME).")
    else:
        log("ERROR: could not identify the touchscreen automatically.")
    cands = _multitouch_devices()
    if len(cands) > 1:
        log("  more than one multitouch device found -- set TOUCH_DEVICE_NAME to one of:")
        for d in cands:
            log(f"    {d.name!r}  ({d.path})")
    elif not cands:
        log("  no direct-input multitouch device found. Is the touchscreen driver up (iptsd, hid-multitouch)?")
    names = _all_device_names()
    log("  input devices present: " + (", ".join(repr(n) for n in names) if names else "(none)"))


def wait_for_touch_device():
    reported = False
    while True:
        dev = find_touch_device()
        if dev is not None:
            log(f"using touch device {dev.name!r} ({dev.path})")
            return dev
        if not reported:
            _report_no_device()
            reported = True
        time.sleep(2)


# Updated once a second by poll_screensaver_state(). screensaver_active() shells
# out to pgrep, which is far too expensive to call per input event -- the
# pointer watcher wakes on every movement the touchpad reports.
_screensaver_active = False


def poll_screensaver_state():
    global _screensaver_active
    was_active = False
    while True:
        active = screensaver_active()
        _screensaver_active = active
        if active and not was_active:
            hide_osk_and_trackpad()
        was_active = active
        time.sleep(1)


def _pointer_devices():
    """Pointing devices that are not the touchscreen: touchpads and mice.

    The mirror of _multitouch_devices(). INPUT_PROP_DIRECT means the surface you
    touch is the display itself, so excluding it drops the touchscreen and the
    stylus -- the stylus also reports INPUT_PROP_POINTER and would otherwise
    match here.
    """
    found = []
    for path in evdev.list_devices():
        try:
            d = evdev.InputDevice(path)
        except OSError:
            continue
        if d.name in OWN_UINPUT_NAMES:
            continue
        try:
            if e.INPUT_PROP_DIRECT in d.input_props():
                continue
        except Exception:
            pass
        caps = d.capabilities()
        rel = set(caps.get(e.EV_REL) or [])
        keys = set(caps.get(e.EV_KEY) or [])
        abs_codes = {c for c, _ in (caps.get(e.EV_ABS) or [])}
        try:
            props = set(d.input_props())
        except Exception:
            props = set()
        is_mouse = {e.REL_X, e.REL_Y} <= rel
        # Absolute axes alone are not enough: the raw uncalibrated touchscreen
        # HID node reports ABS_X/ABS_Y with no INPUT_PROP at all, so it looks
        # like a touchpad here even though INPUT_PROP_DIRECT never appears on
        # it. A real indirect pointing device carries INPUT_PROP_POINTER, or at
        # minimum a left button; that node carries neither.
        is_touchpad = bool({e.ABS_MT_POSITION_X, e.ABS_X} & abs_codes) and (
            e.INPUT_PROP_POINTER in props or e.BTN_LEFT in keys)
        if is_mouse or is_touchpad:
            found.append(d)
    return found


def _move_threshold(dev):
    """Motion counting as deliberate, in this device's own units."""
    absinfo = dict(dev.capabilities(absinfo=True).get(e.EV_ABS) or [])
    for code in (e.ABS_MT_POSITION_X, e.ABS_X):
        info = absinfo.get(code)
        if info is None:
            continue
        if info.resolution:
            return POINTER_MOVE_MM * info.resolution
        return max(1, (info.max - info.min) * 0.02)   # 2% of travel if unscaled
    return REL_MOVE_COUNTS


def watch_pointers_for_dismiss():
    """Dismiss the screensaver on deliberate trackpad or mouse input.

    omarchy-screensaver exits on a byte reaching its pty or on losing focus.
    Pointer motion and clicks produce neither -- a fullscreen window that is
    already focused stays focused, and nothing writes to the terminal -- so, as
    with touch, nothing happens unless a keypress is injected.

    Devices are rescanned periodically so a mouse plugged in after the helper
    started is picked up, and so a detached Type Cover stops being polled.
    """
    devs, thresh, moved, lastpos = {}, {}, {}, {}
    known = None
    last_dismiss = 0.0

    def dismiss(dev, why):
        """Send Escape once, then stay quiet while the screensaver goes away."""
        nonlocal last_dismiss
        now = time.time()
        for fd in moved:
            moved[fd] = 0.0
            lastpos[fd] = {}
        if now - last_dismiss < DISMISS_COOLDOWN:
            return
        if not screensaver_active():      # confirm before injecting a keypress
            return
        last_dismiss = now
        log(f"{dev.name!r} {why} during screensaver -- dismissing")
        send_injector("KEY esc")

    def rescan():
        nonlocal known
        paths = set(evdev.list_devices())
        if paths == known:
            return
        known = paths
        for fd in list(devs):
            if devs[fd].path not in paths:
                # Close it: a Surface Type Cover is detached and reattached
                # often enough that leaked descriptors would accumulate.
                try:
                    devs[fd].close()
                except Exception:
                    pass
                devs.pop(fd, None); thresh.pop(fd, None)
                moved.pop(fd, None); lastpos.pop(fd, None)
        have = {d.path for d in devs.values()}
        for d in _pointer_devices():
            if d.path in have:
                continue
            devs[d.fd] = d
            thresh[d.fd] = _move_threshold(d)
            moved[d.fd] = 0.0
            lastpos[d.fd] = {}
            log(f"watching pointer {d.name!r} ({d.path}), "
                f"move threshold {thresh[d.fd]:.0f} units")

    rescan()
    if not devs:
        log("no pointer devices found; trackpad/mouse dismiss inactive")

    while True:
        try:
            ready, _, _ = select.select(list(devs), [], [], RESCAN_SECONDS)
        except (OSError, ValueError):
            rescan()
            continue
        if not ready:
            rescan()
            continue

        # Cheap gate: the cached flag costs nothing, and the exact check only
        # runs at the moment we would actually inject a keypress.
        active = _screensaver_active
        for fd in ready:
            dev = devs.get(fd)
            if dev is None:
                continue
            try:
                events = list(dev.read())
            except OSError:
                rescan()
                continue
            if not active:
                # Motion before the screensaver appeared must not carry over.
                moved[fd] = 0.0
                lastpos[fd] = {}
                continue
            for ev in events:
                if ev.type == e.EV_KEY and ev.code in CLICK_BUTTONS and ev.value == 1:
                    dismiss(dev, "click")
                    break
                if ev.type == e.EV_REL and ev.code in (e.REL_X, e.REL_Y):
                    moved[fd] += abs(ev.value)
                elif ev.type == e.EV_ABS and ev.code in (
                        e.ABS_MT_POSITION_X, e.ABS_MT_POSITION_Y, e.ABS_X, e.ABS_Y):
                    prev = lastpos[fd].get(ev.code)
                    lastpos[fd][ev.code] = ev.value
                    if prev is not None:
                        moved[fd] += abs(ev.value - prev)
                if moved[fd] >= thresh[fd]:
                    dismiss(dev, "moved")
                    break


def watch_touch_for_dismiss():
    dev = wait_for_touch_device()
    log(f"watching {dev.path} for dismiss taps")
    for ev in dev.read_loop():
        if ev.type == e.EV_ABS and ev.code == e.ABS_MT_TRACKING_ID and ev.value != -1:
            if screensaver_active():
                log("touch detected during screensaver -- dismissing")
                send_injector("KEY esc")


def main():
    threading.Thread(target=poll_screensaver_state, daemon=True).start()
    threading.Thread(target=watch_pointers_for_dismiss, daemon=True).start()
    watch_touch_for_dismiss()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
