# On-screen keyboard (wvkbd)

`wvkbd-deskintl` from the AUR has a real upstream bug on touchscreens: the key
highlight flickers off almost instantly and key-repeat (holding a key to
repeat it) never engages. See [`../wvkbd/README.md`](../wvkbd/README.md) for
the root cause and the fix. `./install.sh` builds the patched binary and
installs the toggle script; you add the autostart/keybind lines yourself
(see the printed instructions, or [`../hypr/`](../hypr/)).

## Customizing the keyboard

Everything below is a `wvkbd-deskintl` command-line flag, set where you
autostart it (`~/.config/hypr/autostart.lua`). Run `wvkbd-deskintl --help`
for the full list; the ones worth knowing about first:

| Flag | What it does | Example |
|---|---|---|
| `-H <px>` | Keyboard height in **portrait** orientation | `-H 470` |
| `-L <px>` | Keyboard height in **landscape** orientation | `-L 470` |
| `-l <layers>` | Comma-separated layers to load, portrait | `-l full,special` |
| `--landscape-layers <layers>` | Layers to load, landscape | `--landscape-layers full,special` |
| `--hidden` | Start hidden (toggle it on with `omarchy-toggle-osk`) | |
| `--fn <name>` | Font family | `--fn "JetBrains Mono"` |
| `-D <name>` | Output/display to appear on | `-D eDP-1` |

Available layers ship in the `deskintl` build under
`layout.deskintl.h`/`keymap.deskintl.h` in the source (see
[`../wvkbd/README.md`](../wvkbd/README.md) for where that lives) --
`full` is a complete desktop layout (function row, Super, Ctrl, Alt, Tab,
Esc, arrows, no numpad), `special` adds a symbols/numpad layer accessible
via the keyboard's own layer-switch key.

The height that looks right depends on your screen's DPI and how big your
fingers need the keys to be -- 470px is what worked well on a Surface Pro 7+'s
2736x1824 panel at 1.6x scale. Start there and adjust up/down in ~30px steps.

To change flags after install, edit the `o.launch_on_start(...)` line in
your `autostart.lua` and restart Hyprland (or kill and relaunch
`wvkbd-deskintl` by hand to preview a change without a full restart).

## Toggling visibility

`omarchy-toggle-osk` sends `wvkbd-deskintl` a `SIGRTMIN` signal (its
show/hide toggle) and also disables cursor-hide-on-touch while the keyboard
is visible (typing on it is itself a stream of touches, and hide-on-touch
would otherwise flicker the cursor on every keystroke).

## Alternative: squeekboard, for focus-triggered showing

wvkbd is the default here and the patched build fixes a real flicker/no-repeat
bug, so there is no reason to switch unless you specifically want the keyboard
to appear **by itself** when a text field takes focus. wvkbd cannot do that:
it implements `zwp_virtual_keyboard_v1` only, which sends keystrokes but has
no way to hear that a field was focused. It has to be toggled.

squeekboard implements `text-input-v3` / `input-method-v2`, so it shows on
focus and hides on blur. It is in Arch `extra`, so no AUR build and no patch.

### The setting that makes or breaks it

```sh
gsettings set org.gnome.desktop.a11y.applications screen-keyboard-enabled true
gsettings set org.gnome.desktop.input-sources sources "[('xkb','us')]"
```

**Without the first key squeekboard does not auto-show and gives no indication
why.** It starts, binds `sm.puri.OSK0`, renders correctly when forced visible,
and simply never appears on focus. Every symptom points at the compositor, so
the natural conclusion is "squeekboard does not work on Hyprland", which is
wrong. The second key gives it a layout to draw; without it you get
`No system layout present`.

### Diagnosing it

Test with a **GTK** client. Chromium's Wayland text-input support is
incomplete and will not trigger the keyboard, which is misleading if it is the
first thing you reach for.

```sh
zenity --entry --text="Type:" &
sleep 5
hyprctl layers | grep 'namespace: osk'                                   # present == auto-show works
busctl --user call sm.puri.OSK0 /sm/puri/OSK0 sm.puri.OSK0 SetVisible b true
```

If `SetVisible` draws a keyboard, rendering is fine and the problem is the
focus signal, i.e. the a11y key above. That is the fork that isolates the
fault. (`Visible` is a read-only property; `SetVisible` is the method.)

### It does not conflict with fcitx5

Worth stating because the assumption cuts the other way: only one client can
bind `input-method-v2`, so displacing fcitx5 looks unavoidable. In practice
fcitx5 keeps serving `~/.XCompose` while squeekboard auto-shows, with both
running and no contention.

### Trade-offs against wvkbd

- In `extra`; no patched build, no AUR
- Sizes itself, nothing to tune -- where wvkbd needs `-H`/`-L` picked by hand
- Carries `gnome-desktop`, `gtk3` and `feedbackd`, being a Phosh project
- Layout customisation is far less direct than wvkbd's layers
- Configured through `gsettings` rather than flags, which is why the missing
  key is so easy to miss

### With `tablet-mode/`

[`tablet-mode/`](../tablet-mode/) sets `OSK_COMMAND`, so
`Environment="OSK_COMMAND=squeekboard"` gets you a keyboard that appears on
*focus* rather than on *fold*. That is arguably the better behaviour, but it
is not what you expect after folding the cover and seeing nothing: squeekboard
starting hidden is correct there and a trap here. wvkbd is started visible by
that hook for exactly this reason.

Verified on a Surface Go under Omarchy 4.x with Hyprland 0.56.2 by @kermes --
see [#15](https://github.com/javon27/omarchy-surface-touch/issues/15).
