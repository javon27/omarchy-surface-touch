#!/bin/sh
# systemd-sleep hook: re-init the Surface Type Cover touchpad's multitouch mode
# after resume. Its hid-multitouch device can silently drop to single-touch
# reporting on wake -- cursor/click keep working but two-finger scroll dies,
# because no raw events fire for a second finger. Rebinding the HID driver
# forces it to re-negotiate, same effect as unplugging/replugging the cover.
#
# The device's sysfs instance suffix (0003:045E:09C0.NNNN) increments on every
# bind, so match by vendor:product prefix rather than a fixed id.
case "$1/$2" in
  post/*)
    for path in /sys/bus/hid/drivers/hid-multitouch/0003:045E:09C0.*; do
      [ -e "$path" ] || continue
      dev=$(basename "$path")
      logger -t rebind-surface-touchpad "resume detected, rebinding $dev"
      echo "$dev" > /sys/bus/hid/drivers/hid-multitouch/unbind
      sleep 1
      echo "$dev" > /sys/bus/hid/drivers/hid-multitouch/bind
    done
    ;;
esac
