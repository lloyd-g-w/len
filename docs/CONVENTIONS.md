# Len — Code Conventions

Read `docs/ARCHITECTURE.md` first. These rules keep the codebase clean as it grows.

## Layering (`app/lib`)

`domain/` ← `data/` ← `sync/` ← `ink/` ← `features/` + `ui/`. Lower layers never import
higher ones. `domain/` is plain Dart models (may use `dart:ui` geometry types).

- **domain/** immutable models, `copyWith`, value semantics where useful.
- **data/** SQLite repositories. Every syncable table extends `SyncableTable`
  (columns `updated_at, device_id, deleted, dirty`), uses `nextVersion()` for
  local writes, and is registered in `SyncEngine` + `AppServices`.
- **ink/** drawing engine: models, input routing, rendering. No Material widgets
  except in `ink_surface.dart`.
- **features/<area>/** screens and their private widgets.
- **ui/** shared widgets and design tokens (`app_theme.dart`). Use tokens
  (`Radii`, `Gaps`, palette) instead of magic numbers.

## Rules

- `flutter analyze` must report **no issues**; `flutter test` must pass.
- Small files (aim < 300 lines), small functions, doc comments on public APIs.
- No new state-management framework: `ChangeNotifier` + `ListenableBuilder`.
- New packages only when they clearly earn their place and support
  **Android, Linux and Windows**. Pin with `^` constraints.
- Schema changes: **append** a migration to `AppDatabase._migrations`; never edit
  an existing one.
- New synced data: add a collection (documented in `docs/SYNC_PROTOCOL.md`).
  Unknown fields/values must be tolerated (forward compatibility).
  Large binary data (images, PDFs) goes through content-addressed blobs.
- Strokes are immutable: editing = remove old + add new (works with undo + sync).
- Every user-visible edit on a surface must be undoable via `UndoHistory`.
- Write unit tests for logic, widget tests for non-trivial UI flows.
- Format with `dart format -l 100`.

## Tooling (NixOS)

```sh
nix develop -c bash -c 'cd app && flutter analyze && flutter test'
nix develop .#android -c bash -c 'cd app && flutter build apk --debug'
```

Visual checks: prefer golden-style widget tests that write PNGs
(`matchesGoldenFile` + `flutter test --update-goldens`) and inspect them, or run
the Linux build (`flutter build linux` then `build/linux/x64/release/bundle/len`)
with `XDG_DATA_HOME=$(mktemp -d)` and screenshot with `nix run nixpkgs#grim -- out.png`.
