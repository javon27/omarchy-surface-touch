#!/bin/bash
# Installs accelerometer-driven auto-rotate as a user systemd service.
# IMPORTANT: auto-rotate.sh hardcodes this machine's monitor name, mode, and
# scale (MONITOR/MODE/SCALE at the top of the script) -- edit those for your
# hardware before or after installing. See README.md for how to find yours.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../lib.sh

require_cmd monitor-sensor "Install with: sudo pacman -S iio-sensor-proxy"
require_cmd hyprctl

install_bin auto-rotate.sh
install_bin omarchy-toggle-rotation-lock
install_user_unit auto-rotate.service

systemctl --user daemon-reload
systemctl --user enable --now auto-rotate.service

info "auto-rotate.service is running."
warn "Edit MONITOR/MODE/SCALE in ~/.local/bin/auto-rotate.sh if they don't match your display (see README.md)."
info "Lock/unlock rotation with: omarchy-toggle-rotation-lock -- bind a key to it in ~/.config/hypr/bindings.lua"
