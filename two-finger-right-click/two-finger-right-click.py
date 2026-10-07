#!/usr/bin/env python3
"""Two-finger-tap-to-right-click for the IPTS touchscreen.

Passively reads the touchscreen device (never grabs it -- all normal touch
events keep flowing to Hyprland untouched) and watches for exactly two
fingers touching down close together in time, staying nearly still, and
lifting quickly. On a clean tap, moves a synthetic absolute-positioning
virtual pointer (same pattern VNC/remote-desktop tools use) to the midpoint
of the two touch points and clicks BTN_RIGHT there -- Hyprland doesn't move
a persistent cursor position for real touch delivery, so a plain relative
click would land wherever a physical mouse/trackpad last parked it instead.
"""
import glob
import json
import os
import pwd
import subprocess
import time

import evdev
from evdev import AbsInfo, ecodes as e, UInput

DEVICE_NAME = os.environ.get("TOUCH_DEVICE_NAME")  # optional override
TAP_MAX_DURATION = int(os.environ.get("TAP_MAX_DURATION_MS", "350")) / 1000.0
SECOND_FINGER_WINDOW = int(os.environ.get("SECOND_FINGER_WINDOW_MS", "150")) / 1000.0
MOVE_FUZZ_PERCENT = float(os.environ.get("MOVE_FUZZ_PERCENT", "3.0"))

RUNTIME_DIR = os.environ.get("USER_XDG_RUNTIME_DIR", "/run/user/1000")


def _session_ids():
    """(uid, gid) of the session user, or None if it cannot be determined.

    Used to run hyprctl as that user instead of as root. The instance is
    located by globbing the user's runtime dir, which the user controls: a
    symlinked .socket.sock there would otherwise make root connect() -- which
    bypasses socket permissions -- to any unix socket on the machine. As the
    session user, hyprctl can only reach what that user could reach anyway.
    """
    raw = os.environ.get("TARGET_UID") or os.path.basename(RUNTIME_DIR.rstrip("/"))
    if not raw.isdigit() or int(raw) == 0:
        return None
    uid = int(raw)
    try:
        return uid, pwd.getpwuid(uid).pw_gid
    except KeyError:
        return None

# Apps that already have their own native two-finger-tap-to-context-menu (or
# similar) touch gesture. Firing our own synthetic right-click on top of
# theirs races against it -- whichever one opens a menu second ends up
# clicking into whatever the first one opened. Skip these and let the app's
# own gesture handle it.
NATIVE_GESTURE_APPS = [
    "chromium", "chrome", "firefox", "brave-browser", "brave",
    "microsoft-edge", "vivaldi", "opera",
]


def get_active_window_class():
    ids = _session_ids()
    if ids is None:
        return None
    for sock_dir in glob.glob(f"{RUNTIME_DIR}/hypr/*"):
        sig = os.path.basename(sock_dir)
        try:
            out = subprocess.run(
                ["hyprctl", "-j", "activewindow"],
                env={**os.environ, "HYPRLAND_INSTANCE_SIGNATURE": sig, "XDG_RUNTIME_DIR": RUNTIME_DIR},
                user=ids[0], group=ids[1], extra_groups=[],
                capture_output=True, text=True, timeout=1,
            )
            data = json.loads(out.stdout)
            if isinstance(data, dict) and "class" in data:
                return data["class"]
        except Exception:
            continue
    return None


def log(msg):
    print(msg, flush=True)


def _touchscreens():
    """Direct-input multitouch devices, i.e. touchscreens.

    ABS_MT_SLOT alone is not enough -- a precision touchpad reports it too, and
    binding to the Type Cover's touchpad here would be worse than finding
    nothing: every ordinary two-finger tap on the touchpad would fire a
    synthetic right-click on top of the touchpad's own gesture. The kernel
    separates the two with INPUT_PROP_DIRECT (you touch the display itself)
    versus INPUT_PROP_POINTER, which is what libinput keys off as well.

    Kept textually in step with screensaver-touch-helper.py's copy.
    """
    found = []
    for path in evdev.list_devices():
        try:
            dev = evdev.InputDevice(path)
        except OSError:
            continue
        caps = dev.capabilities().get(e.EV_ABS) or []
        if not any(code == e.ABS_MT_SLOT for code, _ in caps):
            continue
        try:
            if e.INPUT_PROP_DIRECT not in dev.input_props():
                continue
        except Exception:
            pass  # no property info from this driver; keep it as a candidate
        found.append(dev)
    return found


def find_device():
    if DEVICE_NAME:
        for path in evdev.list_devices():
            try:
                dev = evdev.InputDevice(path)
            except OSError:
                continue
            if dev.name == DEVICE_NAME:
                return dev
        return None
    candidates = _touchscreens()
    return candidates[0] if len(candidates) == 1 else None


def _report_no_device():
    """Name the cause instead of looping on one unchanging line.

    The old message repeated a hardcoded device name every two seconds, which
    on any model but a Pro 7+ was indistinguishable from working.
    """
    if not evdev.list_devices() and glob.glob("/dev/input/event*"):
        log("ERROR: cannot read any /dev/input/event* node -- this must run as root.")
        return
    if DEVICE_NAME:
        log(f"ERROR: no input device is named {DEVICE_NAME!r} (from TOUCH_DEVICE_NAME).")
    else:
        log("ERROR: could not identify the touchscreen automatically.")
    cands = _touchscreens()
    if len(cands) > 1:
        log("  more than one touchscreen found -- set TOUCH_DEVICE_NAME to one of:")
        for d in cands:
            log(f"    {d.name!r}  ({d.path})")
    elif not cands:
        log("  no direct-input multitouch device found. Is the touchscreen driver up (iptsd, hid-multitouch)?")


