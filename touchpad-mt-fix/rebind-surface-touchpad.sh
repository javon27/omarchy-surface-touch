#!/bin/sh
# Re-init the Surface Type Cover touchpad by rebinding its hid-multitouch device.
#
# Run by rebind-surface-touchpad.service, which is triggered after resume, at
# boot, and whenever a Type Cover is attached. See README.md for why all three,
# and why after a delay.
#
# What this repairs: the touchpad interface falling silent, or dropping to
# single-touch, while still correctly bound to hid-multitouch -- the keyboard on
# the same cover keeps working, which is what makes it look like a software
# problem. A rebind makes the driver re-run its setup, including the feature
# report that puts the device into multitouch mode, against a device that has
# had time to settle.
#
# The sysfs instance suffix (0003:045E:PPPP.NNNN) changes on every
# re-enumeration, and the product id differs between Surface models (09C0 on
# the Pro 7+, 09B5 on the Go), so match the Microsoft vendor id only. The Type
# Cover is the only 045E device that binds to hid-multitouch.
found=0
for path in /sys/bus/hid/drivers/hid-multitouch/0003:045E:*.*; do
  [ -e "$path" ] || continue
  found=1
  dev=$(basename "$path")
  logger -t rebind-surface-touchpad "rebinding $dev"
  echo "$dev" > /sys/bus/hid/drivers/hid-multitouch/unbind
  sleep 1
  echo "$dev" > /sys/bus/hid/drivers/hid-multitouch/bind
done
# Log the no-op too. The previous version only logged when it acted, so a hook
# that never ran at all was indistinguishable from one that ran and found
# nothing -- which is how it went unnoticed for six weeks.
[ "$found" = 1 ] || logger -t rebind-surface-touchpad "no Type Cover bound to hid-multitouch; nothing to do"
