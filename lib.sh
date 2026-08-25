# Shared helpers, sourced by every component install.sh. Not meant to be run directly.

info()  { echo "==> $*"; }
warn()  { echo "WARNING: $*" >&2; }
die()   { echo "ERROR: $*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not installed. $2"
}

# Renders __USER_HOME__ / __USER_UID__ placeholders in a systemd unit and
# installs it under /etc/systemd/system, since root-run units can't use the
# %h specifier (that only expands for the invoking user, and these run as
# root for /dev/uinput access).
install_system_unit() {
  local src="$1" name
  name="$(basename "$src")"
  sed -e "s|__USER_HOME__|$HOME|g" -e "s|__USER_UID__|$(id -u)|g" "$src" \
    | sudo tee "/etc/systemd/system/$name" >/dev/null
  info "Installed /etc/systemd/system/$name"
}

install_user_unit() {
  local src="$1" name dest_dir
  name="$(basename "$src")"
  dest_dir="$HOME/.config/systemd/user"
  mkdir -p "$dest_dir"
  cp "$src" "$dest_dir/$name"
  info "Installed $dest_dir/$name"
}

install_bin() {
  local src="$1" dest="$HOME/.local/bin/$(basename "$1")"
  mkdir -p "$HOME/.local/bin"
  install -m 755 "$src" "$dest"
  info "Installed $dest"
}
