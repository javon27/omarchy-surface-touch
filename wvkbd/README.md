# Patched wvkbd-deskintl

Fixes an upstream bug in [wvkbd](https://git.sr.ht/~proycon/wvkbd) (tested
against v0.19.4, the `deskintl` layout build) that only shows up on real
touchscreens: the key highlight flickers off almost immediately after you
press a key, and holding a key down never triggers repeat.

## The bug

In `keyboard.c`, `kbd_motion_key()` runs on every touch-motion event. Outside
of swipe mode, its handling of "the finger moved" is:

```c
} else {
    kbd_unpress_key(kb, time);
}
```

Unconditional -- it unpresses the currently-pressed key on *every* motion
event, without checking whether the touch is even still over the same key.
Real touch sensors report sub-pixel jitter constantly, even under a
perfectly steady finger, so this fires within a frame or two of the initial
press. That explains both symptoms: the highlight clears right after it
appears (flicker), and whatever repeat-timer state depends on "key is still
held" gets cancelled immediately (no repeat).

## The fix

[`keyboard.c.patch`](keyboard.c.patch) makes the unpress conditional on the
touch having actually left the key that's currently pressed:

```c
} else {
    struct key *current_key = kbd_get_key(kb, x, y);
    if (current_key != kb->last_press) {
        kbd_unpress_key(kb, time);
    }
}
```

## Building it

```
./build.sh
```

Downloads the v0.19.4 source, applies the patch, builds with
`make LAYOUT=deskintl`, and installs to `~/.local/bin/wvkbd-deskintl` --
ahead of the unpatched AUR package on `PATH` (`/usr/bin/wvkbd-deskintl`),
so make sure `~/.local/bin` comes first in your `PATH`, or always invoke it
by its full path (the autostart snippet in [`../hypr/`](../hypr/) does the
latter).

If you're on a different wvkbd version, the patch may not apply cleanly with
`patch -p1` -- open `keyboard.c`, find `kbd_motion_key`, and apply the same
change by hand; it's a small, self-contained fix.

Set `INSTALL_DIR` to install somewhere other than `~/.local/bin`:

```
INSTALL_DIR=/opt/wvkbd-patched ./build.sh
```
