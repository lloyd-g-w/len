#!/usr/bin/env bash
# Fills the winget manifest templates (this directory) for a release:
#
#   app/windows/winget/fill.sh <version> <setup.exe> <owner/repo> <out dir>
#
# writes <out dir>/manifests/l/Len/Len/<version>/*.yaml, the layout of
# microsoft/winget-pkgs (submit with `wingetcreate submit <dir>` or a PR;
# docs/PACKAGING.md "Windows"). The installer URL is the GitHub release
# asset; its SHA-256 comes from <setup.exe>, which must be that asset.
set -euo pipefail
[ $# -eq 4 ] || { sed -n '2,8p' "$0" >&2; exit 2; }
version=$1 setup=$2 repo=$3 out=$4
here=$(cd "$(dirname "$0")" && pwd)
name=$(basename "$setup")
url="https://github.com/$repo/releases/download/v$version/$name"
sha=$(sha256sum "$setup" | cut -d' ' -f1 | tr a-f A-F)
date=$(date -u +%Y-%m-%d)
dir="$out/manifests/l/Len/Len/$version"
mkdir -p "$dir"
for f in "$here"/Len.Len*.yaml; do
  sed -e "s|{{VERSION}}|$version|g" -e "s|{{URL}}|$url|g" -e "s|{{SHA256}}|$sha|g" \
    -e "s|{{DATE}}|$date|g" -e "s|{{RELEASE_URL}}|https://github.com/$repo/releases/tag/v$version|g" \
    "$f" >"$dir/$(basename "$f")"
done
if grep -q '{{' "$dir"/*.yaml; then
  echo "winget: unfilled placeholders in $dir" >&2
  exit 1
fi
if grep -q '^License: TODO' "$dir"/*.yaml; then
  echo "::warning::winget manifests: License is TODO (add a LICENSE first; winget-pkgs rejects it)"
fi
echo "winget: manifests in $dir"