def wait_for_device():
    reported = False
    while True:
        dev = find_device()
        if dev is not None:
            return dev
        if not reported:
            _report_no_device()
            reported = True
        time.sleep(2)


def main():
    dev = wait_for_device()
    log(f"Watching {dev.path} ({dev.name})")

    x_info = dev.absinfo(e.ABS_MT_POSITION_X)
    y_info = dev.absinfo(e.ABS_MT_POSITION_Y)
    fuzz_x = (x_info.max - x_info.min) * MOVE_FUZZ_PERCENT / 100.0
    fuzz_y = (y_info.max - y_info.min) * MOVE_FUZZ_PERCENT / 100.0
    log(f"Move fuzz: {fuzz_x:.0f}x{fuzz_y:.0f} units "
        f"(axis range {x_info.min}-{x_info.max} x {y_info.min}-{y_info.max})")

    ui = UInput(
        {
            e.EV_KEY: [e.BTN_LEFT, e.BTN_RIGHT],
            e.EV_ABS: [
                (e.ABS_X, AbsInfo(value=0, min=x_info.min, max=x_info.max, fuzz=0, flat=0, resolution=0)),
                (e.ABS_Y, AbsInfo(value=0, min=y_info.min, max=y_info.max, fuzz=0, flat=0, resolution=0)),
            ],
        },
        name="two-finger-right-click",
    )

    slots = {}         # slot -> {'x': int|None, 'y': int|None}, only while finger is down
    last_pos = {}       # slot -> (x, y), kept until reset() even after lift
    start_pos = {}       # slot -> (x, y) captured at touch-down, for fuzz checking
    cur_slot = 0
    state = "idle"        # idle -> one-down -> two-down -> aborted
    gesture_start = None

    def reset():
        nonlocal state, gesture_start, start_pos, last_pos
        state = "idle"
        gesture_start = None
        start_pos = {}
        last_pos = {}

    def abort(reason):
        nonlocal state
        if state != "aborted":
            log(f"abort: {reason}")
        state = "aborted"

    def check_fuzz(slot):
        if slot not in slots:
            return
        cx, cy = slots[slot]['x'], slots[slot]['y']
        if cx is None or cy is None:
            return
        last_pos[slot] = (cx, cy)
        if slot not in start_pos:
            # First time we have both coords for this finger -- that's its
            # true starting point, whatever state we're in right now.
            start_pos[slot] = (cx, cy)
            return
        if state != "two-down":
            return
        sx, sy = start_pos[slot]
        if abs(cx - sx) > fuzz_x or abs(cy - sy) > fuzz_y:
            abort(f"finger {slot} moved too far")

    def fire_click():
        win_class = get_active_window_class()
        if win_class and any(app in win_class.lower() for app in NATIVE_GESTURE_APPS):
            log(f"skipping -- '{win_class}' has its own native two-finger-tap gesture")
            return
        xs = [p[0] for p in last_pos.values()]
        ys = [p[1] for p in last_pos.values()]
        if not xs or not ys:
            log("no recorded positions, skipping click")
            return
        mx = int(sum(xs) / len(xs))
        my = int(sum(ys) / len(ys))
        log(f"two-finger tap ({win_class}) -> right click at ({mx}, {my})")
        ui.write(e.EV_ABS, e.ABS_X, mx)
        ui.write(e.EV_ABS, e.ABS_Y, my)
        ui.syn()
        ui.write(e.EV_KEY, e.BTN_RIGHT, 1)
        ui.syn()
        time.sleep(0.01)
        ui.write(e.EV_KEY, e.BTN_RIGHT, 0)
        ui.syn()

    for ev in dev.read_loop():
        if ev.type == e.EV_ABS:
            if ev.code == e.ABS_MT_SLOT:
                cur_slot = ev.value

            elif ev.code == e.ABS_MT_TRACKING_ID:
                if ev.value == -1:
                    slots.pop(cur_slot, None)
                else:
                    slots[cur_slot] = {'x': None, 'y': None}
                    now = time.monotonic()
                    if state == "idle":
                        state = "one-down"
                        gesture_start = now
                    elif state == "one-down" and len(slots) == 2:
                        if now - gesture_start <= SECOND_FINGER_WINDOW:
                            state = "two-down"
                        else:
                            abort("second finger arrived too late")
                    else:
                        abort(f"unexpected finger down in state={state}")

            elif ev.code == e.ABS_MT_POSITION_X:
                if cur_slot in slots:
                    slots[cur_slot]['x'] = ev.value
                    check_fuzz(cur_slot)

            elif ev.code == e.ABS_MT_POSITION_Y:
                if cur_slot in slots:
                    slots[cur_slot]['y'] = ev.value
                    check_fuzz(cur_slot)

        elif ev.type == e.EV_SYN and ev.code == e.SYN_REPORT:
            if len(slots) == 0 and state != "idle":
                elapsed = (time.monotonic() - gesture_start) if gesture_start else None
                if state == "two-down" and elapsed is not None and elapsed <= TAP_MAX_DURATION:
                    fire_click()
                elif state == "two-down":
                    log(f"two-finger hold too long ({elapsed*1000:.0f}ms), not a tap")
                reset()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
