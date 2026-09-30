# omarchy-surface-touch

Touch-input support for [Omarchy](https://omarchy.org/) on a Surface-family
tablet (built and tested on a **Surface Pro 7+**, but see
[Hardware compatibility](#hardware-compatibility) below) -- everything
needed to use one with the keyboard detached: an on-screen keyboard that
doesn't flicker, a virtual trackpad for precise cursor control, two-finger
right-click, a touch-friendly lock screen with a PIN pad, auto-rotate, and a
touch-dismissible screensaver.

None of this ships with Omarchy or linux-surface out of the box. It's the
result of a long trial-and-error session getting a Surface Pro 7+ fully
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
| [`screensaver/`](screensaver/) | Hides OSK/trackpad and adds touch-dismiss to the screensaver | yes (see note) |
| [`lock-pin/`](lock-pin/) | Short PIN unlock (separate from your password) + on-screen keypad on the lock screen | yes (PAM/PIN file) |
| [`touchpad-mt-fix/`](touchpad-mt-fix/) | Fixes the Type Cover trackpad silently losing two-finger scroll after suspend/resume | yes (systemd-sleep hook) |
| [`tablet-mode/`](tablet-mode/) | Runs an on-screen keyboard only while the Type Cover is detached or folded back | yes (reads /dev/input) |

Each component is independent -- install only what you want. `tablet-mode/` is
the one component not installed by `--all`, since it changes existing
behaviour rather than adding to it. The
`trackpad` injector is a shared dependency of the on-screen trackpad panel
*and* the screensaver's touch-dismiss, so install it even if you don't
plan to use the trackpad panel yourself.

## Hardware compatibility

Written and tested on a **Surface Pro 7+** (the commercial/LTE SKU sold
through channels like Costco -- same chassis and panel as the regular
Surface Pro 7, different internals) running Omarchy 4.x (Arch + Hyprland)
with the linux-surface kernel. Nothing here is 7+-specific; a plain Surface
Pro 7 should need the exact same setup.

Most device-specific values are now detected at runtime rather than
hardcoded: `auto-rotate` reads the panel's output/mode/position/scale from
`hyprctl monitors -j`, the touchscreen is located by capability
(`INPUT_PROP_DIRECT`) rather than by device name, and the Type Cover sleep hook
matches the Microsoft vendor id rather than one model's product id. Each is
still overridable -- see the component READMEs. What remains genuinely
model-dependent:

- OSK height/layout flags (osk) -- comfortable key size depends on your
  screen's DPI

Everything else (the trackpad panel, the wvkbd patch, the lock screen
plugin, the PAM setup) should work unmodified on any Surface Pro/Go/Book
model, or any other Linux tablet with a working IPTS-style touchscreen and
an accelerometer.

### Models with an ELAN digitizer (e.g. Surface Go)

[`kernel/`](kernel/) is IPTS-specific. Surface models with an ELAN I2C
digitizer instead do not need it: the touchscreen works on a stock kernel
through mainline `hid-multitouch`, with no linux-surface and no iptsd, and
`iptsd@.service` does not exist for the restart override to attach to. Worth
knowing before committing to a linux-surface install, which is a much bigger
change than the rest of this repo. Skip `kernel/` on those models and start
at [Quick start](#quick-start).

Touch, panel geometry and Type Cover detection are all confirmed working on
a Surface Go (ELAN9038 digitizer, `09B5` Type Cover) -- see
[#5](https://github.com/javon27/omarchy-surface-touch/issues/5), verified by
@kermes on that hardware. The one part still unconfirmed there is whether
[`touchpad-mt-fix/`](touchpad-mt-fix/) is needed at all on ELAN models; see
its README.

## Surface Pen

The pen needs nothing from this repo. iptsd exposes it as a normal tablet
tool and Hyprland picks it up -- pressure and tilt included -- once
[`kernel/`](kernel/) is done.

Two things are worth setting anyway:

**Palm rejection.** iptsd can ignore touch while the pen is in range, which
is what you want when resting a hand on the glass to write. In
`/etc/iptsd.conf`:

```ini
[Touchscreen]
DisableOnStylus = true
```

Then `sudo systemctl restart 'iptsd@*'`. (`DisableOnPalm = true` is a
separate, blunter option that keys off contact shape instead.) Do not build
this in userspace by watching `libinput debug-events` for proximity: that
needs a passwordless sudo rule for `libinput`, which would let anything
running as you read every input device on the machine, keyboard included.

**Duplicate devices.** The raw uncalibrated HID nodes show up alongside the
iptsd-processed ones. Disable the raw pair so only the processed devices
reach Hyprland, in `~/.config/hypr/input.lua`:

```lua
hl.device({ name = "intel-touch-host-controller", enabled = false })
hl.device({ name = "intel-touch-host-controller-stylus", enabled = false })
```

Names differ by model -- check `hyprctl devices`.

## Quick start

```bash
git clone https://github.com/javon27/omarchy-surface-touch.git
cd omarchy-surface-touch
./install.sh          # interactive menu
./install.sh --all    # everything, no prompts
./install.sh osk trackpad   # just these two
```

Start with [`kernel/README.md`](kernel/README.md) first if you haven't
already got linux-surface + iptsd installed and your touchscreen working --
everything else assumes that's done.

### Dependencies

Each component's `install.sh` checks its own and tells you what's missing, so
you can also just run it and see. Installing everything up front:

```bash
sudo pacman -S python python-evdev iio-sensor-proxy jq openssl acl make gcc
yay -S libpam_pwdfile          # lock-pin only, AUR
```

| Component | Needs |
|---|---|
| [`wvkbd/`](wvkbd/), [`osk/`](osk/) | `make`, `gcc` (plus wvkbd-deskintl's own makedepends) |
| [`trackpad/`](trackpad/) | `python`, `python-evdev`, `quickshell` (Omarchy ships this) |
| [`two-finger-right-click/`](two-finger-right-click/) | `python`, `python-evdev` |
| [`screensaver/`](screensaver/) | `python`, `python-evdev`, plus `trackpad/` installed |
| [`auto-rotate/`](auto-rotate/) | `iio-sensor-proxy`, `jq`, `hyprland` |
| [`lock-pin/`](lock-pin/) | `openssl`, `acl`, `libpam_pwdfile` (AUR) |
| [`touchpad-mt-fix/`](touchpad-mt-fix/) | none |

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

`screensaver` gets this backwards today: it reads the touchscreen the same
way those two do, but installs as a *user* unit, so it cannot open
`/dev/input/event*` and its touch-dismiss half has never worked. It needs
moving to a system unit -- see
[`screensaver/README.md`](screensaver/README.md).

## Contributing

Found this useful on a different Surface model, or fixed something? PRs
welcome -- especially device-specific values for other hardware (add them to
the relevant README's table rather than changing the defaults, so the
Surface Pro 7+ configuration keeps working for people who copy-paste without
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
- Type Cover HID product id (only if `touchpad-mt-fix/` needs adjusting):
  `ls /sys/bus/hid/drivers/hid-multitouch/` while the touchpad works
  normally -- default assumes `045E:09C0`.

**Order that avoids broken intermediate states:**
1. `kernel/install-iptsd-override.sh` (safe, no dependencies)
2. `osk/install.sh` (builds wvkbd; needs `make`/`cc`/wayland dev headers --
   if the build fails on missing headers, install the AUR package's
   `makedepends` first: `pacman -Si wvkbd-deskintl` or check
   `wvkbd/README.md`)
3. `trackpad/install.sh` (needed before `screensaver/`)
4. `two-finger-right-click/install.sh`, `auto-rotate/install.sh`,
   `touchpad-mt-fix/install.sh` (any order, no cross-dependencies --
   `touchpad-mt-fix/` only makes sense on a device with a physical Type
   Cover trackpad; skip it on a keyboard-less setup)
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
- Touchpad MT fix: `sudo /etc/systemd/system-sleep/rebind-surface-touchpad.sh
  post suspend` then `journalctl -t rebind-surface-touchpad` should show it
  fired and found a device to rebind -- if it finds nothing, the product id
  doesn't match this hardware (see the device-id note above).

**When something fails**, prefer reading the relevant component's README
over guessing -- several pieces encode non-obvious reasoning (why root
instead of udev, why a separate PIN file, why the trackpad uses absolute
vs. relative positioning in different places) that explains *why* a naive
fix would be wrong.
