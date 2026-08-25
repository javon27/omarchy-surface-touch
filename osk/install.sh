#!/bin/bash
# Installs the on-screen keyboard: builds the patched wvkbd (see ../wvkbd/),
# installs the toggle script, and prints the Hyprland autostart/keybind
# snippets you need to add by hand (autostart.lua and bindings.lua are
# personal config files -- this won't edit yours for you).
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../lib.sh

require_cmd make
require_cmd cc

bash ../wvkbd/build.sh

install_bin omarchy-toggle-osk

cat <<EOF

==> Add to ~/.config/hypr/autostart.lua:

    o.launch_on_start("$HOME/.local/bin/wvkbd-deskintl --hidden -l full,special --landscape-layers full,special -H 470 -L 470")

==> Add to ~/.config/hypr/bindings.lua:

    o.bind("SUPER + SHIFT + K", "Toggle on-screen keyboard", "omarchy-toggle-osk")

See README.md for how to customize the layout, height, and other wvkbd flags.
EOF
