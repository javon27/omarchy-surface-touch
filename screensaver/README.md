# Screensaver touch helper

Two problems with Omarchy's screensaver on a touch-only setup:

1. The on-screen keyboard and virtual trackpad panels sit on Wayland's
   Overlay layer, above the screensaver's own window, so they'd otherwise
   float on top of it looking broken.
2. `omarchy-screensaver` exits on one of two things: a byte arriving at its
   **pty**, or losing window focus. Keyboard input produces the first.
   Touch, trackpad and mouse input produce neither -- nothing writes to the
   terminal without mouse reporting enabled, and clicking a fullscreen window
   that is already focused does not change focus. So none of them dismiss it.

This daemon polls for the screensaver's window (`org.omarchy.screensaver`)
and, while it's active: hides the OSK/trackpad panels, and turns touch,
trackpad and mouse input into an injected `Escape` keypress via
[`../trackpad/`](../trackpad/)'s injector socket (so it needs that service
already running).

### What dismisses it

| Input | How |
|---|---|
| Keyboard | reaches the pty directly; nothing here involved |
| Touchscreen | any contact |
| Trackpad / mouse | ~5mm of movement, or a button press |

Pointer input needs a movement threshold where touch does not: a palm resting
on the trackpad, or a jittery sensor, should not dismiss the screensaver the
moment it appears. Touching the screen is unambiguous, so any contact counts.

The threshold is in millimetres because absolute devices report a resolution
in units/mm (20 on a Surface Type Cover, giving 100 units). Relative devices
report arbitrary counts with no physical scale, so they use a separate
default.

Pointer devices are rescanned every couple of seconds, so a mouse plugged in
after the service started is picked up, and a detached Type Cover stops being
polled.

The touchscreen and stylus are deliberately excluded from the pointer path --
they report `INPUT_PROP_DIRECT`, and touch is already handled. So are the
uinput devices this project creates itself (`virtual-trackpad`,
`two-finger-right-click`), which would otherwise let the on-screen trackpad
dismiss the screensaver it is hidden behind, or loop against the very injector
this helper sends `Escape` through.

> The name is now a misnomer -- it handles more than touch. Renaming the unit
> would break every existing install for no functional gain, so it stays.

## Install

```
./install.sh
```

Needs [`../trackpad/`](../trackpad/) installed first. Installs as a
**user** systemd service.

> **Known issue:** running as a user service is wrong. This helper reads the
> touchscreen directly, but `/dev/input/event*` is `root:input` and logind
> hands the compositor its devices over D-Bus rather than through file
> permissions -- so as your user it sees no input devices at all and the
> touch-dismiss half never works. (The OSK/trackpad-hiding half is fine.) It
> needs converting to a system unit the way `trackpad-injector` and
> `two-finger-rightclick` already are. Until then it logs an explicit error
> saying so; check with
> `journalctl --user -u screensaver-touch-helper -n 20`.

## Customizing

The touchscreen is found by capability -- the input device exposing
`ABS_MT_SLOT`, which is what distinguishes it from the stylus and from the
raw uncalibrated HID nodes -- so there is normally nothing to set. Override it
only if more than one multitouch device is present:

```
systemctl --user edit screensaver-touch-helper.service
# [Service]
# Environment=TOUCH_DEVICE_NAME=Your Device Name Here
# Environment=POINTER_MOVE_MM=5.0      # trackpad/mouse travel before dismissing
# Environment=REL_MOVE_COUNTS=25       # same, for relative devices (a mouse)
```
