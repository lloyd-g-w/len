#!/usr/bin/env sh
# Adds Len to the desktop's application menu for the current user:
# a launcher (.desktop file) pointing at this bundle, plus the app icons.
#   ./install-desktop-entry.sh             install
#   ./install-desktop-entry.sh --uninstall remove again
# Keep the bundle where it is (or re-run this after moving it).
set -eu
here="$(cd "$(dirname "$0")" && pwd)"
data="${XDG_DATA_HOME:-$HOME/.local/share}"
apps="$data/applications"
icons="$data/icons/hicolor"

if [ "${1:-}" = "--uninstall" ]; then
  rm -f "$apps/dev.len.len.desktop"
  find "$icons" -name 'dev.len.len.*' -delete 2>/dev/null || true
  echo "Removed Len from the application menu."
  exit 0
fi

mkdir -p "$apps" "$icons"
cp -r "$here/share/icons/hicolor/." "$icons/"
sed "s|^Exec=.*|Exec=\"$here/len\"|" "$here/share/applications/dev.len.len.desktop" \
  > "$apps/dev.len.len.desktop"
command -v update-desktop-database >/dev/null && update-desktop-database "$apps" || true
command -v gtk-update-icon-cache >/dev/null && gtk-update-icon-cache -q -t "$icons" || true
echo "Installed: $apps/dev.len.len.desktop"
