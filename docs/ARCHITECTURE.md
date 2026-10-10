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

Non-ink content are **elements** (`domain/surface_element.dart`, table
`elements`, synced as collection `elements`): a generic box (`rect` +
`rotation` about its centre), a stacking order `z` and a `type` with an opaque
`data` map. Today the only type is `text` (`TextData`: text, size, colour,
bold, italic, alignment); `image` (a blob hash in `data`) needs no schema
change. Unknown types are kept and synced but not drawn. Unlike strokes, an
element keeps its id when edited — the edit replaces the whole value.

## The sparse infinite canvas

The world plane is cut into fixed **512 × 512 chunks** (`domain/chunk_grid.dart`).
The same grid drives three things:

1. **Storage index** — table `stroke_chunks(surface_id, cx, cy, stroke_id)`
   (and `element_chunks` for elements). Only populated chunks have rows, so
   empty space costs nothing. A stroke is indexed only in the chunks its ink
   passes through (`domain/stroke_chunks.dart`: each segment, cut into short
   pieces, widened by the stroke's padding plus how far neighbouring samples
   stray — the outline smooths over them), never more than its bounding box;
   rows written before this used the whole box and stay valid. An element is
   indexed in every chunk its (rotated) bounds overlap (`ElementChunks`). The
   in-memory `ContentIndex` (one per kind, over a `SpatialIndex`) uses the
   same functions, so memory and storage agree.
2. **Lazy loading** — `SurfaceModel.ensureLoaded(visibleRect)` asks a
   `StrokeReader` for the populated chunks around the viewport that are not yet
   in memory — strokes and elements in one read (`StrokeQueries`) — and evicts
   far-away chunks once more than `maxLoadedChunks` are held (items hidden by a
   selection or text editor are kept). Canvases read through
   `BackgroundStrokeReader`: a worker isolate with its own read-only SQLite
   connection (WAL allows it next to the writer), so panning never waits for
   SQLite. `SurfaceLoader` keeps one read in flight per surface (the newest
   range wins), drops results after `reload()`, and filters strokes and
   elements removed while a read was running (erased, undone, moved by a
   selection), so a stale copy never comes back. `StrokeRepository` is the
   synchronous reader (pages, thumbnails, tests with in-memory databases).
3. **Render cache** — `ChunkPictureCache` records one `ui.Picture` per
   populated chunk, clipped to the chunk square (so strokes crossing chunk
   borders are never double-blended). Elements are drawn into the same
   pictures, above the chunk's ink (`elements/element_renderer.dart`). A stroke edit invalidates only the chunks
   it touches. Painting visits only populated chunks intersecting the screen.
4. **Level of detail** — when a chunk covers ≤ 256 device pixels,
   `CommittedInkPainter` draws it from a `ChunkRasterCache` image (32/64/128/256
   px, always at least screen resolution) instead of replaying its vectors.
   Rasters are made off the critical path (time-boxed batches, newest request
   first, `Picture.toImage`), invalidated by the same chunk stream, and kept in
   an LRU bounded by bytes. A frame never records more than a few uncached
   chunks; the rest fill in over the next frames. Measured (test
   `lod_render_test.dart`, 50 000 strokes, 1 632 visible chunks at 5 %): frame
   rasterisation 205 ms → 17 ms, cold first frame 700 ms → 2 ms.

Rendering is split into three layers, each behind a `RepaintBoundary`:
paper (repaints on pan/zoom), committed ink (repaints on pan/zoom or edits),
and live ink (repaints on every pointer move — the stroke being drawn and the
eraser cursor), so drawing never re-renders the committed ink.

**Navigation** (`ink/navigation/`, `features/editor/canvas/`): `KineticPan`
measures the viewport's own motion during a navigation gesture (fingers,
trackpad, middle-button drag) and `ViewportAnimator` glides on after a fling
(iOS-like deceleration; no glide after a pause or a pinch). The input controller
only reports begin / track / release. `ViewportAnimator` also animates zooms
(geometric scale, focal point fixed) and fits. Canvases add a zoom indicator
(shown while zooming; tap for 50 / 100 / 200 % or fit), a minimap of populated
chunks (from storage, via the reader) with the visible area (tap to glide, drag
to move), "fit content" (exact bounds from the outermost chunks), "back to
start", keyboard zoom (`+` `-` `0` Shift+1 Home) and a background: template and
paper colour (`notebooks.paper_color`). Continuous paged documents glide too.

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

Stroke outlines come from the in-house engine `ink/render/stroke_outline.dart`
(pressure-aware polygons with stabilised positions, hook trimming and exact
caps), smoothed with quadratic curves; paths are memoised per stroke. PDF export
flattens the same paths.

