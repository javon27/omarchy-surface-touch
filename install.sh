#!/bin/bash
# Interactive installer for omarchy-surface-touch. Each component is also a
# standalone script (e.g. ./trackpad/install.sh) if you'd rather cherry-pick.
#
# Usage:
#   ./install.sh                 interactive menu
#   ./install.sh --all           install everything, no prompts
#   ./install.sh osk trackpad    install only the named components
#   ./install.sh --list          list component names and exit
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"

COMPONENTS=(kernel osk trackpad two-finger-right-click auto-rotate screensaver lock-pin touchpad-mt-fix)

run_component() {
  case "$1" in
    kernel) bash kernel/install-iptsd-override.sh ;;
    osk) bash osk/install.sh ;;
    trackpad) bash trackpad/install.sh ;;
    two-finger-right-click) bash two-finger-right-click/install.sh ;;
    auto-rotate) bash auto-rotate/install.sh ;;
    screensaver) bash screensaver/install.sh ;;
    lock-pin) bash lock-pin/install.sh ;;
    touchpad-mt-fix) bash touchpad-mt-fix/install.sh ;;
    *) echo "Unknown component: $1" >&2; exit 1 ;;
  esac
}

if [[ "${1:-}" == "--list" ]]; then
  printf '%s\n' "${COMPONENTS[@]}"
  exit 0
fi

if [[ "${1:-}" == "--all" ]]; then
  for c in "${COMPONENTS[@]}"; do run_component "$c"; done
  exit 0
fi

if [[ $# -gt 0 ]]; then
  for c in "$@"; do run_component "$c"; done
  exit 0
fi

echo "omarchy-surface-touch -- pick components to install (space-separated numbers, or 'a' for all):"
select_list=()
for i in "${!COMPONENTS[@]}"; do
  echo "  $((i+1))) ${COMPONENTS[$i]}"
done
read -rp "> " choice
if [[ $choice == "a" ]]; then
  for c in "${COMPONENTS[@]}"; do run_component "$c"; done
else
  for n in $choice; do
    idx=$((n-1))
    [[ -n "${COMPONENTS[$idx]:-}" ]] && run_component "${COMPONENTS[$idx]}"
  done
fi
