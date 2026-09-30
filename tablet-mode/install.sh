#!/bin/bash
# Runs an on-screen keyboard only while the physical keyboard is unusable:
# the Type Cover detached, or folded back behind the screen.
#
# Not part of --all: it changes behaviour for anyone who relies on the keyboard
# being available to toggle at any time.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../lib.sh

require_cmd python3
require_cmd setpriv "Part of util-linux; should already be present."
python3 -c "import evdev" 2>/dev/null || die "python-evdev is required. Install with: sudo pacman -S python-evdev"

if ! python3 - <<'PY'
import sys, evdev
from evdev import ecodes as e
for p in evdev.list_devices():
    try: d = evdev.InputDevice(p)
    except OSError: continue
    if e.SW_TABLET_MODE in (d.capabilities().get(e.EV_SW) or []):
        print(f"Found tablet-mode switch: {d.name} ({p})"); sys.exit(0)
sys.exit(1)
PY
then
  warn "No device exposing SW_TABLET_MODE was found."
  warn "Detach/fold detection will fall back to whether a keyboard is attached,"
  warn "which still works, but folding the cover back will not be detected."
  warn "Run this as root if you are not in the 'input' group -- the switch may"
  warn "simply not be readable as your user."
fi

install_bin omarchy-tablet-mode.py
install_system_unit omarchy-tablet-mode.service

# Hooks are how anything else consumes tablet mode. The on-screen keyboard is
# shipped as the first one; drop your own scripts alongside it.
sudo install -d -m 755 /etc/omarchy-tablet-mode.d
for hook in hooks/*; do
  sudo install -m 755 "$hook" "/etc/omarchy-tablet-mode.d/$(basename "$hook")"
  info "Installed /etc/omarchy-tablet-mode.d/$(basename "$hook")"
done

sudo systemctl daemon-reload
sudo systemctl enable omarchy-tablet-mode.service
sudo systemctl restart omarchy-tablet-mode.service

info "omarchy-tablet-mode.service is running."
info "State is published to /run/omarchy-tablet-mode and hooks run from"
info "  /etc/omarchy-tablet-mode.d/ on every transition."
info "Change the keyboard: sudo systemctl edit omarchy-tablet-mode.service"
info "  [Service]"
info "  Environment=\"OSK_COMMAND=squeekboard\""
