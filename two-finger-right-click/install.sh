#!/bin/bash
# Installs the two-finger-tap-to-right-click daemon as a system service.
# Needs root (via a system unit, not a user unit) because it opens the raw
# touchscreen device and creates a /dev/uinput virtual pointer -- see
# README.md for why this needs root instead of a udev/group rule.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../lib.sh

require_cmd python3
python3 -c "import evdev" 2>/dev/null || die "python-evdev is required. Install with: sudo pacman -S python-evdev"

install_root_bin two-finger-right-click.py
install_system_unit two-finger-rightclick.service

sudo systemctl daemon-reload
# `enable --now` starts the unit only if it is not already running, so on an
# upgrade it reports success while leaving the previous process and the old
# script loaded. Enable, then restart explicitly.
sudo systemctl enable two-finger-rightclick.service
sudo systemctl restart two-finger-rightclick.service
info "two-finger-rightclick.service is running. Tap two fingers on the touchscreen to right-click."
info "Customize via env vars in 'sudo systemctl edit two-finger-rightclick.service':"
info "  TOUCH_DEVICE_NAME (autodetected; only needed to disambiguate), TAP_MAX_DURATION_MS,"
info "  SECOND_FINGER_WINDOW_MS, MOVE_FUZZ_PERCENT"
