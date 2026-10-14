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

## Android: Google Play and F-Droid

Store texts and images live in `fastlane/metadata/android/en-US/` (the
layout both F-Droid and `fastlane supply` read): `title.txt`,
`short_description.txt` (≤ 80 characters), `full_description.txt`
(≤ 4000; `<b>` is the only markup), `changelogs/<versionCode>.txt` (one per
release, ≤ 500 characters; `1.txt` is 0.1.0+1), and `images/`: `icon.png`
(512²), `featureGraphic.png` (1024×500, the icon on the branding colour),
`phoneScreenshots/` (780×1560, the phone shots cropped to Play's 2:1 limit),
`sevenInchScreenshots/` (tablet portrait 800×1280) and `tenInchScreenshots/`
(tablet landscape 1280×800), all from the screenshot suites (`library`,
`editor`, `overview`, `pdf`; light theme). Play suggests ≥ 1080 px tablet
screenshots for some placements: render the tablet scenarios at 2× when that
matters.

### Google Play — needs the owner

- A Play developer account (one-time fee, identity verification) and the
  app created as `dev.len.len`.
- Signing: the release keystore (README *Android signing*) as the upload
  key; enrol in Play App Signing. Play wants an **AAB**: `flutter build
  appbundle --release` (not in the release workflow yet).
- Store listing from `fastlane/metadata` (by hand, or `fastlane supply` with
  a Play service-account JSON key — never commit it), data-safety form (no
  data collected; sync only to the user's own server), content rating
  questionnaire, privacy-policy URL (needed because of the microphone
  permission: TODO write one).
- ML Kit is fine on Play.

### F-Droid — blockers and the proposed `foss` flavor

F-Droid's main repository builds from source with only free dependencies.
Today's Len does not qualify:

1. ⚠️ **ML Kit (blocker).** `com.google.mlkit:digital-ink-recognition` and
   the `google_mlkit_digital_ink_recognition` plugin are proprietary Google
   libraries (they pull Play-services components). Lasso → *Convert to
   text* uses them.
2. ⚠️ **Licence (blocker):** none in the repository yet.
3. **Prebuilt native libraries fetched at build time:** `pdfium_dart`'s build
   hook downloads PDFium from `bblanchon/pdfium-binaries`, and `sqlite3`'s
   hook downloads a precompiled SQLite from GitHub. F-Droid wants them built
   from source: SQLite can be (`hooks: user_defines: sqlite3: source:
   source` with the amalgamation as a srclib); PDFium needs a srclib build or
   a reviewer's exception. Expect discussion here.

**Proposal: a `foss` flavor without ML Kit** (not implemented yet; Play
keeps the `play` flavor):

- Dart: stop importing `google_mlkit_digital_ink_recognition`; model
  checks and downloads go through Len's own `len/handwriting` channel like
  recognition already does (the Kotlin side calls ML Kit's
  `RemoteModelManager` directly). Then the pub dependency goes away and no
  per-store pubspec edits are needed. When the channel is missing
  (`MissingPluginException`), `createHandwritingRecognizer()` returns
  `UnavailableRecognizer`, which hides *Convert to text* as on desktops.
- Gradle: `productFlavors { play {}; foss {} }` in `android/app/build.gradle.kts`,
  `"playImplementation"("com.google.mlkit:digital-ink-recognition:19.0.0")`,
  `HandwritingRecognitionPlugin.kt` moved to `src/play/kotlin` and
  registered from a flavor-specific helper (`src/foss/kotlin` registers
  nothing).
- Builds: `flutter build apk --flavor play` (releases, Play) and
  `--flavor foss` (F-Droid, and a release asset for people avoiding Google
  code). The release workflow builds both once the flavors exist.

**F-Droid recipe** (for `fdroiddata`, `metadata/dev.len.len.yml`, once the
above is done):

```yaml
Categories: [Writing]
License: TODO            # SPDX id of the chosen licence
SourceCode: https://github.com/lloyd-g-w/len
IssueTracker: https://github.com/lloyd-g-w/len/issues
AutoName: Len
RepoType: git
Repo: https://github.com/lloyd-g-w/len.git
Builds:
  - versionName: X.Y.Z
    versionCode: N
    commit: vX.Y.Z
    subdir: app
    sudo:
      - apt-get update
      - apt-get install -y openjdk-17-jdk-headless
    output: build/app/outputs/flutter-apk/app-foss-release.apk
    srclibs:
      - flutter@3.47.4     # = FLUTTER_VERSION in the workflows / flake
    prebuild:
      - export PUB_CACHE=$(pwd)/.pub-cache
      - $$flutter$$/bin/flutter config --no-analytics
      - $$flutter$$/bin/flutter pub get
    build:
      - export PUB_CACHE=$(pwd)/.pub-cache
      - $$flutter$$/bin/flutter build apk --release --flavor foss
AutoUpdateMode: Version
UpdateCheckMode: Tags
```

**Reproducible builds** let F-Droid ship the APK signed with Len's own key
(`Binaries:` + `AllowedAPKSigningKeys:`), so users can move between GitHub,
F-Droid and Play builds: pin Flutter (done: `FLUTTER_VERSION`), JDK 17 and
the Gradle wrapper; keep R8 deterministic (no `-printmapping` timestamps);
build from the tag with a clean `PUB_CACHE`; compare with `apksigcopier`
(`fdroid build` does this). Untested so far — the first F-Droid build will
show which inputs still differ (typical culprits: build paths in native
libraries, `pubspec.lock` drift).

## Windows: installer, signing and winget

### winget

`app/windows/winget/` holds the manifest templates (schema 1.10.0: version,
installer, default locale) for the Inno Setup installer: per-user install by
default (`/CURRENTUSER`), all users with `/ALLUSERS` (elevates itself),
`ProductCode` = the installer's `AppId` + `_is1`, upgrade in place, the file
types and `len://` it registers. The release job fills them (`fill.sh`:
version, the release asset's URL and SHA-256, date, release-notes URL) and
attaches `len-X.Y.Z-winget-manifests.zip` in the `microsoft/winget-pkgs`
layout (`manifests/l/Len/Len/X.Y.Z/`). Checked here: filled from a dummy
setup, all three validate against Microsoft's 1.10.0 JSON schemas
(`winget validate` itself needs Windows).

Needs the owner:

- ⚠️ `License:` is `TODO` (the job warns): winget-pkgs requires it.
- Choose the identifier for good (`Len.Len` = Publisher.Name).
- Submit: unzip and open a PR to `microsoft/winget-pkgs`, or
  `wingetcreate submit --token <GitHub PAT> manifests/l/Len/Len/X.Y.Z` (on
  Windows). Automating it needs a PAT secret (e.g. `WINGET_TOKEN`) and
  `wingetcreate update Len.Len --urls … --version … --submit` in the release
  job; not wired up (no secret exists).

### Code signing (needs a certificate)

Unsigned, SmartScreen warns on the setup until it earns reputation and some
antivirus heuristics distrust it; winget accepts unsigned installers.
Signing needs a code-signing certificate. Since 2023 private keys must live
in hardware (HSM / token), so a plain `.pfx` in a CI secret is no longer an
option. Choices, roughly by cost:

1. **SignPath Foundation** — free signing for open-source projects (needs an
   OSI licence first, then their application and review). Signs in their
   HSM from a GitHub Actions step.
2. **Azure Trusted Signing** — a small monthly fee, identity validation of
   the publisher (individuals or organisations, availability by country);
   `azure/trusted-signing-action` in the workflow with an Azure app
   registration's client id / tenant / secret as secrets.
3. **An OV / EV certificate from a CA** on a cloud HSM (DigiCert KeyLocker,
   SSL.com eSigner, …), used through their `signtool` integration.

Steps once there is one (all on the `windows` job, before zipping):

1. Sign the app itself: `signtool sign /fd sha256 /tr <RFC 3161 timestamp
   URL> /td sha256 <cert options> app\build\windows\x64\runner\Release\len.exe`
   (the DLLs Len builds may be signed the same way; Flutter's own are
   unsigned upstream).
2. Build the installer signed: `iscc /DSign "/Slen=signtool sign /fd sha256
   /tr … /td sha256 <cert options> $f" …` — `len.iss` then sets
   `SignTool=len` and `SignedUninstaller=yes` (setup and uninstaller signed).
3. Check: `signtool verify /pa /v len-X.Y.Z-windows-x64-setup.exe`.
4. Keep the publisher name identical across releases (SmartScreen reputation
   is per certificate / publisher). MSIX (README *Windows installer*) becomes
   an option once signing works.
