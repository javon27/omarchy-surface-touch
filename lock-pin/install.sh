#!/bin/bash
# Sets up a short numeric PIN for unlocking the lock screen by touch,
# completely decoupled from your real account password (a compromised PIN
# never exposes your login password, and vice versa), plus a Quickshell lock
# plugin with an on-screen PIN pad / QWERTY keyboard so the lock screen is
# unlockable with no physical keyboard attached.
#
# Prerequisite: Omarchy's own lock plugin system must already be present
# (it ships by default). This clones it rather than replacing it wholesale --
# see README.md for why, and for what "clonedFrom" means here.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../lib.sh

require_cmd openssl
require_cmd pacman

pacman -Qq libpam_pwdfile >/dev/null 2>&1 || die "libpam_pwdfile is required. Install with: yay -S libpam_pwdfile"

PIN_FILE=/etc/omarchy-lock-pin.pwd
PLUGIN_DIR="$HOME/.config/omarchy/plugins/touchlock"

if [[ -e $PIN_FILE ]]; then
  warn "$PIN_FILE already exists -- leaving it alone. Delete it first to set a new PIN."
else
  echo -n "Choose a numeric PIN (not your account password): "
  read -rs pin
  echo
  [[ $pin =~ ^[0-9]{4,}$ ]] || die "PIN must be 4+ digits."
  hash=$(openssl passwd -6 "$pin")
  unset pin
  printf '%s:%s\n' "$USER" "$hash" | sudo tee "$PIN_FILE" >/dev/null
  sudo chmod 600 "$PIN_FILE"
  sudo chown root:root "$PIN_FILE"
  info "Wrote $PIN_FILE"
fi

sudo cp omarchy-lock-password.pam /etc/pam.d/omarchy-lock-password
info "Installed /etc/pam.d/omarchy-lock-password"

mkdir -p "$PLUGIN_DIR"
cp plugin/*.qml plugin/manifest.json "$PLUGIN_DIR/"
info "Installed lock plugin to $PLUGIN_DIR"

cat <<'EOF'

==> Enable the plugin through Omarchy's own plugin settings (Setup > Plugins,
    or wherever your Omarchy version surfaces `~/.config/omarchy/plugins/`),
    then lock your session to test: hyprctl dispatch exec 'omarchy-lock' (or
    however you normally trigger the lock screen).

Forgot your PIN? Your real account password still unlocks the session (the
password field in this plugin falls through to pam_unix -- see
omarchy-lock-password.pam). Delete /etc/omarchy-lock-pin.pwd and re-run this
script to set a new PIN.
EOF
