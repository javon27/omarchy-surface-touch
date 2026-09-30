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

## Which Type Covers this affects

Both, but on opposite events -- which is why each model looks like it does not
need this component when tested only the way the other one fails.

| Type Cover | suspend / resume | detach / reattach |
|---|---|---|
| `09C0` (Surface Pro 7+) | **loses multitouch** | survives |
| `09B5` (Surface Go) | survives | **loses multitouch** |

Measured both ways. On a Pro 7+, a detach and reattach left the touchpad
reporting `ABS_MT_SLOT` with slots 0-4, and a live capture during two-finger
scrolling saw 17 contacts with 2 simultaneous -- multitouch intact, no rebind
run. On a Go, removing this hook entirely and suspending left two-finger
scroll working, while a physical detach and reattach killed it outright (zero
events at evdev level) until the hook was run by hand. Both reported in
[#5](https://github.com/javon27/omarchy-surface-touch/issues/5).

**The hook only covers the resume half.** It lives in
`/etc/systemd/system-sleep/`, so nothing rebinds on a detach and reattach --
which is precisely the case a `09B5` needs. A udev rule on `add` for `045E`
would close that; see
[#18](https://github.com/javon27/omarchy-surface-touch/issues/18).

The hook matches the Microsoft vendor id, so it installs and matches on both.
Installing it where its half is not needed costs nothing -- rebinding a
healthy device is harmless.

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
