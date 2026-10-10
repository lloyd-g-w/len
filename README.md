# Len

Handwriting-first notes for **Windows, Linux and Android**: paged notebooks,
a truly infinite canvas, great stylus support (Samsung S Pen first), and
optional sync through a tiny server you host yourself.

- [Vision & requirements](docs/VISION.md)
- [Architecture](docs/ARCHITECTURE.md)
- [Sync protocol](docs/SYNC_PROTOCOL.md)
- [Self-hosting the sync server](server/README.md)

## Develop

On NixOS / with Nix:

```sh
nix develop            # Flutter + Linux desktop toolchain
cd app
flutter run -d linux   # or: flutter run -d <android-device-id>
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

## Using it

- **Pen / highlighter / eraser**: toolbar, or keys `P` / `H` / `E`.
- **S Pen**: hold the side button (or flip to the eraser end) to erase.
- **Navigate**: two fingers (or one, when *stylus only* is on), trackpad,
  mouse wheel (Ctrl+wheel zooms), middle-drag.
- **Undo / redo**: `Ctrl+Z` / `Ctrl+Shift+Z`.
- **Sync**: Settings → enter your server URL and token.
