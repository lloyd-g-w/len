# Len â Code Conventions

Read `docs/ARCHITECTURE.md` first. These rules keep the codebase clean as it grows.

## Layering (`app/lib`)

`domain/` â `data/` â `sync/` â `ink/` â `features/` + `ui/`. Lower layers never import
higher ones. `domain/` is plain Dart models (may use `dart:ui` geometry types).

- **domain/** immutable models, `copyWith`, value semantics where useful.
- **data/** SQLite repositories. Every syncable table extends `SyncableTable`
  (columns `updated_at, device_id, deleted, dirty`), uses `nextVersion()` for
  local writes, and is registered in `SyncEngine` + `AppServices`.
- **ink/** drawing engine: models, input routing, rendering. No Material widgets
  except in `ink_surface.dart`.
- **features/<area>/** screens and their private widgets.
- **ui/** shared widgets and design tokens (`app_theme.dart`). Use tokens
  (`Radii`, `Gaps`, `Motion`, palette) instead of magic numbers, and the shared
  components instead of local styling: `AppDialog` / `confirmAction` for dialogs,
  `showMessage` for snack bars, `MenuRow` for popup menus, `SectionLabel` for
  group headings, `EvenGrid` for swatches. Copy is sentence case; commands that
  ask something first end in …; single-sentence messages have no full stop.

## Pre-release: breaking changes are fine

Len is far from its first release (user decision). **Do not keep code for
backwards compatibility**: no legacy data shims, no tolerance for old
record formats, no keeping removed features around for old data. Change
formats, rename things, squash migrations and drop old tools freely when it
makes the code better â just keep the code base itself consistent and the
tests green. (Forward-compat rules below apply once we ship.)

## Rules

- `flutter analyze` must report **no issues**; `flutter test` must pass.
- Small files (aim < 300 lines), small functions, doc comments on public APIs.
- No new state-management framework: `ChangeNotifier` + `ListenableBuilder`.
- New packages only when they clearly earn their place and support
  **Android, Linux, Windows and Web** (or are confined to a
  `platform/*_native.dart` file). Pin with `^` constraints.
- No `dart:io`, `dart:isolate`, `dart:ffi` or `path_provider` outside
  `lib/platform/*_native.dart` (and code only those import); add a
  conditional-export abstraction instead (see ARCHITECTURE "Platforms").
  Mind web integers: no negative or â¥ 31-bit shifts, no 64-bit `ByteData`.
- Schema changes: **append** a migration to `AppDatabase._migrations` (version 1
  creates the whole schema); never edit one that has shipped.
- New synced data: add a collection (documented in `docs/SYNC_PROTOCOL.md`) and
  parse it strictly with `RecordFields` (every field required; malformed â
  skipped). Once we ship: new fields optional, unknown fields/values tolerated
  (backward and forward compatibility).
  Large binary data (images, PDFs) goes through content-addressed blobs.
- Strokes are immutable: editing = remove old + add new (works with undo + sync).
- Every user-visible edit on a surface must be undoable via `UndoHistory`.
- Write unit tests for logic, widget tests for non-trivial UI flows.
- Format with `dart format -l 100`.

## Tooling (NixOS)

```sh
nix develop -c bash -c 'cd app && flutter analyze && flutter test'
nix develop -c bash -c 'cd app && flutter build web --release'   # web must keep compiling
nix develop .#android -c bash -c 'cd app && flutter build apk --debug'
app/tool/generate_icons.sh   # after changing the icon design (commit the output)
```

CI (`.github/workflows/ci.yml`) pins the same Flutter version as `flake.nix`;
when nixpkgs bumps Flutter, update `FLUTTER_VERSION` in both workflows.

Visual checks: prefer golden-style widget tests that write PNGs
(`matchesGoldenFile` + `flutter test --update-goldens`) and inspect them, or run
the Linux build (`flutter build linux` then `build/linux/x64/release/bundle/len`)
with `XDG_DATA_HOME=$(mktemp -d)` and screenshot with `nix run nixpkgs#grim -- out.png`.
