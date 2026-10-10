# Len — Architecture

```
len/
├── app/        Flutter app (Windows, Linux, Android)
├── server/     Self-hosted sync server (Dart + SQLite, Docker)
├── docs/       Vision, architecture, sync protocol
└── flake.nix   Nix dev shell (Flutter + Linux desktop toolchain)
```

## App layers (`app/lib`)

Dependencies point downwards only.

| Layer        | Path            | Responsibility                                                         |
|--------------|-----------------|------------------------------------------------------------------------|
| UI           | `features/`, `ui/` | Screens (library, editor, settings, documents: templates, PDF import/export) and shared widgets / theme. |
| Ink engine   | `ink/`          | Surface model, viewport, input routing, rendering.                      |
| Sync         | `sync/`         | HTTP client, push/pull engine, scheduling + status.                     |
| Data         | `data/`         | SQLite schema, repositories, binary stroke codec, sync bookkeeping.     |
| Domain       | `domain/`       | Plain immutable models (`Notebook`, `NotebookPage`, `Stroke`) and the chunk grid. |
| Composition  | `app_services.dart` | Builds and owns every service; exposed to widgets via `AppScope`.   |

No state-management framework: long-lived objects are `ChangeNotifier`s
created in `AppServices` or in a screen's `State`, and widgets listen with
`ListenableBuilder`.

## Surfaces and strokes

Everything you draw on is a **surface**: each page of a paged notebook, or the
single plane of an infinite canvas (whose surface id is the notebook id).
A `Stroke` is immutable — it is only ever added or removed. That keeps sync
conflicts trivial and makes every cache keyed by stroke identity safe.

Stroke points are stored as a compact little-endian `float32` blob
(`x, y, pressure` = 12 bytes per point).

## The sparse infinite canvas

The world plane is cut into fixed **512 × 512 chunks** (`domain/chunk_grid.dart`).
The same grid drives three things:

1. **Storage index** — table `stroke_chunks(surface_id, cx, cy, stroke_id)`.
   Only populated chunks have rows, so empty space costs nothing.
2. **Lazy loading** — `SurfaceModel.ensureLoaded(visibleRect)` asks the DB which
   chunks around the viewport are populated, loads only the ones not yet in
   memory, and evicts far-away chunks once more than `maxLoadedChunks` are held.
3. **Render cache** — `ChunkPictureCache` records one `ui.Picture` per
   populated chunk, clipped to the chunk square (so strokes crossing chunk
   borders are never double-blended). A stroke edit invalidates only the chunks
   it touches. Painting visits only populated chunks intersecting the screen.

Rendering is split into three layers, each behind a `RepaintBoundary`:
paper (repaints on pan/zoom), committed ink (repaints on pan/zoom or edits),
and live ink (repaints on every pointer move — the stroke being drawn and the
eraser cursor), so drawing never re-renders the committed ink.

World coordinates are stored as `float32`, which stays sub-unit precise to
roughly ±8 million units from the origin — thousands of screens in every
direction.

## Paged notebooks (`features/editor/document/`)

A paged notebook is shown as one **document**: `DocumentLayout` places the
pages in "document space" — stacked vertically with gaps (continuous
scrolling, the default) or one page at a time (`PageFlow.single`, persisted
in settings). A single `ViewportController` pans/zooms the document;
`DocumentController` tracks the page list, the **current** page (shown in the
indicator: the page crossing the upper third of the screen) and the **active**
page (the one receiving input).

Strokes stay in **page-local** coordinates. The ink engine always works on one
surface, so `PageViewport` adapts the document viewport to the active page
(`world = document − page origin`) and forwards pans/zooms to the document;
`PagedDocumentView` makes the page under the first pointer of a gesture (or
under any stylus) active before handing the event to `InkInputController`.
Everything the engine draws or hit-tests therefore lands on the right page.

`DocumentSurfaces` holds a `SurfaceModel` + `ChunkPictureCache` only for
visible pages (plus a few recently seen ones, and any with undo history), and
loads just their visible chunks. It also provides **notebook-wide undo**: the
most recently edited page is undone first. Painting mirrors `InkSurface`
(paper → committed ink → live ink layers) across every visible page.

