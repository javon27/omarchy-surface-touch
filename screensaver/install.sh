#!/bin/bash
# Installs the screensaver touch helper as a user systemd service. Requires
# the trackpad injector (../trackpad/) to already be installed and running --
# this dismisses the screensaver by sending a synthetic Escape key through
# the injector's virtual keyboard device, since omarchy-screensaver only
# reads real keyboard/mouse input to exit.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../lib.sh

require_cmd python3
python3 -c "import evdev" 2>/dev/null || die "python-evdev is required. Install with: sudo pacman -S python-evdev"

if ! systemctl is-active --quiet trackpad-injector.service 2>/dev/null; then
  warn "trackpad-injector.service isn't running yet -- install ../trackpad/ first (dismiss-by-touch needs it)."
fi

install_root_bin screensaver-touch-helper.py

# Earlier versions installed this as a user unit, where it could never read the
# touchscreen. Clear that out first, or the stale copy keeps running alongside
# the system one and keeps logging the same failure.
if [[ -e "$HOME/.config/systemd/user/screensaver-touch-helper.service" ]]; then
  info "Removing the old user-scoped unit (it could not read /dev/input)."
  systemctl --user disable --now screensaver-touch-helper.service >/dev/null 2>&1 || true
  rm -f "$HOME/.config/systemd/user/screensaver-touch-helper.service"
  systemctl --user daemon-reload || true
fi

install_system_unit screensaver-touch-helper.service

sudo systemctl daemon-reload
# `enable --now` starts the unit only if it is not already running, so on an
# upgrade it reports success while leaving the previous process and the old
# script loaded. Enable, then restart explicitly.
sudo systemctl enable screensaver-touch-helper.service
sudo systemctl restart screensaver-touch-helper.service

info "screensaver-touch-helper.service is running (system unit, runs as root)."
info "Override the touch device name with: sudo systemctl edit screensaver-touch-helper.service"
