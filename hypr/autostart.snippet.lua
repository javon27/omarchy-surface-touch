-- Add to your own ~/.config/hypr/autostart.lua. Not applied automatically.

-- wvkbd on-screen keyboard (full desktop layout: function row, Super, Ctrl,
-- Alt, Tab, Esc, arrows -- no numpad). Starts hidden; toggle with
-- SUPER+SHIFT+K or omarchy-toggle-osk. Uses the patched build at
-- ~/.local/bin (see ../wvkbd/) rather than any AUR package on PATH.
--
-- Customize the layout/size flags -- see ../osk/README.md. Lua config here
-- doesn't expand $HOME -- replace /home/YOUR_USERNAME with your actual home.
o.launch_on_start("/home/YOUR_USERNAME/.local/bin/wvkbd-deskintl --hidden -l full,special --landscape-layers full,special -H 470 -L 470")
