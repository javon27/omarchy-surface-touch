#!/bin/bash
# Installs the virtual trackpad: a root uinput injector service (mouse/scroll/
# key events) plus a Quickshell panel you toggle with a keybind. Also used by
# the screensaver touch-dismiss helper -- install this even if you don't plan
# to use the on-screen trackpad panel yourself.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../lib.sh

require_cmd python3
require_cmd quickshell "Install with: sudo pacman -S quickshell (Omarchy ships this already; on plain Arch: yay -S quickshell)"
python3 -c "import evdev" 2>/dev/null || die "python-evdev is required. Install with: sudo pacman -S python-evdev"

install_bin trackpad-injector.py
install_system_unit trackpad-injector.service

mkdir -p "$HOME/.config/omarchy/trackpad"
cp shell.qml "$HOME/.config/omarchy/trackpad/shell.qml"
install_bin omarchy-toggle-trackpad

sudo systemctl daemon-reload
sudo systemctl enable --now trackpad-injector.service

info "Trackpad panel installed. Toggle it with: omarchy-toggle-trackpad"
info "Bind a key to it -- see ../hypr/bindings.snippet.lua (SUPER+SHIFT+T by default)."
