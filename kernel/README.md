# Kernel + touch digitizer (linux-surface / iptsd)

This part is **not automated** beyond the iptsd restart override below --
switching kernels is too consequential to script blindly, and the exact
steps depend on your Arch-based distro's setup.

## Prerequisite: linux-surface kernel + iptsd

Surface devices' touchscreen, pen, and (on some models) keyboard/trackpad
need the [linux-surface](https://github.com/linux-surface/linux-surface)
kernel and the [iptsd](https://github.com/linux-surface/iptsd) daemon
(Intel Precise Touch & Stylus userspace driver). Follow the linux-surface
project's own setup guide for adding their repo and installing the
`linux-surface`/`linux-surface-headers` and `iptsd` packages for your
device. Confirm touch works (`sudo libinput debug-events` or just tapping
the screen) before moving on to the rest of this repo -- everything else
here assumes a working touchscreen.

## iptsd restart override

On at least some Surface Pro hardware, `iptsd` occasionally dies with an
"Interrupted system call" on the hidraw read -- not fully root-caused yet,
but it correlates loosely with the `power-saver` power profile and PCIe
ASPM (Active State Power Management). Whatever the cause, the practical fix
is: restart it immediately, unconditionally, forever.

```
./install-iptsd-override.sh
```

Installs [`systemd/iptsd-override.conf`](systemd/iptsd-override.conf) to
`/etc/systemd/system/iptsd@.service.d/override.conf`:

```ini
[Unit]
StopWhenUnneeded=no
StartLimitIntervalSec=0

[Service]
Restart=always
RestartSec=1
```

`StartLimitIntervalSec=0` disables systemd's restart-storm circuit breaker
for this unit -- however often it dies, it keeps coming back within a
second, rather than giving up after N restarts and leaving touch dead until
you notice.

If you find the actual root cause of the crash, please open an issue/PR --
this is a workaround, not a fix.
