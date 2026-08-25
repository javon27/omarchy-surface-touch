#!/bin/bash
# Applies a systemd override that keeps iptsd (the IPTS touch daemon)
# restarting forever. iptsd has a recurring, not-fully-diagnosed
# "Interrupted system call" crash on some Surface machines (tentatively
# linked to the power-saver profile / PCIe ASPM) -- without this, that crash
# just kills touch until you notice and restart it yourself.
#
# Prerequisite (not automated here -- see README.md): the linux-surface
# kernel + iptsd must already be installed and your touchscreen working.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
source ../lib.sh

require_cmd systemctl

sudo mkdir -p /etc/systemd/system/iptsd@.service.d
sudo cp systemd/iptsd-override.conf /etc/systemd/system/iptsd@.service.d/override.conf
sudo systemctl daemon-reload

info "Installed /etc/systemd/system/iptsd@.service.d/override.conf"
info "iptsd@*.service will now restart immediately and indefinitely if it crashes."