Page management (`PageActions`, `DocumentCommands`, `PageOverview`): insert,
duplicate (copies stroke rows wholesale via `SurfaceCopier`, so stroke
columns added later are copied too), delete (with an Undo snack bar that
re-saves the page's strokes), reorder (fractional sort keys, `PageOrder`;
the list is renumbered only when a gap is exhausted), bookmarks, templates.

## Templates (`domain/paper.dart`, `domain/paper_pattern.dart`)

`PaperStyle` names are stored and synced and never renamed (`lined` is wide
ruled, `grid` the large grid). `PaperPattern.of` computes a template's
geometry (lines with weights, dots) for an area, independent of the target:
`PaperRenderer` draws it on screen, in thumbnails and PNG export, and
`PdfExporter` writes the same lines as PDF vectors. Pages carry their paper
colour and size; new pages copy the current page's paper and size.

## Blobs and PDFs

Large binary data is **content-addressed**: a blob's id is the SHA-256 of its
bytes. `BlobStore` keeps files under `<app support>/blobs/<sha[0..2]>/<sha>`
and a `blobs` table (size, mime, uploaded flag). Each sync cycle first uploads
pending blobs (`BlobSync`, `HEAD` then `PUT`), then pushes records, so a
record never reaches the server before its blob. Blobs are fetched lazily
when a page needs them (`SyncController.fetchBlob`).

PDF import (`features/documents/pdf/`) stores the file once as a blob and
creates one page per PDF page with background `{type: pdf, blob, page}` and
the PDF page's size. PDF pages are rendered with PDFium via `pdfrx`
(`PdfRenderer`, serialised); `PdfBackgroundCache` renders at the current
zoom quantised to √2 steps (≤ 2896 px wide), keeps an LRU of images within a
memory budget and shows the best cached image while a sharper one renders.
PDFium itself is a native asset downloaded at build time by `pdfium_dart`'s
build hook (Linux, Windows, Android), so no system package is needed.

Export (`features/documents/export/`): `PdfExporter` (package `pdf`) writes
ink as filled polygons flattened from the exact outline paths the app
renders, templates as vector lines, and imported PDF pages as 150 dpi
images; PNG export rasterises a page with the same painters as the editor.
Files are saved with a save dialog on desktop (`file_selector`) and the share
sheet on Android (`share_plus`).

## Input (`ink/input/ink_input_controller.dart`)

Raw `Listener` pointer events (no gesture arena → no latency, full pressure data):

- **Stylus** draws; **eraser end** or **side button held** (S Pen) erases.
  A stylus touching down cancels a stroke a resting palm may have started.
- **Touch**: with *stylus only* (palm rejection) on, fingers pan/zoom; off,
  one finger draws and a second finger turns it into a pinch.
  Stylus-only switches on automatically the first time a stylus is used.
- **Mouse**: left draws, middle/right drag pans, wheel scrolls, Ctrl+wheel zooms.
- **Trackpad**: two-finger pan, pinch zoom.

Stroke outlines come from the in-house engine in `ink/render/` (see *Ink
rendering* below); paths are memoised per stroke. PDF export flattens the same
paths.

Resting the pen for 600 ms at the end of a stroke straightens it
(`input/hold_to_straighten.dart`); only the straight line is committed.

## Pens (`ink/pen/`, `ink/render/`)

The toolbar offers exactly two inks — the **pen** (`InkTool.ballpoint`) and the
**highlighter** — plus the eraser. A stroke's look = its `InkTool` + its
`StrokeStyle`:

- **`PenProfile`** (per tool, in code): pressure easing, nib, texture and
  flat highlighter caps. It also covers the tools earlier versions offered
  (`pen` (v0.1), `fountain`, `brush`, `pencil`, `marker`), so their strokes
  keep rendering; nothing creates them any more. Render constants must stay
  stable.
- **`PenDefaults`** (pen, highlighter): default colours, widths, feel settings,
  width range and taper factor offered in the UI.
- **`StrokeStyle`** (per stroke, stored in `strokes.style` and synced as
  `data.style`): opacity, thinning (pressure sensitivity), streamline
  (stabiliser) and start/end taper lengths. Missing → `StrokeStyle.defaultsFor`,
  which reproduces how v0.1 strokes looked. So a stroke renders identically on
  every device, whatever the local tool settings.

