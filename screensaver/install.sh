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

install_bin screensaver-touch-helper.py
install_user_unit screensaver-touch-helper.service

systemctl --user daemon-reload
systemctl --user enable --now screensaver-touch-helper.service

info "screensaver-touch-helper.service is running."
info "Override the touch device name with: systemctl --user edit screensaver-touch-helper.service"
