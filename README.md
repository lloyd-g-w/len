# Len

Handwriting-first notes for **Windows, Linux, Android and the Web**: paged notebooks,
a truly infinite canvas, great stylus support (Samsung S Pen first), and
optional sync through a tiny server you host yourself.

- [Vision & requirements](docs/VISION.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Sync protocol](docs/SYNC_PROTOCOL.md)
- [Self-hosting the sync server](server/README.md)

## Install

Download the latest build from
[GitHub Releases](https://github.com/lloyd-g-w/len/releases):

| Platform | File | How |
|----------|------|-----|
| Android 7+ | `len-X.Y.Z-android-arm64-v8a.apk` (most phones/tablets; `-universal` if unsure) | Open the APK and allow installing from your browser/file manager. |
| Windows 10/11 (x64) | `len-X.Y.Z-windows-x64.zip` | Unzip anywhere, run `len.exe`. |
| Linux (x64) | `len-X.Y.Z-linux-x64.tar.gz` | Unpack, run `./len`; `./install-desktop-entry.sh` adds it to your application menu (`--uninstall` removes it). Needs GTK 3 and GStreamer (with the -good and an AAC plugin, for audio playback); recording uses `parecord` and `ffmpeg`. |
| Web | `len-X.Y.Z-web.zip` | Static site: unzip and serve it with any web server (headers: see *Develop*). |

For sync, run the server: [server/README.md](server/README.md) (Docker image
`ghcr.io/lloyd-g-w/len-sync`). `SHA256SUMS` lists the checksums of all files.

## Develop

On NixOS / with Nix:

```sh
nix develop            # Flutter + Linux desktop toolchain
cd app
flutter run -d linux   # or: -d chrome, -d <android-device-id>
flutter analyze && flutter test
```

> **NixOS note:** run the Linux build from inside `nix develop`. nixpkgs' Flutter
> engine library carries its own RUNPATH, which hides the bundled
> `libsqlite3.so`; the dev shell supplies SQLite via `LD_LIBRARY_PATH`.

Without Nix, install Flutter ≥ 3.47 and follow
[flutter.dev/desktop](https://docs.flutter.dev/platform-integration/desktop).

| Target  | Build on        | Command                      |
|---------|-----------------|------------------------------|
| Linux   | Linux           | `flutter build linux`        |
| Android | Linux / Windows | `flutter build apk`          |
| Windows | Windows         | `flutter build windows`      |
| Web     | any             | `flutter build web` (or `--wasm`) |

The web build (`app/build/web`) is a static site (installable as a PWA):
serve it from any web server, e.g. `python3 -m http.server -d build/web`.
Data stays in the browser (SQLite in IndexedDB); one tab at a time. To sync,
the server must allow the site's origin (`LEN_CORS_ORIGINS`, default `*`).
For `--wasm` builds, serve with `Cross-Origin-Opener-Policy: same-origin` and
`Cross-Origin-Embedder-Policy: require-corp` to enable multi-threaded
rendering (it works without, single-threaded).

The Linux bundle (`build/linux/x64/release/bundle`) also contains
`share/applications/dev.len.len.desktop`, the icons (`share/icons/hicolor`)
and `install-desktop-entry.sh`; packagers can copy `share/` into `/usr`
(with `Exec=len` on the `PATH`).

**Icons** for every platform are generated from one design by
`app/tool/generate_icons.sh` (glyph in `app/tool/branding/glyph.path`, colours
and geometry in the script). Re-run it after changing either and commit the
output.

## Release

1. Bump `version: X.Y.Z+N` in `app/pubspec.yaml` (`N`, the Android
   `versionCode`, must increase with every release).
2. Tag and push: `git tag vX.Y.Z && git push origin vX.Y.Z`.

The [release workflow](.github/workflows/release.yml) checks that the tag
matches the pubspec, builds the APKs (universal + per ABI), the Linux tarball,
the Windows zip and the web zip, attaches them to a GitHub release, and
pushes the sync server image to `ghcr.io/<owner>/len-sync` (`X.Y.Z`, `X.Y`,
`latest`; amd64 + arm64). CI ([ci.yml](.github/workflows/ci.yml)) runs on
every push / PR: analyze + tests (app and server) and all builds. Both pin
the Flutter version used by `flake.nix` (`FLUTTER_VERSION`); bump them
together.

### Android signing

Without a keystore, release APKs are signed with the debug key: fine for
trying them out, but Android only installs updates signed with the **same**
key, so create one release key before publishing and keep it safe (losing it
means users must uninstall to update):

```sh
# keytool ships with the JDK (Nix: nix shell nixpkgs#jdk17)
keytool -genkeypair -v -keystore ~/len-release.jks -alias len \
  -keyalg RSA -keysize 4096 -validity 10000
```

- **Local builds:** create `app/android/key.properties` (git-ignored):

  ```properties
  storeFile=/home/you/len-release.jks
  storePassword=…
  keyAlias=len
  keyPassword=…
  ```

  `flutter build apk --release` then signs with it.
- **GitHub releases:** add repository secrets `ANDROID_KEYSTORE_BASE64`
  (`base64 -w0 ~/len-release.jks`), `ANDROID_KEYSTORE_PASSWORD`,
  `ANDROID_KEY_ALIAS` and `ANDROID_KEY_PASSWORD`. The image push to GHCR uses
  the built-in `GITHUB_TOKEN` (no secret needed); make the `len-sync` package
  public under *Packages → Package settings* after the first push so
  `docker pull` works without logging in.

Release builds use R8 code + resource shrinking
(`app/android/app/proguard-rules.pro` for keep rules).

## Using it

- **Pen / highlighter / eraser**: toolbar, or keys `P` / `H` / `E`.
- **S Pen**: hold the side button (or flip to the eraser end) to erase.
- **Navigate**: two fingers (or one, when *stylus only* is on), trackpad,
  mouse wheel (Ctrl+wheel zooms), middle-drag.
- **Undo / redo**: `Ctrl+Z` / `Ctrl+Shift+Z`.
- **Sync**: Settings → enter your server URL and token.
