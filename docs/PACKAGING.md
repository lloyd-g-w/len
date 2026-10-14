# Packaging and store listings

How Len is packaged per platform, what each package bundles and what it takes
from the system, and what is still needed (from the owner: licence, signing
keys, store accounts) before publishing to stores. Build and release steps
are in the README (*Release*); this file keeps the decisions.

## Linux: AppImage

`app/linux/packaging/appimage/build-appimage.sh <bundle> <out.AppImage>`
turns the Linux release bundle (`flutter build linux --release`, or the
unpacked release tarball) into `len-X.Y.Z-linux-x64.AppImage`; the release
workflow's `appimage` job does this from the tarball and attaches the
AppImage and its `.zsync` (update information `gh-releases-zsync`, so
AppImageUpdate / Gear Lever can update in place). appimagetool and the
type-2 runtime are pinned by version and SHA-256 and run without FUSE.

- **AppDir = the bundle as is** (`len`, `lib/`, `data/`, `share/`) plus
  `AppRun`, the desktop entry and icon at the root and `usr/share → share`.
  The runner keeps finding its libraries and window icon next to itself.
- **Desktop integration:** the desktop entry carries the MIME types
  (`application/pdf`, PNG / JPEG / WebP, `application/x-len` for `.len`) and
  the `len://` scheme with `Exec=len %U`. AppImages cannot register MIME
  types by themselves, so `Len.AppImage --install-desktop-entry` runs the
  bundle's `install-desktop-entry.sh` with `Exec` pointing at the AppImage
  (menu entry, icons, the `.len` type); `--uninstall-desktop-entry` removes
  it. appimaged / Gear Lever integrate the root desktop entry as usual.
- **Bundled vs required (decided):** the AppImage bundles exactly what the
  tarball does — Len, the Flutter engine, SQLite, PDFium and the plugins'
  libraries. It does **not** bundle GTK 3, libsecret, GStreamer (and its
  plugins), `parecord` or `ffmpeg`:
  - GTK, GStreamer and their plugins load modules, themes, GL drivers and
    the sound server's client libraries from the host; bundled copies break
    on mismatches (the AppImage project's exclude list says the same of
    glibc, GL and friends) and would triple the size. Every desktop that runs
    GTK apps has GTK 3 and GStreamer.
  - `parecord` is a client of the host's sound server (PulseAudio, or
    PipeWire's `pipewire-pulse`): it belongs to that server's packages.
  - `ffmpeg` is the one often missing (not installed by default on Ubuntu
    or Fedora). Len says so where recording starts ("Recording needs
    ffmpeg …"); everything else works without it. Bundling a small static
    ffmpeg (AAC encoder + ADTS muxer only) is the follow-up if users trip on
    it.
  - Required at run time, as for the tarball: glibc ≥ the build machine's
    (the release builds on `ubuntu-latest`, 24.04: glibc 2.39), GTK 3,
    libsecret (the sync token goes to the keyring), GStreamer with
    -good and an AAC decoder (playback), `parecord` + `ffmpeg` (recording).
- **Verified here** (NixOS, no FUSE): built from a local release bundle;
  `tool/appimage_smoke.sh` ran it under `xvfb-run` with Mesa, given a `.len`
  file and a PDF on the command line — both opened as tabs (notebook and
  imported PDF), no errors logged; `--install-desktop-entry` wrote a desktop
  entry with `Exec="<path to the AppImage>" %U`, icons and the MIME package.
