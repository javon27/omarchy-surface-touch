# Virtual trackpad panel

A floating, draggable, resizable on-screen trackpad -- for when you've
detached the Type Cover (or don't have one) and need precise cursor control
that touch-on-the-screen-directly can't give you (no persistent cursor
position, no hover, awkward for small targets).

## Pieces

- **`trackpad-injector.py`** -- runs as root (needs `/dev/uinput`), listens
  on `/run/trackpad.sock` for plain-text commands (`MOVE dx dy`,
  `SCROLL dx dy`, `CLICK left|right|middle`, `DOWN`/`UP` for
  click-and-drag, `KEY esc`/`KEY space`), and injects them through a real
  virtual mouse+keyboard device. Every app sees identical events to a
  physical trackpad -- click-and-drag text selection included -- because
  this sidesteps Wayland's touch protocol entirely rather than trying to
  synthesize pointer events through it.
- **`shell.qml`** -- a standalone Quickshell panel: two-finger drag to move
  or resize itself, single-finger drag to move the cursor (relative
  motion), two-finger drag inside the pad to scroll, tap to click.
- **`omarchy-toggle-trackpad`** -- launches/kills the Quickshell instance
  and toggles `cursor.hide_on_touch` off while it's up (the panel drives the
  cursor via synthetic relative motion while you're touching it, which
  hide-on-touch would otherwise fight, causing flicker).

## Install

```
./install.sh
```

Needs [Quickshell](https://quickshell.outfoxxed.me/) installed (ships with
Omarchy already; `sudo pacman -S quickshell` / `yay -S quickshell` elsewhere)
and `python-evdev`.
Installs `trackpad-injector.service` as a **system** unit (root, same
reasoning as [`../two-finger-right-click/`](../two-finger-right-click/)) --
it also backs the touch-dismiss in [`../screensaver/`](../screensaver/), so
install this even if you don't plan to use the on-screen panel yourself.

Bind a key to `omarchy-toggle-trackpad` -- see
[`../hypr/bindings.snippet.lua`](../hypr/bindings.snippet.lua)
(`SUPER+SHIFT+T` by default).

## Customizing

`shell.qml` has no hardware-specific values -- it's just Quickshell driving
the injector socket -- so it should work unmodified on any screen size.
Panel size/position on first launch, drag sensitivity, and colors are all
plain QML properties near the top of the file if you want to tweak feel.