The legacy **fountain** nib adjusts per-point pressure so the radius shrinks
where the pen travels along a 45° nib (`render/nib.dart`); the legacy
**pencil** fills its outline with a world-anchored grain texture
(`render/pencil_texture.dart`). **Highlighter** strokes are translucent with
flat chisel ends, drawn before other ink in each chunk picture, and the live
highlighter stroke is painted on a layer beneath committed ink.

User customisation lives in `ToolSettings`, persisted as JSON in the local
`settings` table: per ink a `PenConfig` with **independent quick colours and
quick widths** (1–6 slots each, one of each selected) and feel settings
(pressure sensitivity, stabiliser, tapered ends; opacity for the highlighter —
the pen is always opaque), plus eraser options, hold-to-straighten and
favourite colours. Older settings with combined colour+width presets migrate:
preset colours become colour slots, preset widths width slots (topped up from
the defaults to three each); if a removed pen type was in use, its slots go to
the pen (`PenConfigJson`).

### Toolbar (`features/editor/`)

`EditorToolbar` is built from `ToolDescriptor`s (`editor_tools.dart`): icon,
label, shortcut, ink colour, a contextual *strip* and a settings popover.
More tools slot in by adding descriptors. For inks the strip is a row of
colour slots beside a row of width slots (dots at scaled real size) — one tap
picks either; tapping the selected slot (or long-pressing / right-clicking
any) edits it (colour picker, or slider with a live stroke preview; both can
remove the slot); `+` adds one. It lays out on one row when it fits, else on
two (phones). Shortcuts: P / H / E, 1–6 colour slots, [ / ] thinner / thicker.

### Ink rendering (`ink/render/`)

`StrokeOutline` turns points into a filled outline whose edges are smooth at
any zoom:

1. Drop duplicate samples, trim pen-down/pen-up hooks.
2. `Centerline`: resample at a uniform **arc-length** spacing (so filtering
   acts over distance, not over however many samples the digitiser sent),
   find sharp reversals (tips of `n`, `v`), and low-pass the positions per
   stretch between them with `2G − G∘G` (`LineFilters`): flat response for
   shapes larger than the filter, so loops keep their size, while jitter is
   removed. Beyond the ends the line is continued by a local quadratic fit
   through the end point, so ends neither lag (live stroke) nor bend.
   The filter scale grows with the stabiliser and (up to 4×) with width.
3. Radii (from pressure): non-swelling ends, Gaussian smoothing, a limit on
   radius change per unit length (no bumps), tapers.
4. `OutlineEmitter`: each side is the **envelope** of the circles along the
   centre line (tangent to every circle even where the radius changes),
   emitted as cubic Hermite pieces (decimated where nearly straight) — no
   polyline facets. Caps are arcs of the end circles that meet the sides
   tangentially. Where the inner side would fold (curvature × radius > 0.8)
   or at reversals, the outline is split into runs, each closed with round
   caps and wound alike, so the non-zero fill unions them seamlessly.

`OutlineSink` lets tests record the exact segments (tangent continuity is
asserted); specimens of synthetic 240 Hz handwriting with jitter and pressure
noise are rendered at 1×–16× in `test/ink_specimen_test.dart`. A 1000-point
stroke builds in well under a millisecond, so the live stroke is rebuilt on
every pointer move.

## Erasing

`SurfaceModel.eraseAlong` either removes whole strokes or, in *pixel* mode,
cuts the ink under the eraser out (`geometry/stroke_splitter.dart`): the stroke
is removed and its surviving fragments are added as new strokes (keeping the
original `createdAt`, so paint order is unchanged). One drag is one undoable
`InkEdit`; fragments cut and erased again within the drag cancel out.
Optionally only highlighter ink is erased. Both modes test against the ink as
rendered: its radius at each point depends on pressure, thinning and the pen's
easing (`StrokeHitTest.inkRadius`), not just the nominal width.

## Persistence

`package:sqlite3` (bundles SQLite via build hooks on every platform).
Schema migrations live in `AppDatabase._migrations` — append, never edit.
All writes go straight to SQLite; in-memory state is a cache.

## Library (`features/library/`)

