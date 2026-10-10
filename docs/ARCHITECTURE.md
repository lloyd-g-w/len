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

Stroke outlines come from `perfect_freehand` (pressure-aware polygons), smoothed
with quadratic curves; paths are memoised per stroke.

## Persistence

`package:sqlite3` (bundles SQLite via build hooks on every platform).
Schema migrations live in `AppDatabase._migrations` — append, never edit.
All writes go straight to SQLite; in-memory state is a cache.

## Sync

See [`SYNC_PROTOCOL.md`](SYNC_PROTOCOL.md). Every synced table has
`updated_at / device_id / deleted / dirty`. A cycle pushes dirty rows, then
pulls the server's change feed from the last seen sequence number, applying
records with last-write-wins. Open screens subscribe to
`SyncController.remoteChanges` and reload only the affected surfaces.

## Known limitations / next steps

- SQLite runs on the UI isolate. Queries are small and indexed, but a
  background isolate (e.g. `sqlite_async`) would remove any jank risk.
- Stroke eraser only (no partial/pixel eraser yet); no lasso/selection.
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
