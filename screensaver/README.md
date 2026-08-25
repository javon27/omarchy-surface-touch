# Screensaver touch helper

Two problems with Omarchy's screensaver on a touch-only setup:

1. The on-screen keyboard and virtual trackpad panels sit on Wayland's
   Overlay layer, above the screensaver's own window, so they'd otherwise
   float on top of it looking broken.
2. `omarchy-screensaver` only reads real keyboard/mouse input to know when
   to exit (a `read -n1 -t 1` loop internally) -- a touch on the screen
   can't reach that at all, so touching the screen while it's up would do
   nothing.

This daemon polls for the screensaver's window (`org.omarchy.screensaver`)
and, while it's active: hides the OSK/trackpad panels, and forwards any
touch to an injected `Escape` keypress via
[`../trackpad/`](../trackpad/)'s injector socket (so it needs that service
already running).

## Install

```
./install.sh
```

Needs [`../trackpad/`](../trackpad/) installed first. Installs as a
**user** systemd service.

## Customizing

`TOUCH_DEVICE_NAME` env var overrides the touchscreen device name (same
default and same way to find yours as
[`../two-finger-right-click/README.md`](../two-finger-right-click/README.md)):

```
systemctl --user edit screensaver-touch-helper.service
# [Service]
# Environment=TOUCH_DEVICE_NAME=Your Device Name Here
```