- **Data.** Folders are a synced collection (`FolderRepository`, nested via `parentId`).
  Notebooks carry `folderId`, `favorite`, `trashedAt`, `coverStyle` and `editedAt`
  (content/title edits only, so organising never reorders "last edited"). Readers are
  defensive: a missing parent folder means "root", and folders caught in a parent cycle
  (possible after concurrent moves) are shown at the top level. Deleting a folder
  tombstones its subtree and trashes its notebooks. `NotebookDuplicator` deep-copies a
  notebook column-by-column (`RowCopier`), so columns added later are copied too.
- **State.** `LibraryController` (a `ChangeNotifier`) holds the section (library,
  favourites, trash), open folder and search query, reads the repositories on `reload()`
  and filters/sorts in memory (`LibraryQuery`). `LibraryActions` adds the dialogs and
  confirmations. Layout and sort are preferences (`AppPreferences`).
- **Shell.** ≥ 720 px wide: sidebar with sections, folder tree (all drop targets), sync
  status and settings; narrower: bottom navigation. Notebooks and folders drag with a
  mouse immediately and with touch after a long press (a long press released in place
  opens the context menu instead). Shortcuts: Ctrl+N, Ctrl+Shift+N, Ctrl+F, Delete, Esc.
- **Live covers.** `ThumbnailRenderer` draws the first page (paged) or the content nearest
  the origin (canvas) with the editor's own `PaperPainter` and `StrokeRenderer` into a
  `ui.Image`. `ThumbnailCache` keys previews by a cheap per-surface fingerprint
  (`SurfaceStats`: live stroke count + latest version, plus the page's paper and size), renders
  lazily in short time-boxed batches (one per event-loop turn, one notification per batch that
  changed a preview), keeps an LRU of images and is invalidated when an editor closes or sync brings
  strokes. Covers without ink show the coloured, patterned cover.

## Preferences

`AppPreferences` (in `AppServices.preferences`) is a `ChangeNotifier` over
`SettingsRepository`: theme mode and accent (the app rebuilds its `ThemeData` from them),
stylus-only, two-finger-tap undo, three-finger-tap redo, stylus side-button action
(`PenButtonAction.eraser|lasso|none`), library layout and sort. Getters always read
the store, so values written elsewhere are never stale.

## UI design system (`ui/`)

`AppTheme.light/dark({accent})` build a fidelity colour scheme from the accent with quiet
neutral surfaces, a tighter type scale and shared component themes
(`theme_components.dart`). Tokens: `Gaps`, `Radii`, `Palette` (`app_theme.dart`) and
`Motion`, `Breakpoints`, `Shadows`, `Accents` (`design_tokens.dart`).

Visual checks: `test/screenshots/` renders the library, settings and editor (toolbar, popovers) at phone, tablet and
desktop sizes in light and dark with real fonts. Run
`flutter test test/screenshots --dart-define=SCREENSHOTS=true` and look at
`app/build/screenshots/*.png`.

## Sync

See [`SYNC_PROTOCOL.md`](SYNC_PROTOCOL.md). Every synced table has
`updated_at / device_id / deleted / dirty`. A cycle pushes dirty rows, then
pulls the server's change feed from the last seen sequence number, applying
records with last-write-wins. Open screens subscribe to
`SyncController.remoteChanges` and reload only the affected surfaces.

## Known limitations / next steps

- SQLite runs on the UI isolate. Queries are small and indexed, but a
  background isolate (e.g. `sqlite_async`) would remove any jank risk.
- No lasso/selection yet. Pixel-erasing a long stroke rewrites it as new
  fragment records (simple and sync-safe, but more rows than a delta).
- Extreme zoom-out draws every visible stroke at full detail; a level-of-detail
  layer (e.g. rasterised chunk thumbnails) would cap that cost.
- Android: Flutter does not expose `MotionEvent` historical samples or
  front-buffered rendering; a platform-channel "low-latency ink" layer could
  shave further latency on Samsung tablets.
- The sync token is stored in the app's SQLite database; move it to secure
  storage before shipping.
- PDF backgrounds are rendered as whole-page images (no tiling), so very deep
  zoom on a PDF page is capped at ~2896 px page width; exported PDFs embed
  imported pages as images rather than copying their vector content.
- Blobs are never garbage-collected (neither on devices nor on the server).
- Page reorders made concurrently on two devices converge (LWW per page) but
  may interleave differently than either device intended.
