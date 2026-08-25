#!/bin/bash
# Installs a systemd-sleep hook that re-inits the Type Cover touchpad's
# multitouch mode on every resume from suspend. See README.md for the
# symptom this fixes and why it happens.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../lib.sh

if ! ls /sys/bus/hid/drivers/hid-multitouch/0003:045E:*.* >/dev/null 2>&1; then
  warn "No 0003:045E:* device found under hid-multitouch right now."
  warn "This is normal if the touchpad is currently working fine -- the device"
  warn "only shows up there while correctly bound. See README.md if your Type"
  warn "Cover's product id differs from 09C0 (other Surface models can differ)."
fi

sudo install -m 755 rebind-surface-touchpad.sh /etc/systemd/system-sleep/rebind-surface-touchpad.sh
info "Installed /etc/systemd/system-sleep/rebind-surface-touchpad.sh"
info "Takes effect on the next suspend/resume -- no service to enable or reload."
info "Test it immediately with: sudo /etc/systemd/system-sleep/rebind-surface-touchpad.sh post suspend"
info "Check it fired after a real resume with: journalctl -t rebind-surface-touchpad"
