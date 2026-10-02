#!/usr/bin/env python3
"""Relative-mouse + key injector for the virtual trackpad panel and the
screensaver touch-dismiss helper.

Runs as root (needs /dev/uinput). Listens on a Unix socket for simple
text commands and injects them via virtual uinput devices -- the same
kind of devices a real trackpad/keyboard present, so every app handles
them identically (click-and-drag selection included, since this
sidesteps Wayland's touch protocol entirely). Serves multiple concurrent
client connections (the trackpad panel holds one open persistently; other
tools connect one-shot).

Protocol: newline-delimited commands over the socket:
  MOVE <dx> <dy>       relative pointer motion
  SCROLL <dx> <dy>     high-res scroll wheel motion (two-finger drag)
  CLICK left|right|middle    press+release a mouse button
  DOWN left|right|middle       press and hold a mouse button
  UP left|right|middle           release a held mouse button
  KEY <name>            press+release a keyboard key (e.g. "KEY esc")
"""
import os
import socket
import struct
import threading

from evdev import ecodes as e, UInput

SOCKET_PATH = "/run/trackpad.sock"

# struct ucred: pid, uid, gid, as returned by SO_PEERCRED.
_UCRED = struct.Struct("3i")

BUTTONS = {"left": e.BTN_LEFT, "right": e.BTN_RIGHT, "middle": e.BTN_MIDDLE}
KEYS = {"esc": e.KEY_ESC, "space": e.KEY_SPACE}


def log(msg):
    print(msg, flush=True)


def allowed_uids():
    """Which uids may drive the injector.

    This process runs as root and writes to /dev/uinput, so a client that
    reaches the socket can synthesize pointer motion and clicks into the
    session. That includes clicking the lock screen's own PIN keypad, so the
    socket has to be restricted to the session it belongs to.

    TARGET_UID comes from the unit, rendered at install time, the same way
    screensaver-touch-helper.service gets it.
    """
    env = os.environ.get("TARGET_UID", "")
    if env.isdigit():
        return {0, int(env)}

    # A unit installed before TARGET_UID was added, i.e. an upgrade without
    # re-running install.sh. Recover when the answer is unambiguous rather
    # than leaving the socket open to everyone.
    try:
        uids = {int(n) for n in os.listdir("/run/user") if n.isdigit()}
    except OSError:
        uids = set()
    if len(uids) == 1:
        uid = uids.pop()
        log(f"TARGET_UID unset, using uid {uid} from /run/user; re-run trackpad/install.sh")
        return {0, uid}
    raise SystemExit(
        "TARGET_UID is not set and the session uid is ambiguous. "
        "Re-run trackpad/install.sh to reinstall the unit."
    )


def peer_uid(conn):
    creds = conn.getsockopt(socket.SOL_SOCKET, socket.SO_PEERCRED, _UCRED.size)
    _pid, uid, _gid = _UCRED.unpack(creds)
    return uid


