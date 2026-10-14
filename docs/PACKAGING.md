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

## Linux: Flatpak and Flathub

`app/linux/packaging/flatpak/dev.len.len.yml` repackages the release tarball
on the GNOME runtime (README *Release → Flatpak*; the release workflow's
`flatpak` job builds `len-X.Y.Z-linux-x64.flatpak`).

- **Audio recording works in the Flatpak.** record_linux runs `parecord`
  (PCM from the sound server) piped into `ffmpeg` (AAC in ADTS). The GNOME
  runtime ships both — `parecord` (PulseAudio 17 `pacat`) and an `ffmpeg`
  whose libavcodec has the native AAC encoder and the ADTS muxer — and
  `--socket=pulseaudio` lets them reach the microphone (PipeWire systems
  serve it through `pipewire-pulse`). Nothing is bundled; playback uses the
  runtime's GStreamer (`libav` for AAC). The earlier "doesn't work" note was
  an assumption, checked wrong for GNOME 51:
  `flatpak/check-runtime-recording.sh` pulls the runtime's `bin/` and `lib/`
  with ostree (no flatpak or user namespaces needed), runs its `parecord`
  with record_linux's arguments against a throwaway PulseAudio sine source
  and its `ffmpeg` with record_linux's encoder arguments, and checks the
  result is ADTS AAC. Run it when bumping `runtime-version`.
- **Manifest checked here** without building (this machine has no user
  namespaces, so no `flatpak-builder` build): `flatpak-builder
  --show-manifest` parses it; its build commands, run against an unpacked
  bundle with `/app` redirected, install the expected tree (`bin/len`,
  `lib/len/…`, desktop entry, MIME package, icons, metainfo). The release
  job builds it for real.
- **AppStream** (`dev.len.len.metainfo.xml`) passes `appstreamcli validate
  --pedantic` (screenshot URLs resolve only once the files are on `main`):
  summary, description, launchable, URLs (homepage, bug tracker, source),
  branding colours, five captioned screenshots from the screenshot suites
  (`app/linux/packaging/screenshots/`, desktop 1440×900: notebook, library,
  canvas, pages, dark mode), provides (binary, MIME types incl.
  `application/x-len`), controls, display length, keywords, OARS 1.1 content
  rating (all "none": no social features, ads or tracking; sync only talks to
  the user's server) and release notes for 0.1.0. Refresh the screenshots
  with `flutter test test/screenshots/{library,editor,overview}_screenshot_test.dart
  --dart-define=SCREENSHOTS=true` and copy `library_desktop_light`,
  `editor_desktop_{paged,canvas}_light`, `overview_desktop_light`,
  `editor_desktop_paged_dark`.

### Flathub: what the owner must do

- ⚠️ **Licence (blocker):** the repository has no licence. Flathub (and
  F-Droid) only publish software with one. Add `LICENSE`, then
  `<project_license>SPDX-ID</project_license>` to the metainfo.
- ⚠️ **App id:** `dev.len.len` claims the domain `len.dev`. Flathub checks
  that the submitter controls the id's domain (verification needs a token on
  `https://len.dev/.well-known/org.flathub.VerifiedApps.txt`). Without it,
  rename to `io.github.lloyd_g_w.Len` (Android keeps its own id).
- **Submission:** a PR to `flathub/flathub` (branch `new-pr`) with the
  manifest, its archive source switched to the release tarball's `url` +
  `sha256` (Flathub builds offline) and `x-checker-data` for update bots.
  Reviewers prefer building from source; repackaging a release binary is
  accepted for apps whose toolchain is impractical in the sandbox (Flutter
  needs network for `pub get`) but may be questioned — the alternative is
  `flatpak-flutter` (vendors the pub packages and the Flutter SDK as
  sources).
- **Account:** a GitHub account owns the Flathub repo after acceptance;
  nothing else to sign.
