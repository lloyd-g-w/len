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
- **ui/** shared widgets and design tokens (`app_theme.dart`, which exports
  `design_tokens.dart` and `surfaces.dart`). Use the shared components instead
  of local styling: `AppDialog` / `confirmAction` for dialogs (their buttons lay out through
  `DialogActions`), `showMessage`
  for snack bars, `MenuRow` for popup menus, `showAdaptivePopover` for live
  settings, `showDialogOrSheet` + `SheetHeader` / `SheetActions` for task
  sheets, `FloatingPanel` for anything floating over the canvas,
  `SectionLabel` for group headings, `EvenGrid` for swatches, `ChipSurface`
  around chips on dialogs and sheets. Copy is sentence
  case; commands that ask something first end in …; single-sentence messages
  have no full stop.

## Design tokens (REDESIGN §1)

No magic numbers or ad-hoc colours in `features/`: pick a token.

- **Spacing:** `Gaps` (2, 4, 8, 12, 16, 24, 32, 48). **Radii:** `xs` 6 (chips,
  badges, the selected-tool plate), `sm` 10 (buttons, fields, covers,
  thumbnails), `md` 14 (menus, popovers, floating panels, snack bars), `lg` 20
  (dialogs, sheets), `pill`.
- **Type:** Inter only, six roles from `Theme.of(context).textTheme`:
  `titleLarge` (screen titles), `titleMedium` (dialog titles, the notebook
  title), `bodyMedium` (rows), `labelLarge` (buttons, menu rows, card titles),
  `bodySmall` (captions; already `onSurfaceVariant`), `labelSmall`
  (`SectionLabel`). Don't set `fontSize` / `fontWeight` on UI text; numbers
  that change in place use `AppTheme.tabularFigures`.
- **Colour:** the accent (`colorScheme.primary`, ink blue) only for primary
  buttons, focus rings, selection handles, links, switches, progress and the
  selected sidebar row. Selected states otherwise use the neutral plate
  `Surfaces.pressed` with `onSurface`; hovers `Surfaces.hovered`. Ink and
  covers are never themed; fixed marker colours live in `Palette`.
  Destructive commands are `colorScheme.error`, last in menus.
- **Surfaces:** `Surfaces.canvasBackdrop` around pages; `Surfaces.chrome` +
  `Surfaces.chromeEdge` hairline for docked bars; `raised` (`FloatingPanel`,
  `Surfaces.raisedDecoration`, `Shadows.low`) for floating palettes, pills and
  menus over the canvas; `overlay` (`OverlaySurface`,
  `Surfaces.overlayDecoration`, `Shadows.high`) for popovers, menus, dialogs
  and sheets. Shadows only from `Shadows`; never Material `elevation`
  (menus excepted: Flutter offers no shadow hook there). No outlines in light
  mode; dark mode adds the hairline (`Surfaces.border`).
- **Icons:** Material Symbols Rounded only (`Symbols.*_rounded` from
  `package:material_symbols_icons/symbols.dart`; never `Icons.*`). Weight 300
  and fill 0 come from the theme; active or selected states pass `fill: 1`.
  Sizes from `Glyphs`: `bar` 20, `menu` 18, `empty` 40. Always reference
  symbols as `const` members (no lookups by name), so release builds keep
  tree-shaking the icon font.
- **Targets:** by input, not width. `Targets.touchFirst` (Android, or a coarse
  pointer on the web); `Targets.of(context, visual)`, `Targets.barHit` (48 on
  touch, 40 with a pointer), `Targets.slotHit` (44 / 36),
  `Targets.menuRowHeight` (48 on touch, 44 with a pointer). Bar buttons keep a 40-dp
  visual and pad their hit area (`MaterialTapTargetSize.padded`).
- **Motion:** `Motion.fast` 120 (state changes, popovers scaling from
  `Motion.popoverScale`), `medium` 200 (chrome fades, panels), `slow` 300
  (sheets, routes), `travel` 420. Chrome shows and hides with `ChromeFade`
  (fade + `Motion.chromeSlide` 8 px toward its edge; fades only when
  `Motion.reduced`). Taps never ripple: the theme uses `NoSplash` and a calm
  `onSurface` overlay (`ThemeComponents.calmOverlay` for custom button
  styles).

## Pre-release: breaking changes are fine

Len is far from its first release (user decision). **Do not keep code for
backwards compatibility**: no legacy data shims, no tolerance for old
record formats, no keeping removed features around for old data. Change
formats, rename things, squash migrations and drop old tools freely when it
makes the code better â just keep the code base itself consistent and the
tests green. (Forward-compat rules below apply once we ship.)

Safety net for old local data: a database whose schema doesn't match what
the current migrations produce (or that is newer, or fails to migrate) is
copied aside as `len.db.schema-<version>-<time>.bak` (native; browsers
can't keep it) and started fresh, keeping the sync login; the library tells
the user once (`SchemaCheck`, `AppDatabase.schemaReset`). So rewriting
migrations needs no manual cleanup — but don't rely on it once we ship.

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
- Schema changes: **append** a migration to `SchemaMigrations.all` (version 1
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
