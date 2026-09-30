# Tablet mode

Publishes whether the physical keyboard is usable, and runs hooks when that
changes. An on-screen keyboard is shipped as the first hook; it is hardware
state rather than keyboard behaviour, so rotation lock, the lock screen or
anything else can consume the same signal.

Not installed by `--all`: it changes behaviour for anyone who relies on the
keyboard being available to toggle at any time.

```bash
./install.sh tablet-mode
```

## Two conditions, and why presence alone is not enough

The keyboard is unusable when either:

- the Type Cover is **detached**, or
- the Type Cover is **folded back** behind the screen. It is still attached and
  still enumerated, so a presence check misses the most common tablet posture.

Fold-back is reported as `SW_TABLET_MODE` on an `EV_SW` device. The predicate is
therefore *tablet mode **or** no usable keyboard*, not either alone.

## Nothing here matches on a device name

Where the switch lives differs by model, and the name is not a reliable handle:

| | Surface Go | Surface Pro 7+ |
|---|---|---|
| Device name | `Intel HID switches` | `Microsoft Surface Type Cover Tablet Mode Switch` |
| Provided by | the chassis | the Type Cover itself |
| On detach | switch persists | switch disappears with the cover |
| Name is unique? | yes | no: ten devices share it, one exposes `SW_TABLET_MODE` |

So on a Pro 7+ the two conditions collapse into one device's presence, while on
a Go they stay genuinely independent. A missing switch means "no cover", not
"not in tablet mode", which the predicate above already handles.

The switch is found by capability (`EV_SW` containing `SW_TABLET_MODE`), which
is correct on both.

Keyboard presence is also capability-based, with one wrinkle: an x86 machine
enumerates an `AT Translated Set 2 keyboard` on i8042 whether or not anything is
attached to it, so "has alphabetic keys" is always true. Presence therefore
requires alphabetic keys **on a hotpluggable bus** (USB or Bluetooth).

## Why a root system unit

It reads `/dev/input` directly, which is `root:input`, exactly as
`trackpad-injector` and `two-finger-rightclick` do. That avoids adding anyone to
the `input` group, needs no compositor dependency, and keeps per-model device
names out of the Hyprland config.

Attach and detach need no separate udev trigger: the devices appearing and
disappearing under `/dev/input` is the signal, watched with inotify.

The keyboard itself is started **as the session user** with `setpriv`, since it
must be the user's own Wayland client. The unit is deliberately not ordered
against the graphical session so it survives the compositor restarting; it
discovers the Wayland socket when it needs one and does nothing until one
exists.

## What it publishes

`/run/omarchy-tablet-mode`, rewritten atomically on every change:

```
TABLET_MODE=0
KEYBOARD_ATTACHED=1
KEYBOARD_USABLE=1
```

`KEYBOARD_USABLE` is the derived answer most consumers want, computed once so
every hook agrees.

> **Use `KEYBOARD_USABLE`, not `TABLET_MODE`.** The raw switch means different
> things on different hardware, because of where it lives:
>
> - **Surface Go**: the switch is chassis-level, so `TABLET_MODE=1` for as long
>   as the cover is folded back.
> - **Surface Pro 7+**: folding the cover physically USB-disconnects it, taking
>   the switch with it. `TABLET_MODE=1` exists for about a second and then the
>   device disappears, so it reads **0 for almost the whole time the machine is
>   physically folded**, and fold-back is indistinguishable from detach in
>   steady state.
>
> A hook keying off `TABLET_MODE` to mean "is this a tablet right now" is
> correct on a Go and wrong on a Pro 7+. `KEYBOARD_USABLE` answers the question
> both models actually agree on.

## Hooks

Every executable in `/etc/omarchy-tablet-mode.d/` runs on each transition, with
those three values plus `TARGET_UID`, `TARGET_GID` and `USER_XDG_RUNTIME_DIR`
in the environment. A hook that fails is logged and does not stop the others.

```bash
#!/bin/bash
# /etc/omarchy-tablet-mode.d/60-rotation-lock
[[ ${TABLET_MODE:-0} -eq 1 ]] && unlock-rotation || lock-rotation
```

Hooks run as **root**. Anything that has to be the user's own Wayland client
needs `setpriv`; `50-onscreen-keyboard` shows the pattern.

### Deferring

A hook that understands the state but cannot act on it yet should exit **75**
(`EX_TEMPFAIL`). The daemon then re-runs hooks on its next wake even though the
hardware has not changed, and stops once none defer.

That is what makes booting with the cover already folded work. The daemon starts
before any graphical session, the keyboard hook has nowhere to draw, and logging
in changes no hardware state — so waiting for a transition would leave you with
no keyboard and no way to ask for one. logind touches `/dev/input` when a
session starts, which is the wake that gets the retry.

## Choosing the keyboard

```bash
sudo systemctl edit omarchy-tablet-mode.service
```

```ini
[Service]
Environment="OSK_COMMAND=squeekboard"
```

The default is the patched `wvkbd-deskintl` from [`../osk/`](../osk/), started
**without** `--hidden`. That matters: wvkbd implements `virtual-keyboard-v1`
only, so it sends keystrokes and has no way to hear that a text field took
focus. Started hidden it would need `SUPER+SHIFT+K` to reveal, which is a
keypress you cannot make on a machine whose keyboard just became unusable.

`squeekboard` is the opposite: it implements `text-input-v3`, starts hidden by
design and shows itself when a text field takes focus. Folding the cover while
looking at a window with no text field therefore shows nothing until you tap
one. Both behaviours are correct for their keyboard; neither pops up merely
because the cover moved.

> Quote the value. `Environment=` splits on whitespace, so an unquoted command
> with arguments is parsed as several assignments and the arguments are silently
> dropped.

**A note on what "running" means.** With `wvkbd --hidden` the keyboard is
launched but not shown; you still toggle it. With `squeekboard` it appears by
itself when a text field takes focus, so folding the cover while looking at a
window with no text field shows nothing until you tap one. Neither keyboard pops
up merely because the cover moved.

## Verify

```bash
systemctl status omarchy-tablet-mode.service
journalctl -u omarchy-tablet-mode.service -f
```

Then fold the cover, unfold it, and detach it. Expect one line per transition:

```
tablet=1 keyboard_attached=1 keyboard_usable=0     <- folded back
tablet=0 keyboard_attached=1 keyboard_usable=1     <- unfolded
tablet=0 keyboard_attached=0 keyboard_usable=0     <- detached
```

`cat /run/omarchy-tablet-mode` at any point shows the same values.

The third line is a detach on a Surface Go: the chassis switch still reads
`False` while the keyboard is gone, which is why the predicate checks both.

**Fold twice.** A single cycle passing is not enough to prove the process is
being reaped correctly: `pgrep` matches zombies, so a daemon that leaks one
reports the keyboard as permanently running and silently stops starting it.
