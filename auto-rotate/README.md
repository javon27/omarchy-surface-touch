# Auto-rotate

Follows the device's accelerometer and rotates the display + touchscreen
input to match, with debouncing so picking the tablet up and setting it back
down doesn't flash-rotate through every orientation in between.

## Prerequisite: find your values

`auto-rotate.sh` hardcodes three things at the top of the file that are
specific to the exact machine it was written on (a Surface Pro 7+):

```bash
MONITOR="eDP-1"
MODE="2736x1824@59.96"
SCALE="1.6"
```

Before installing, find yours:

```
hyprctl monitors        # monitor name, current mode, current scale
```

Edit those three lines in `auto-rotate.sh` to match (do this before running
`./install.sh`, or after -- it edits `~/.local/bin/auto-rotate.sh` in place
either way).

## How it works

`monitor-sensor --accel` (from `iio-sensor-proxy`) streams orientation
readings. On a change, the script waits `ROTATE_DELAY` seconds (default
0.5s) and applies the *last* reading that arrived in that window --
cancelling and restarting the wait on every new reading. Only an orientation
the device settles on for a full debounce window gets applied.

Rotation is applied via `hl.monitor(...)` and `hl.config(...)` -- Omarchy
4.0's own Lua Hyprland-config API (not a Hyprland core feature) -- so this
piece assumes an Omarchy environment specifically, unlike most of the rest
of this repo.

## Install

```
./install.sh
```

Needs `iio-sensor-proxy` (`sudo pacman -S iio-sensor-proxy`) and a device
with a working accelerometer under it (check with `monitor-sensor --accel`
before installing -- if it prints nothing, the kernel isn't exposing one).

Installs as a **user** systemd service (no root needed -- it only calls
`hyprctl`).

Bind a key to `omarchy-toggle-rotation-lock` to freeze/unfreeze rotation at
the current orientation -- see
[`../hypr/bindings.snippet.lua`](../hypr/bindings.snippet.lua)
(`SUPER+SHIFT+R` by default).

## Customizing

`ROTATE_DELAY` env var overrides the debounce window:

```
systemctl --user edit auto-rotate.service
# [Service]
# Environment=ROTATE_DELAY=1.0
```
