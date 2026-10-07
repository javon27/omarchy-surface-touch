#!/bin/bash
# Installs a oneshot service that rebinds the Type Cover touchpad's
# hid-multitouch device after resume, at boot, and when the cover is attached,
# each after a short settle delay. See README.md for the symptom and why all
# three triggers are needed.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../lib.sh

# Must stay identical to the glob in rebind-surface-touchpad.sh. When the two
# differ this check can pass while the hook never fires -- which is exactly what
# happened on models whose Type Cover reports a product id other than 09C0.
# (Left unquoted on purpose: quoting it would stop the shell expanding it.)
if ! ls /sys/bus/hid/drivers/hid-multitouch/0003:045E:*.* >/dev/null 2>&1; then
  warn "No Microsoft (045E) device is bound to hid-multitouch right now."
  warn "That is normal if the Type Cover is detached, or if the touchpad is"
  warn "working correctly -- the device only appears there while bound."
  bound=$(ls -1 /sys/bus/hid/drivers/hid-multitouch/ 2>/dev/null | grep -E '^[0-9A-Fa-f]{4}:' || true)
  if [ -n "$bound" ]; then
    warn "Currently bound to hid-multitouch:"
    printf '         %s\n' $bound >&2
  else
    warn "Nothing is bound to hid-multitouch at all."
  fi
fi

# Root-owned location on purpose. A root service must not execute anything a
# non-root user can rewrite, or that user can turn it into root code execution.
sudo install -Dm 755 -o root -g root rebind-surface-touchpad.sh /usr/local/bin/rebind-surface-touchpad
info "Installed /usr/local/bin/rebind-surface-touchpad"

install_system_unit rebind-surface-touchpad.service
sudo install -Dm 644 99-surface-touchpad.rules /etc/udev/rules.d/99-surface-touchpad.rules
info "Installed /etc/udev/rules.d/99-surface-touchpad.rules"

# Earlier versions installed a hook here. systemd-sleep only runs executables
# from /usr/lib/systemd/system-sleep/, so it never fired on a real resume --
# and leaving it behind would suggest otherwise to anyone reading the system.
old=/etc/systemd/system-sleep/rebind-surface-touchpad.sh
if [[ -e $old ]]; then
  sudo rm -f "$old"
  info "Removed $old (never ran: systemd-sleep does not read /etc/systemd/system-sleep/)"
fi

sudo systemctl daemon-reload
sudo systemctl enable rebind-surface-touchpad.service
sudo udevadm control --reload

info "Enabled. Fires after resume, at boot, and when the Type Cover is attached."
info "Not run now: a rebind briefly drops the keyboard, so it would interrupt this install."
info "Test it with: sudo systemctl start rebind-surface-touchpad.service   (keyboard blips ~5s later)"
info "Every run is logged, including no-ops: journalctl -t rebind-surface-touchpad"
