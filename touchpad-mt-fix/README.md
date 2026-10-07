# Type Cover touchpad multitouch fix

## Symptom

The Type Cover's touchpad stops working properly while its keyboard keeps
working. Two forms have been seen, both below libinput and Hyprland -- raw
`evdev`, and in the second case raw `hidraw`, show the device itself is not
sending the events:

- **Multitouch degraded** (`09C0`, Surface Pro 7+, after suspend/resume): the
  cursor moves and single-finger tap/click work, but two-finger scroll does
  nothing, because no events fire for a second finger at all.
- **Pointer interface silent** (`09B5`, Surface Go, with no suspend or detach
  involved): touchpad and mouse event nodes produce nothing, down to
  `/dev/hidrawN`, while the keyboard on the same cover produces events
  normally. Reported and measured by @kermes in
  [#18](https://github.com/javon27/omarchy-surface-touch/issues/18).

In both, the device is correctly bound to `hid-multitouch` the whole time, so
nothing about the binding looks wrong.

## Fix

Rebind the cover's HID device to the driver it is already bound to:

```sh
echo "$DEV" > /sys/bus/hid/drivers/hid-multitouch/unbind
sleep 1
echo "$DEV" > /sys/bus/hid/drivers/hid-multitouch/bind
```

That makes `hid-multitouch` re-run its setup, including the feature report that
switches the device into multitouch mode. It has cleared both forms above. The
keyboard drops for about a second during it.

Why the device ends up in this state is not established. One hypothesis, from
#18, is that the driver configures the device too soon after it enumerates and
the setup is silently ignored, which a later rebind against a settled device
does not hit. It fits what has been seen but has not been demonstrated.

## When it runs

A oneshot `rebind-surface-touchpad.service`, requested by three triggers:

| Trigger | How |
|---|---|
| after resume | `WantedBy=` the suspend/hibernate targets |
| at boot | udev rule on the cover's USB `add` (coldplug replays existing devices as `add`) |
| cover attached | the same udev rule |

Every trigger is a re-enumeration of the cover or follows one, so the service
waits **5 seconds** before rebinding, to let the device settle rather than race
it again. Triggers that land together -- a resume that also re-enumerates the
cover, say -- request the same unit while it is still waiting, and collapse
into a single rebind. Not every resume re-enumerates the cover (on a Pro 7+,
about half do), which is why the resume trigger exists separately from udev.

It rebinds unconditionally rather than trying to detect whether the touchpad
actually broke. A rebind of a healthy device is harmless apart from the
keyboard blip, and detection would be more fragile than the fix.

**The cost:** the keyboard drops for about a second, five seconds after you
attach the cover or wake the machine. If you start typing immediately, a
keystroke can land in that window.

## Why this used to never run

Earlier versions installed a hook in `/etc/systemd/system-sleep/`. `systemd-sleep`
only runs executables from `/usr/lib/systemd/system-sleep/` -- see
`man systemd-sleep` -- so that hook never fired on a real resume. On the machine
this component was written on, its log showed exactly one run in six weeks: the
manual test from install time.

It was also silent when it found nothing to do, so a hook that never ran looked
the same as one that ran and found nothing. Every run is now logged, including
no-ops.

`install.sh` removes the old hook if it finds it.

## Which Type Covers this affects

The `09C0` suspend/resume case is the one this component was built for and
was measured directly. The `09B5` silent-interface case is measured by its
reporter. Whether either cover loses the touchpad on a physical detach is not
established: an earlier claim that a `09B5` did was withdrawn in #18 after
three detach/reattach cycles across two kernels all came back healthy, and ten
more deliberate cycles later reproduced nothing.

A finding from that investigation is worth knowing if you are reading these
logs yourself. They look different at boot than on hotplug:

```
# at boot -- two lines, because hid-multitouch is not loaded yet
hid-generic    0003:045E:09B5.0004: ... Mouse [Microsoft Surface Keyboard]
hid-multitouch 0003:045E:09B5.0004: ... Mouse [Microsoft Surface Keyboard]

# on hotplug -- one line, because hid-multitouch is already resident
hid-multitouch 0003:045E:09B5.000B: ... Mouse [Microsoft Surface Keyboard]
```

A single line means the rebind was never *needed*, not that it never happened.
It reads exactly backwards, and it is how the withdrawn claim was made.

The script matches every Microsoft (`045E`) device bound to `hid-multitouch`,
so it covers any Type Cover model without editing. The Type Cover is the only
`045E` device that binds to that driver.

## Install

```
./install.sh
```

Installs the script root-owned to `/usr/local/bin/rebind-surface-touchpad` --
a root service must not run anything a regular user can rewrite -- plus the
unit and `/etc/udev/rules.d/99-surface-touchpad.rules`, and enables it. It
does not run the rebind during install, since that would interrupt you.

## Testing and checking it ran

```sh
sudo systemctl start rebind-surface-touchpad.service   # keyboard blips ~5s later
journalctl -t rebind-surface-touchpad                   # every run, including no-ops
journalctl -u rebind-surface-touchpad.service           # when it was triggered
```

To confirm multitouch is genuinely working rather than just bound, capture from
the touchpad's event node and check for two simultaneous contacts during a
two-finger scroll. "The touchpad responds" is not enough, since the
`09C0` failure leaves single-finger input working.
