# Shared helpers, sourced by every component install.sh. Not meant to be run directly.

info()  { echo "==> $*"; }
warn()  { echo "WARNING: $*" >&2; }
die()   { echo "ERROR: $*" >&2; exit 1; }

require_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "'$1' is required but not installed. $2"
}

# Scripts run by root system units live here: root-owned, outside $HOME. A unit
# that executes anything the session user can rewrite hands that user root --
# edit the script, or for Python just drop a module beside it (the script's
# directory comes first on sys.path), and the next service start runs it as
# root. Units also start Python with -I, which keeps the script's directory,
# user site-packages and PYTHON* variables out of the interpreter entirely.
ROOT_LIBDIR=/usr/local/lib/omarchy-surface-touch

# Renders __USER_HOME__ / __USER_UID__ / __ROOT_LIBDIR__ placeholders in a systemd unit and
# installs it under /etc/systemd/system, since root-run units can't use the
# %h specifier (that only expands for the invoking user, and these run as
# root for /dev/uinput access).
install_system_unit() {
  local src="$1" name
  name="$(basename "$src")"
  sed -e "s|__USER_HOME__|$HOME|g" -e "s|__USER_UID__|$(id -u)|g" \
      -e "s|__ROOT_LIBDIR__|$ROOT_LIBDIR|g" "$src" \
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

# For scripts a root system unit executes. Never use install_bin for those.
install_root_bin() {
  local src="$1" name
  name="$(basename "$src")"
  sudo install -d -m 755 -o root -g root "$ROOT_LIBDIR"
  sudo install -m 755 -o root -g root "$src" "$ROOT_LIBDIR/$name"
  info "Installed $ROOT_LIBDIR/$name (root-owned)"
  # Earlier versions put this in ~/.local/bin and root ran it from there.
  # Nothing executes that copy any more; remove it so nobody edits it
  # expecting an effect.
  if [[ -e "$HOME/.local/bin/$name" ]]; then
    rm -f "$HOME/.local/bin/$name"
    info "Removed $HOME/.local/bin/$name (root no longer runs it from there)"
  fi
}
