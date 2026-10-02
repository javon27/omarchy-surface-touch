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

Confirmed on the `09C0` Type Cover (Surface Pro 7+), after suspend/resume.
That is the case this component exists for and it is measured.

**What is not established is whether any cover loses multitouch on a physical
detach and reattach.** An earlier version of this README claimed a Surface Go's
`09B5` did, and that `09B5` survives suspend while `09C0` does not -- a tidy
mirrored table. The `09B5` half has since been withdrawn by the reporter
([#18](https://github.com/javon27/omarchy-surface-touch/issues/18)) after
checking their own journal: three detach/reattach cycles across two kernels all
rebound to `hid-multitouch` unaided, and the boot in which a manual rebind was
cited as the fix contains no detach at all.

A real and useful finding came out of that, though, because it explains how the
mistake was made. The log looks different at boot than on hotplug:

```
# at boot -- two lines, because hid-multitouch is not loaded yet
hid-generic    0003:045E:09B5.0004: ... Mouse [Microsoft Surface Keyboard]
hid-multitouch 0003:045E:09B5.0004: ... Mouse [Microsoft Surface Keyboard]

# on hotplug -- one line, because hid-multitouch is already resident
hid-multitouch 0003:045E:09B5.000B: ... Mouse [Microsoft Surface Keyboard]
```

At boot `hid-generic` claims the device first and the rebind follows once udev
loads the module. On a reattach the correct driver binds immediately. A single
line therefore means the rebind was never *needed*, not that it never happened
-- which reads exactly backwards.

So: install this if you have a `09C0` and lose two-finger scroll after
suspend. Whether anything needs it for detach is open, and the hook does not
cover that case anyway, since it is a `systemd-sleep` hook.

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
