# omarchy-surface-touch

Touch-input support for [Omarchy](https://omarchy.org/) on a Surface-family
tablet (built and tested on a **Surface Pro 7**, but see
[Hardware compatibility](#hardware-compatibility) below) -- everything
needed to use one with the keyboard detached: an on-screen keyboard that
doesn't flicker, a virtual trackpad for precise cursor control, two-finger
right-click, a touch-friendly lock screen with a PIN pad, auto-rotate, and a
touch-dismissible screensaver.

None of this ships with Omarchy or linux-surface out of the box. It's the
result of a long trial-and-error session getting a Surface Pro 7 fully
usable as a tablet under Omarchy, written up so nobody else has to repeat
that from scratch.

## What's here

| Component | What it does | Root needed? |
|---|---|---|
| [`kernel/`](kernel/) | linux-surface + iptsd pointers, and a restart-forever override for iptsd's occasional crash | yes (override only) |
| [`wvkbd/`](wvkbd/) | Patch + build script for wvkbd-deskintl, fixing an upstream flicker/no-repeat bug | no |
| [`osk/`](osk/) | On-screen keyboard toggle + autostart, built on `wvkbd/` | no |
| [`trackpad/`](trackpad/) | Floating virtual trackpad panel (Quickshell) + root uinput injector | yes (injector service) |
| [`two-finger-right-click/`](two-finger-right-click/) | Two-finger tap on the touchscreen = right click | yes |
| [`auto-rotate/`](auto-rotate/) | Accelerometer-driven display + touch rotation | no |
| [`screensaver/`](screensaver/) | Hides OSK/trackpad and adds touch-dismiss to the screensaver | no |
| [`lock-pin/`](lock-pin/) | Short PIN unlock (separate from your password) + on-screen keypad on the lock screen | yes (PAM/PIN file) |

Each component is independent -- install only what you want. The
`trackpad` injector is a shared dependency of the on-screen trackpad panel
*and* the screensaver's touch-dismiss, so install it even if you don't
plan to use the trackpad panel yourself.

## Hardware compatibility

Written and tested on a **Surface Pro 7** running Omarchy 4.x (Arch +
Hyprland) with the linux-surface kernel. Device-specific values you'll need
to adjust for other hardware are called out in each component's README --
in short:

- `TOUCH_DEVICE_NAME` (two-finger-right-click, screensaver) -- your IPTS
  digitizer's evdev device name
- `MONITOR` / `MODE` / `SCALE` (auto-rotate) -- your panel's output name,
  mode, and scale
- OSK height/layout flags (osk) -- comfortable key size depends on your
  screen's DPI

Everything else (the trackpad panel, the wvkbd patch, the lock screen
plugin, the PAM setup) should work unmodified on any Surface Pro/Go/Book
model, or any other Linux tablet with a working IPTS-style touchscreen and
an accelerometer.

## Quick start

```bash
git clone https://github.com/<you>/omarchy-surface-touch.git
cd omarchy-surface-touch
./install.sh          # interactive menu
./install.sh --all    # everything, no prompts
./install.sh osk trackpad   # just these two
```

Start with [`kernel/README.md`](kernel/README.md) first if you haven't
already got linux-surface + iptsd installed and your touchscreen working --
everything else assumes that's done.

## Why some of this needs root

`two-finger-right-click` and `trackpad-injector` both read a raw touch input
device and/or create a `/dev/uinput` virtual device. The straightforward way
to grant that without root is a udev rule adding the invoking user to the
`input`/`uinput` group -- this repo instead runs them as root system
services, which is simpler to install correctly across different distros
but is a real tradeoff (a bug in either script runs with root privileges).
If you'd rather set up udev rules and run them as your own user, the scripts
themselves need no changes -- only the systemd units would move from system
to user scope.

## Contributing

Found this useful on a different Surface model, or fixed something? PRs
welcome -- especially device-specific values for other hardware (add them to
the relevant README's table rather than changing the defaults, so the
Surface Pro 7 configuration keeps working for people who copy-paste without
reading closely).

## License

MIT -- see [LICENSE](LICENSE).

---

## For AI coding agents

If you're an AI agent helping someone install this, read this section
before touching anything.

**Before you start:**
1. Confirm the target machine is Arch-based with Hyprland (Omarchy or
   compatible) -- `pacman -Q hyprland` and check for `omarchy` in
   `pacman -Q`. This repo assumes Omarchy's Lua Hyprland config
   (`~/.config/hypr/*.lua`, the `hl.*`/`o.*` API) and Omarchy's Quickshell
   plugin system for `lock-pin/`. It will not work as-is on plain Hyprland
   or a non-Arch distro.
2. Confirm linux-surface + iptsd are already installed and the touchscreen
   works (`libinput list-devices` should show an IPTS-named touchscreen; a
   tap should register somewhere). If not, stop and point the user at
   [`kernel/README.md`](kernel/README.md) -- **do not** attempt to install
   or switch kernels yourself; that's explicitly out of scope for
   automation here (see that file for why).
3. Ask the user which components they actually want rather than assuming
   `--all` -- e.g. someone with a keyboard permanently attached may not
   want the on-screen keyboard, and `lock-pin` changes their auth surface,
   which deserves an explicit yes.

**Device-specific values -- do not guess, look them up on the actual
machine:**
- Touchscreen device name: `libinput list-devices | grep -B2 -i touch` or
  `evtest` -- look for something like `IPTSD Virtual Touchscreen XXXX:XXXX`.
  Needed for `TOUCH_DEVICE_NAME` in `two-finger-right-click/` and
  `screensaver/`.
- Monitor name/mode/scale: `hyprctl monitors`. Needed for `MONITOR`/`MODE`/
  `SCALE` in `auto-rotate/auto-rotate.sh`.
- Confirm an accelerometer exists before installing `auto-rotate/`:
  `monitor-sensor --accel` should print orientation events, not silence.

**Order that avoids broken intermediate states:**
1. `kernel/install-iptsd-override.sh` (safe, no dependencies)
2. `osk/install.sh` (builds wvkbd; needs `make`/`cc`/wayland dev headers --
   if the build fails on missing headers, install the AUR package's
   `makedepends` first: `pacman -Si wvkbd-deskintl` or check
   `wvkbd/README.md`)
3. `trackpad/install.sh` (needed before `screensaver/`)
4. `two-finger-right-click/install.sh`, `auto-rotate/install.sh` (either
   order, no cross-dependencies)
5. `screensaver/install.sh` (after `trackpad/`)
6. `lock-pin/install.sh` last, and only with explicit user confirmation --
   it writes to `/etc/pam.d/` and prompts interactively for a PIN. Never
   pipe a PIN into it non-interactively or hardcode one in a script; let
   the human type it at the prompt.

**Idempotency notes:**
- Re-running any `install.sh` overwrites the previously installed copy of
  its own scripts/units -- safe to re-run after editing device-specific
  values.
- `lock-pin/install.sh` refuses to overwrite an existing
  `/etc/omarchy-lock-pin.pwd` -- if the user wants to change their PIN, you
  must `sudo rm /etc/omarchy-lock-pin.pwd` first (confirm with them before
  doing this; it's destructive of their existing PIN).
- systemd unit installs use `daemon-reload` + `enable --now`, so a re-run
  after an edit picks up the change without a manual restart step.

**Verifying each piece actually works** (don't just trust exit code 0):
- OSK: `pgrep -af wvkbd-deskintl` shows the patched binary running from
  `~/.local/bin`, not `/usr/bin`.
- Trackpad: `systemctl status trackpad-injector.service` is active, and
  `omarchy-toggle-trackpad` produces a visible panel.
- Two-finger right-click: `systemctl status two-finger-rightclick.service`
  active; a real two-finger tap on the touchscreen should log a line via
  `journalctl -u two-finger-rightclick.service -f`.
- Auto-rotate: `systemctl --user status auto-rotate.service` active, and
  physically rotating the device (or `monitor-sensor --accel` in another
  terminal to confirm events are flowing) should change `hyprctl monitors`
  output within ~1 second.
- Lock-pin: lock the session and confirm the PIN pad renders and both the
  PIN and the real password unlock it, before considering this step done.

**When something fails**, prefer reading the relevant component's README
over guessing -- several pieces encode non-obvious reasoning (why root
instead of udev, why a separate PIN file, why the trackpad uses absolute
vs. relative positioning in different places) that explains *why* a naive
fix would be wrong.