def main():
    ui = UInput(
        {
            e.EV_KEY: [e.BTN_LEFT, e.BTN_RIGHT, e.BTN_MIDDLE] + list(KEYS.values()),
            e.EV_REL: [e.REL_X, e.REL_Y, e.REL_WHEEL, e.REL_HWHEEL, e.REL_WHEEL_HI_RES, e.REL_HWHEEL_HI_RES],
        },
        name="virtual-trackpad",
    )
    ui_lock = threading.Lock()
    log("Virtual trackpad injector ready")

    # Accumulate hi-res scroll units so we can also emit a correctly-paced
    # legacy REL_WHEEL/REL_HWHEEL step every 120 units, for apps/toolkits
    # that only understand the old low-res wheel events.
    scroll_accum = {"v": 0.0, "h": 0.0}

    uids = allowed_uids()
    session_uid = max(uids)

    if os.path.exists(SOCKET_PATH):
        os.remove(SOCKET_PATH)

    srv = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
    # connect() needs write permission on the inode, so the mode is the first
    # line of defence. Set it through the umask rather than chmod-ing after
    # bind: a chmod leaves a window in which the socket exists world-writable.
    old_umask = os.umask(0o177)
    try:
        srv.bind(SOCKET_PATH)
    finally:
        os.umask(old_umask)
    if session_uid:
        os.chown(SOCKET_PATH, session_uid, -1)
    srv.listen(5)
    log(f"Listening on {SOCKET_PATH} for uids {sorted(uids)}")

    def handle_command(line):
        parts = line.split()
        if not parts:
            return
        cmd = parts[0]
        with ui_lock:
            if cmd == "MOVE" and len(parts) == 3:
                dx, dy = int(parts[1]), int(parts[2])
                ui.write(e.EV_REL, e.REL_X, dx)
                ui.write(e.EV_REL, e.REL_Y, dy)
                ui.syn()
            elif cmd == "SCROLL" and len(parts) == 3:
                dx, dy = int(parts[1]), int(parts[2])
                if dy != 0:
                    ui.write(e.EV_REL, e.REL_WHEEL_HI_RES, dy)
                    scroll_accum["v"] += dy
                    while abs(scroll_accum["v"]) >= 120:
                        step = 1 if scroll_accum["v"] > 0 else -1
                        ui.write(e.EV_REL, e.REL_WHEEL, step)
                        scroll_accum["v"] -= step * 120
                if dx != 0:
                    # REL_HWHEEL's positive direction is inverted relative to
                    # REL_WHEEL's by evdev convention -- negate to match the
                    # natural-scroll feel already correct on the vertical axis.
                    hdx = -dx
                    ui.write(e.EV_REL, e.REL_HWHEEL_HI_RES, hdx)
                    scroll_accum["h"] += hdx
                    while abs(scroll_accum["h"]) >= 120:
                        step = 1 if scroll_accum["h"] > 0 else -1
                        ui.write(e.EV_REL, e.REL_HWHEEL, step)
                        scroll_accum["h"] -= step * 120
                ui.syn()
            elif cmd == "CLICK" and len(parts) == 2 and parts[1] in BUTTONS:
                btn = BUTTONS[parts[1]]
                ui.write(e.EV_KEY, btn, 1)
                ui.syn()
                ui.write(e.EV_KEY, btn, 0)
                ui.syn()
            elif cmd == "DOWN" and len(parts) == 2 and parts[1] in BUTTONS:
                ui.write(e.EV_KEY, BUTTONS[parts[1]], 1)
                ui.syn()
            elif cmd == "UP" and len(parts) == 2 and parts[1] in BUTTONS:
                ui.write(e.EV_KEY, BUTTONS[parts[1]], 0)
                ui.syn()
            elif cmd == "KEY" and len(parts) == 2 and parts[1] in KEYS:
                key = KEYS[parts[1]]
                ui.write(e.EV_KEY, key, 1)
                ui.syn()
                ui.write(e.EV_KEY, key, 0)
                ui.syn()
            else:
                log(f"unrecognized command: {line!r}")

    def handle_client(conn):
        buf = b""
        try:
            with conn:
                while True:
                    chunk = conn.recv(4096)
                    if not chunk:
                        break
                    buf += chunk
                    while b"\n" in buf:
                        line, buf = buf.split(b"\n", 1)
                        try:
                            handle_command(line.decode("utf-8", "ignore").strip())
                        except Exception as ex:
                            log(f"error handling {line!r}: {ex}")
        except Exception as ex:
            log(f"connection error: {ex}")

    while True:
        conn, _ = srv.accept()
        # The mode should already have stopped anyone else, but check the peer
        # too: the mode depends on install-time ownership being right, and this
        # does not.
        try:
            uid = peer_uid(conn)
        except OSError as ex:
            log(f"could not read peer credentials, refusing: {ex}")
            conn.close()
            continue
        if uid not in uids:
            log(f"refused connection from uid {uid}")
            conn.close()
            continue
        threading.Thread(target=handle_client, args=(conn,), daemon=True).start()


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        pass
