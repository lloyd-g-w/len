#!/usr/bin/env bash
# Builds the Len AppImage from a Linux release bundle (no Flutter needed):
#
#   app/linux/packaging/appimage/build-appimage.sh <bundle dir> <out.AppImage> [appimagetool args…]
#   e.g. … build/linux/x64/release/bundle /tmp/len-0.1.0-linux-x64.AppImage
#
# The AppDir is the bundle itself plus AppRun (this directory), the desktop
# entry and icon at its root and usr/share → share (AppStream metadata for
# appimagetool's check). Like the tarball, it bundles Flutter, SQLite and
# Len; GTK 3, libsecret, GStreamer, parecord and ffmpeg come from the
# system (README "Install"; docs/PACKAGING.md says why).
#
# appimagetool and the AppImage runtime are pinned and checked by SHA-256
# (cached in ~/.cache/len-packaging); APPIMAGETOOL / APPIMAGE_RUNTIME
# override them. Set VERSION to stamp X-AppImage-Version.
set -euo pipefail

tool_version=1.9.1
tool_sha=ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0
runtime_version=20251108
runtime_sha=2fca8b443c92510f1483a883f60061ad09b46b978b2631c807cd873a47ec260d

[ $# -ge 2 ] || { sed -n '2,5p' "$0" >&2; exit 2; }
bundle=$(realpath "$1")
out=$(realpath -m "$2")
shift 2
here=$(cd "$(dirname "$0")" && pwd)
[ -x "$bundle/len" ] || { echo "build-appimage: no Len bundle in $bundle" >&2; exit 1; }

cache="${XDG_CACHE_HOME:-$HOME/.cache}/len-packaging"
fetch() { # <file> <url> <sha256>
  local file="$cache/$1"
  if ! echo "$3  $file" | sha256sum -c --status 2>/dev/null; then
    mkdir -p "$cache"
    curl -fsSL --retry 3 -o "$file.part" "$2"
    echo "$3  $file.part" | sha256sum -c --status ||
      { echo "build-appimage: checksum mismatch for $2" >&2; rm -f "$file.part"; exit 1; }
    mv "$file.part" "$file"
  fi
  chmod +x "$file"
  echo "$file"
}
tool="${APPIMAGETOOL:-$(fetch "appimagetool-$tool_version-x86_64.AppImage" \
  "https://github.com/AppImage/appimagetool/releases/download/$tool_version/appimagetool-x86_64.AppImage" \
  "$tool_sha")}"
runtime="${APPIMAGE_RUNTIME:-$(fetch "runtime-$runtime_version-x86_64" \
  "https://github.com/AppImage/type2-runtime/releases/download/$runtime_version/runtime-x86_64" \
  "$runtime_sha")}"

work=$(mktemp -d /tmp/len-appimage.XXXXXX)
trap 'rm -rf "$work"' EXIT
appdir="$work/Len.AppDir"
cp -a "$bundle" "$appdir"
install -m755 "$here/AppRun" "$appdir/AppRun"
cp "$appdir/share/applications/dev.len.len.desktop" "$appdir/"
cp "$appdir/share/icons/hicolor/256x256/apps/dev.len.len.png" "$appdir/"
ln -s dev.len.len.png "$appdir/.DirIcon"
mkdir -p "$appdir/usr"
ln -s ../share "$appdir/usr/share"
# AppImage tools look for AppStream metadata under this (older) name.
ln -s dev.len.len.metainfo.xml "$appdir/share/metainfo/dev.len.len.appdata.xml"

# appimagetool's own check fetches the screenshot URLs (flaky in CI, and they
# exist only once on main): validate offline here, and skip its check.
if command -v appstreamcli >/dev/null; then
  appstreamcli validate --no-net "$appdir/share/metainfo/dev.len.len.metainfo.xml"
fi
# No FUSE needed: the tool AppImage runs extracted.
ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 "$tool" --no-appstream --runtime-file "$runtime" \
  "$@" "$appdir" "$out"
