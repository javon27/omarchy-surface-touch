# Touch-friendly lock screen (PIN + on-screen keyboard)

Your account password is probably too long/complex to comfortably type on
glass with no physical keyboard attached. This adds a short numeric PIN as
an *additional* way to unlock -- your real password still works too -- plus
an on-screen PIN pad / QWERTY keyboard on the lock screen itself, so it's
unlockable with no keyboard present at all.

## Why a separate PIN instead of just a shorter password

`/etc/omarchy-lock-pin.pwd` stores the PIN's hash completely separately from
your account password (`/etc/shadow`), via
[`pam_pwdfile`](https://github.com/tobiadam/pam_pwdfile). If the PIN file
ever leaked, it exposes only the PIN -- not your login password, not your
disk encryption passphrase, nothing else. And the PIN only works against the
*lock screen* PAM stack, not `login`, `sudo`, `su`, or SSH.

## How the PAM stack works

[`omarchy-lock-password.pam`](omarchy-lock-password.pam) tries the PIN
first, and falls through to your real password if the PIN doesn't match:

```
auth  [success=2 default=ignore]  pam_pwdfile.so pwdfile=/etc/omarchy-lock-pin.pwd
auth  [success=1 default=bad]     pam_unix.so try_first_pass nullok
```

So either your PIN or your real account password unlocks the screen --
whichever you type into the same field.

## The plugin

Omarchy's lock screen is a Quickshell plugin. This clones the default one
(`omarchy.lock`) and swaps in a `VirtualKeyboard.qml` + `Key.qml`
touch-typable keypad under the password field (see
[`plugin/VirtualKeyboard.qml`](plugin/VirtualKeyboard.qml)): numeric by
default, with an "ABC" key to switch to a full QWERTY layout for typing your
real password instead of a PIN. Typed characters go straight into the
password field via `insert()`/`remove()` -- nothing here is logged, stored,
or transmitted anywhere.

`Service.qml` is otherwise Omarchy's own stock lock-service boilerplate
(session lock lifecycle, fingerprint PAM, idle-blank timing, stranded-lock
recovery) -- included as-is because the plugin needs the whole thing to
load, but the touch-specific work is entirely in `VirtualKeyboard.qml` /
`Key.qml` / `LockView.qml`.

## Install

```
./install.sh
```

Needs `libpam_pwdfile` (`yay -S libpam_pwdfile`) and `openssl`. Prompts for
a PIN (4+ digits), hashes it (`openssl passwd -6`, SHA-512 crypt), and
writes `/etc/omarchy-lock-pin.pwd` as `username:hash`, mode 600. Then
installs the PAM config and copies the plugin to
`~/.config/omarchy/plugins/touchlock/`.

You still need to **enable the plugin** through however your Omarchy version
surfaces plugin management (Setup > Plugins, or directly editing
`~/.config/omarchy/shell.json` if you know that format) -- this repo installs
the plugin's files but doesn't assume how your Omarchy version wires plugin
enablement.

## Changing or removing your PIN

Delete `/etc/omarchy-lock-pin.pwd` and re-run `./install.sh` to set a new
one. Delete it and don't re-run anything to remove the PIN entirely (the
PAM stack falls through to your real password when the file is absent
-- `pam_pwdfile` fails open to `default=ignore`, not a hard error).
