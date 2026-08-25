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
import os
import socket
import subprocess
import threading
import time

import evdev
from evdev import ecodes as e

TOUCH_DEVICE_NAME = os.environ.get("TOUCH_DEVICE_NAME", "IPTSD Virtual Touchscreen 045E:0C1A")
SOCKET_PATH = "/run/trackpad.sock"
OSK_STATE_FILE = "/tmp/osk-visible"
TRACKPAD_MARKER = "omarchy/trackpad/shell.qml"


def log(msg):
    print(msg, flush=True)


def screensaver_active():
    r = subprocess.run(["pgrep", "-f", "org.omarchy.screensaver"], capture_output=True)
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
    subprocess.run(["pkill", "-SIGUSR1", "wvkbd-deskintl"])
    try:
        os.remove(OSK_STATE_FILE)
    except FileNotFoundError:
        pass
    subprocess.run(["pkill", "-f", TRACKPAD_MARKER])
    subprocess.run(
        ["bash", "-c", 'hyprctl eval "hl.config({ cursor = { hide_on_touch = true } })" >/dev/null 2>&1']
    )


def find_touch_device():
    for path in evdev.list_devices():
        d = evdev.InputDevice(path)
        if d.name == TOUCH_DEVICE_NAME:
            return d
    return None


def wait_for_touch_device():
    while True:
        dev = find_touch_device()
        if dev is not None:
            return dev
        log(f"waiting for touch device '{TOUCH_DEVICE_NAME}'...")
        time.sleep(2)


def poll_screensaver_state():
    was_active = False
    while True:
        active = screensaver_active()
        if active and not was_active:
            hide_osk_and_trackpad()
        was_active = active
        time.sleep(1)


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
    watch_touch_for_dismiss()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
