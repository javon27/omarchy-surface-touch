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
