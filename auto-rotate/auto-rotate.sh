#!/bin/bash
# Follows the device's accelerometer orientation and rotates the display +
# touchscreen to match. Paused while /tmp/rotation-locked exists (toggled by
# omarchy-toggle-rotation-lock).
LOCK_FILE="/tmp/rotation-locked"
DELAY="${ROTATE_DELAY:-0.5}"

# Panel geometry. These used to be hardcoded to one machine's values, which
# failed silently on every other model -- rotation would apply a mode the panel
# does not have. Read them from Hyprland instead, and let any of the four be
# overridden if the detection picks the wrong output.
MONITOR="${ROTATE_MONITOR:-}"
MODE="${ROTATE_MODE:-}"
POS="${ROTATE_POS:-}"
SCALE="${ROTATE_SCALE:-}"
pending_pid=""

detect_panel() {
    local json sel
    json=$(hyprctl monitors -j 2>/dev/null) || return 1
    [ -n "$json" ] || return 1
    # Prefer the internal panel; fall back to whatever is listed first. The
    # refresh rate is rounded to 2dp to match the form Hyprland accepts in a
    # mode string (it reports e.g. 59.959 but wants 59.96).
    sel=$(printf '%s' "$json" | jq -r '
        ((map(select(.name | startswith("eDP"))) | first) // .[0])
        | select(. != null)
        | "\(.name)\t\(.width)x\(.height)@\((.refreshRate*100|round)/100)\t\(.x)x\(.y)\t\(.scale)"
    ' 2>/dev/null) || return 1
    [ -n "$sel" ] || return 1
    local d_monitor d_mode d_pos d_scale
    IFS=$'\t' read -r d_monitor d_mode d_pos d_scale <<<"$sel"
    [ -n "$d_monitor" ] || return 1
    MONITOR="${MONITOR:-$d_monitor}"
    MODE="${MODE:-$d_mode}"
    POS="${POS:-$d_pos}"
    SCALE="${SCALE:-$d_scale}"
}

if ! detect_panel; then
    echo "ERROR: could not read panel geometry from 'hyprctl monitors -j'." >&2
    echo "  Is Hyprland running, and is jq installed?" >&2
    echo "  Set ROTATE_MONITOR / ROTATE_MODE / ROTATE_POS / ROTATE_SCALE to skip detection." >&2
    exit 1
fi
echo "panel: monitor=$MONITOR mode=$MODE pos=$POS scale=$SCALE"

apply_orientation() {
    local orientation="$1"
    local transform
    case "$orientation" in
        normal)    transform=0 ;;
        left-up)   transform=1 ;;
        bottom-up) transform=2 ;;
        right-up)  transform=3 ;;
        *) return ;;
    esac
    echo "orientation=$orientation -> transform=$transform"
    hyprctl eval "hl.monitor({ output = \"$MONITOR\", mode = \"$MODE\", position = \"$POS\", scale = $SCALE, transform = $transform })"
    hyprctl eval "hl.config({ input = { touchdevice = { transform = $transform } } })"
    # The stylus is a separate device class: Hyprland lists the digitizer under
    # `touch` and the pen under `tablets`, and they take separate transforms.
    # Without this the display and finger input rotate while pen input keeps the
    # panel's original orientation, so the pointer lands in the pre-rotation
    # position.
    hyprctl eval "hl.config({ input = { tablet = { transform = $transform } } })"
}

stdbuf -oL monitor-sensor --accel | while IFS= read -r line; do
    if [ -f "$LOCK_FILE" ]; then
        continue
    fi
    orientation=$(echo "$line" | grep -oP '[Oo]rientation.*?:\s*\K[a-z-]+')
    if [ -n "$orientation" ]; then
        # Debounce: cancel any still-pending apply from a previous reading,
        # then wait DELAY seconds before applying this one. If another
        # orientation event arrives in the meantime, it cancels this one too
        # -- only the reading the device settles on for a full DELAY gets
        # applied, so a quick pass-through orientation while picking the
        # tablet up doesn't cause a flash-rotate.
        if [ -n "$pending_pid" ] && kill -0 "$pending_pid" 2>/dev/null; then
            kill "$pending_pid" 2>/dev/null
        fi
        ( sleep "$DELAY"; apply_orientation "$orientation" ) &
        pending_pid=$!
    fi
done