Resting the pen for 600 ms at the end of a stroke snaps it
(`input/hold_to_straighten.dart` + `shapes/shape_recognizer.dart`): open
strokes become a line (whose end then follows the pen) or an arrow, closed
ones a rectangle (axis-aligned or rotated), ellipse/circle, triangle or
polygon; scribbles stay freehand. Only the clean shape is committed.

The lasso, shape, text and laser tools are `PointerTool`s
(`ink/tools/`): `InkInputController` hands them the drawing pointer
(after palm rejection / navigation / stylus-eraser routing) instead of
making ink. `ContentTools` bundles them with their shared state for one
editor; `features/editor/tools/ContentLayer` shows that state over the
surface.

## Editing tools

- **Shapes** are ordinary strokes whose points trace a clean outline at
  constant pressure, with no stabiliser or tapers
  (`shapes/shape_builder.dart`), so they render, erase, select and sync
  like ink. The Shape tool drags out a box (Shift: square / 15° lines).
- **Lasso** (`selection/`): a stroke is selected when at least half of its
  *length* is inside the lasso polygon (segments are subdivided and weighted
  by length, so sampling density does not matter); an element when its
  centre (or most of its outline) is. A tap selects the topmost item.
  `SelectionController` hides the selection from the committed layer
  (`SurfaceModel.setHidden`, which only invalidates the affected chunks) and
  records it once into a picture; dragging, resizing (corners keep the
  aspect ratio, edges stretch) and rotating only change an `Affine` applied
  to that picture, so a drag never re-tessellates. On release the transform
  is applied once (`TransformItems`): strokes are replaced by transformed
  copies (new ids, same `createdAt`, width scaled), elements keep their id.
  Every gesture or menu action (delete, duplicate, cut, copy, paste,
  recolour) is one `InkEdit`. The selection frame keeps its rotation across
  gestures. The clipboard (`InkClipboard`) lives in `AppServices`, so paste
  works across pages and notebooks; paste goes to the screen centre
  (Ctrl+V, menu) or a long-press position.
- **Text** (`elements/text_edit_session.dart`): tapping with the Text tool
  creates or edits a box; double-tapping a box with the lasso edits it too.
  While editing, the element is hidden and a real `TextField` is laid out
  in world units and transformed by the viewport — `TextLayout` gives the
  field and the renderer the same complete (non-inheriting) style, so text
  wraps identically while edited and once committed. The whole session is
  one undoable edit (an emptied box is deleted).
- **Laser pointer**: a fading trail (`tools/laser.dart`) kept only in
  memory, animated by a ticker while visible.

`InkEdit` carries strokes and elements; merging cancels intermediate
values on both, so undo/redo and sync treat text and ink alike.

## Pens (`ink/pen/`, `ink/render/`)

A stroke's look = its `InkTool` (pen type) + its `StrokeStyle`:

- **`PenProfile`** (per tool, in code): outline smoothing, pressure easing,
  fountain nib variation, pencil texture, flat highlighter caps, taper length
  factor, plus the defaults and width range offered in the UI. Render
  constants here must stay stable.
- **`StrokeStyle`** (per stroke, stored in `strokes.style` and synced as
  `data.style`): opacity, thinning (pressure sensitivity), streamline
  (stabiliser) and start/end taper lengths. Missing → `StrokeStyle.defaultsFor`,
  which reproduces how v0.1 strokes looked. So a stroke renders identically on
  every device, whatever the local tool settings.

The **fountain** nib adjusts per-point pressure so the radius shrinks where the
pen travels along a 45° nib (`render/nib.dart`). The **pencil** fills its
outline with a procedurally generated, world-anchored grain texture
(`render/pencil_texture.dart`, an `ImageShader` tinted by a colour filter), so
it works inside cached chunk pictures and lines up across chunks.
**Highlighter** strokes are drawn before other ink in each chunk picture, and
the live highlighter stroke is painted on a layer beneath committed ink.

User customisation lives in `ToolSettings` (pen type, three presets + feel
settings per pen, eraser options, favourite colours), persisted as JSON in
the local `settings` table.

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

Visual checks: `test/screenshots/` renders the library and settings at phone, tablet and
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

- Canvas chunk reads run in a background isolate, but writes, page surfaces,
  thumbnails and other queries still run on the UI isolate (small and indexed).
- Far zoom-out of a huge canvas still loads every visible stroke into memory
  (LOD caps rendering cost, not memory); LOD rasters are not persisted, so they
  are rebuilt after reopening. Paged documents do not use LOD rasters yet.
- Pixel-erasing a long stroke, or moving a selection, rewrites strokes as
  new records (simple and sync-safe, but more rows than a delta).
- Text uses Roboto (with system fallbacks); a bundled font would make text
  boxes wrap identically on every device.
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
