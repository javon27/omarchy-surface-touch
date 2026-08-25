# Two-finger-tap-to-right-click

Touchpads get two-finger-tap-for-right-click for free from libinput. Real
touchscreens don't have an equivalent, and Wayland's touch protocol has no
concept of "right click" at all -- this daemon adds one.

## How it works

Reads the raw touchscreen evdev device **passively** (opens it without
`EVIOCGRAB`, so every event still reaches Hyprland/the compositor normally
-- this never interferes with real touch input). It watches for exactly two
fingers touching down close together in time, staying nearly still, and
lifting quickly (a clean tap, not a drag or pinch). On a match, it moves a
synthetic absolute-positioning virtual pointer to the midpoint of the two
touch points and clicks `BTN_RIGHT` there.

The absolute positioning matters: Hyprland doesn't move a persistent cursor
position in response to real touch delivery, so a plain relative
right-click would land wherever a physical mouse/trackpad last parked the
cursor, not where you tapped.

Apps with their own native two-finger-tap gesture (Chromium, Firefox, and
other browsers use it for a context menu) are skipped by active window
class, so this doesn't race against their own handling.

## Install

```
./install.sh
```

Runs as a **system** service (root), not a user service -- it needs
`/dev/uinput` and raw access to the touchscreen's input device, and this
repo doesn't set up udev rules to grant a normal user that access. If you'd
rather do it via udev + a user service, that works too; you'll need to write
your own `uinput` group rule.

## Customizing

Set these as environment overrides (`sudo systemctl edit
two-finger-rightclick.service`, add under `[Service]`):

| Variable | Default | Meaning |
|---|---|---|
| `TOUCH_DEVICE_NAME` | `IPTSD Virtual Touchscreen 045E:0C1A` | Run `sudo libinput list-devices` or `evtest` to find yours if you're not on a Surface Pro 7+ |
| `TAP_MAX_DURATION_MS` | `350` | Longest a two-finger touch can last and still count as a tap |
| `SECOND_FINGER_WINDOW_MS` | `150` | How close together the two touch-downs must land in time |
| `MOVE_FUZZ_PERCENT` | `3.0` | How much either finger may drift (as % of the axis range) before the gesture aborts as a drag/pinch instead |
