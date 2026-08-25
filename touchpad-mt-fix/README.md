# Type Cover touchpad multitouch fix

## Symptom

After a suspend/resume cycle, the Type Cover's hardware trackpad
occasionally drops out of multitouch reporting mode: the cursor still moves
and single-finger tap/click still works, but two-finger scroll silently
stops doing anything. This isn't a libinput or Hyprland config issue --
confirmed via raw `evdev` capture, zero kernel events fire for a second
finger at all. The touchpad's `hid-multitouch` driver has (for reasons not
fully understood) come back up in a degraded single-touch mode after
resume.

## Fix

Force the driver to re-negotiate by unbinding and rebinding the Type
Cover's composite HID device (keyboard + touchpad share one HID interface)
-- the same effect as physically unplugging and replugging the cover:

```sh
echo "$DEV" > /sys/bus/hid/drivers/hid-multitouch/unbind
sleep 1
echo "$DEV" > /sys/bus/hid/drivers/hid-multitouch/bind
```

The keyboard briefly drops during the rebind (under a second), then both
keyboard and touchpad come back correctly.

## Install

```
./install.sh
```

Installs [`rebind-surface-touchpad.sh`](rebind-surface-touchpad.sh) to
`/etc/systemd/system-sleep/` -- systemd calls every script there
automatically on every suspend and resume (`pre`/`post`), no service to
enable. It rebinds on every `post` (resume) event, unconditionally, rather
than trying to detect whether multitouch actually degraded this time --
the rebind is cheap and the detection would be more failure-prone than just
always doing it.

## Finding your device id if you're not on a Surface Pro 7/7+

The script matches `0003:045E:09C0.*` under
`/sys/bus/hid/drivers/hid-multitouch/` -- `045E` is Microsoft's USB vendor
ID, `09C0` is this Type Cover's product id. Other Surface models' covers
may report a different product id. Find yours:

```sh
ls /sys/bus/hid/drivers/hid-multitouch/
```

Look for a `0003:045E:XXXX.NNNN` entry while the touchpad is working
normally, and swap `09C0` for your `XXXX` in
`rebind-surface-touchpad.sh`'s glob pattern.

## Testing without waiting for a real suspend cycle

systemd-sleep hooks take `$1` (`pre`/`post`) and `$2` (`suspend`/
`hibernate`/etc) as arguments -- you can invoke it exactly as systemd would:

```sh
sudo /etc/systemd/system-sleep/rebind-surface-touchpad.sh post suspend
```

Confirm it actually ran (and what it rebound) with:

```sh
journalctl -t rebind-surface-touchpad
```
