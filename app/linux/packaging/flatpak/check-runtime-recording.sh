#!/usr/bin/env bash
# Checks that the Flatpak's runtime (runtime-version in dev.len.len.yml) still
# has what audio recording needs: `parecord` and an `ffmpeg` with the AAC
# encoder and ADTS muxer (record_linux pipes parecord's PCM into ffmpeg).
# Run it when bumping runtime-version. Needs Nix (ostree, PulseAudio) and
# no flatpak / user namespaces: it pulls only the runtime's bin/ and lib/
# from Flathub (~300 MB download, ~800 MB in a temporary directory) and runs
# its programs with its own dynamic loader, recording 3 s of a sine source
# from a throwaway PulseAudio server.
set -euo pipefail
if ! command -v ostree >/dev/null || ! command -v pulseaudio >/dev/null; then
  exec nix shell nixpkgs#ostree nixpkgs#pulseaudio -c "$0" "$@"
fi
here=$(cd "$(dirname "$0")" && pwd)
version=$(sed -n "s/^runtime-version: *'\{0,1\}\([^' ]*\).*/\1/p" "$here/dev.len.len.yml")
ref="runtime/org.gnome.Platform/x86_64/$version"
work=$(mktemp -d /tmp/len-runtime-check.XXXXXX)
trap 'pulseaudio -k 2>/dev/null || true; rm -rf "$work"' EXIT
cd "$work"

echo "check: pulling bin/ and lib/ of $ref"
ostree --repo=repo init --mode=bare-user-only
ostree --repo=repo remote add --no-gpg-verify flathub https://dl.flathub.org/repo/
ostree --repo=repo pull --disable-static-deltas --http-header=User-Agent=Flatpak/1.16.0 \
  --subpath=/files/bin --subpath=/files/lib flathub "$ref" >/dev/null
mkdir usr
ostree --repo=repo checkout -U --subpath=/files/bin "$ref" usr/bin
ostree --repo=repo checkout -U --subpath=/files/lib "$ref" usr/lib
rm -rf repo
lib="$work/usr/lib/x86_64-linux-gnu"
run() { "$lib/ld-linux-x86-64.so.2" --library-path "$lib:$lib/pulseaudio" "$@"; }

for tool in parecord ffmpeg; do
  [ -e "usr/bin/$tool" ] || { echo "check: the runtime has no $tool" >&2; exit 1; }
done
run usr/bin/ffmpeg -hide_banner -encoders 2>/dev/null | grep -q ' aac ' ||
  { echo "check: the runtime's ffmpeg has no AAC encoder" >&2; exit 1; }
run usr/bin/ffmpeg -hide_banner -muxers 2>/dev/null | grep -q ' adts ' ||
  { echo "check: the runtime's ffmpeg has no ADTS muxer" >&2; exit 1; }

export XDG_RUNTIME_DIR="$work/run"
mkdir -p "$XDG_RUNTIME_DIR"
pulseaudio -n --daemonize=yes --exit-idle-time=-1 --load=module-native-protocol-unix \
  --load='module-sine-source source_name=sine frequency=440' --load='module-always-sink'
sleep 1
# The arguments record_linux uses (capture_pipeline.dart, process_args.dart).
run usr/bin/pacat --record --device=sine --raw --format=s16le --rate=44100 --channels=1 \
  --latency-msec=100 >pcm 2>/dev/null &
pid=$!
sleep 3
kill "$pid"
wait "$pid" 2>/dev/null || true
run usr/bin/ffmpeg -hide_banner -loglevel error -f s16le -ar 44100 -ac 1 -i - \
  -c:a aac -b:a 64k out.aac <pcm
bytes=$(stat -c %s out.aac)
head=$(od -An -tx1 -N2 out.aac | tr -d ' ')
[ "$bytes" -gt 10000 ] && [ "${head:0:3}" = fff ] ||
  { echo "check: no ADTS AAC recorded ($bytes bytes, header $head)" >&2; exit 1; }
echo "check: $ref records: parecord → ffmpeg wrote $bytes bytes of ADTS AAC"
