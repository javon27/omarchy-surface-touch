#!/bin/bash
# Follows the device's accelerometer orientation and rotates the display +
# touchscreen to match. Paused while /tmp/rotation-locked exists (toggled by
# omarchy-toggle-rotation-lock).
LOCK_FILE="/tmp/rotation-locked"
MONITOR="eDP-1"
MODE="2736x1824@59.96"
POS="0x0"
SCALE="1.6"
DELAY="${ROTATE_DELAY:-0.5}"
pending_pid=""

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
