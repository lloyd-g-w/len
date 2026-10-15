# Len — Architecture

```
len/
├── app/        Flutter app (Windows, Linux, Android, Web)
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
`data` map: `text` (`domain/text/`: `TextData` — plain text, character
`spans`, paragraph styles and the box defaults, see *Text boxes* below)
or `image` (`ImageData`: blob hash, natural size, normalised crop). Elements
with `z < 0` are drawn beneath the ink (`SurfaceElement.belowInk`), the rest
above it (`ink/elements/element_order.dart` hands out stacking orders).
Unknown types are kept and synced but not drawn. Unlike strokes, an element
keeps its id when edited — the edit replaces the whole value.

## The sparse infinite canvas

The world plane is cut into fixed **512 × 512 chunks** (`domain/chunk_grid.dart`).
The same grid drives three things:

1. **Storage index** — table `stroke_chunks(surface_id, cx, cy, stroke_id)`
   (and `element_chunks` for elements). Only populated chunks have rows, so
   empty space costs nothing. A stroke is indexed only in the chunks its ink
   passes through (`domain/stroke_chunks.dart`: each segment, cut into short
   pieces, widened by the stroke's padding plus how far neighbouring samples
   stray — the outline smooths over them), never more than its bounding box
   (each row also carries the item's hash, see *Stored rasters*). An element is
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
   SQLite (natively; the web reads on the UI thread, see *Platforms*). `SurfaceLoader` keeps one read in flight per surface (the newest
   range wins), drops results after `reload()`, and filters strokes and
   elements removed while a read was running (erased, undone, moved by a
   selection), so a stale copy never comes back. `StrokeRepository` is the
   synchronous reader (pages, thumbnails, tests with in-memory databases).
3. **Render cache** — `ChunkPictureCache` records one `ui.Picture` per
   populated chunk, clipped to the chunk square (so strokes crossing chunk
   borders are never double-blended). Elements are drawn into the same
   pictures, layered by `render/content_painter.dart` (elements beneath the ink,
   highlighter, other ink, elements above), the same order every renderer —
   selections, thumbnails, exports — uses. A stroke edit invalidates only the chunks
   it touches. Painting visits only populated chunks intersecting the screen.
4. **Level of detail** — when a chunk covers ≤ 256 device pixels,
   `paintLod` (`render/lod_painting.dart`; canvases and, per page, paged
   documents) draws it from a `ChunkRasterCache` image (32/64/128/256
   px, always at least screen resolution) instead of replaying its vectors.
   Rasters are made off the critical path (`ChunkRasteriser`: time-boxed
   batches, newest request first, `Picture.toImage`), invalidated by the same
   chunk stream (`ChunkVersions` keeps content versions and strokes to draw
   over stale images), and kept in
   an LRU bounded by bytes. A chunk without a raster yet shows what the tile
   cache still holds of it (the closer zoom's images, scaled) or nothing for
   the frame or two until it is made; only chunks edited since their rasters
   were dropped (`needsVectors`: an erase must not linger, a stroke must show)
   are drawn from vectors, a few recorded per frame at most. Measured (test
   `lod_render_test.dart`, 50 000 strokes, 1 632 visible chunks at 5 %): frame
   rasterisation 205 ms → 17 ms, cold first frame 700 ms → 2 ms.
5. **Stored rasters** (canvases, natively): rasters of levels ≤ 128 are also
   kept across restarts (`StoredRasters`, a `RasterStore`: PNG files in the
   app's cache directory, `lod-<format>/`, LRU by file time within 96 MB;
   none on the web). They are named by content: each `stroke_chunks` /
   `element_chunks` row carries its item's hash (`ChunkDigest`: a stroke's
   id, an element's whole value), so storage sums a chunk's digest in one
   aggregate query (`StrokeReader.chunkDigests`) without loading it, and
   memory computes the same from the items (`SurfaceModel.digestOf`). Same
   digest, same content — so a raster found is right whatever was edited,
   undone, synced or emptied since, by any device, and nothing is ever
   invalidated: changed chunks get new names, old files age out. Zoomed out
   until a chunk covers ≤ 128 device pixels, `InkSurface` calls
   `SurfaceModel.showStored` instead of `ensureLoaded`: nothing is read;
   `ChunkRasterCache` lists the populated chunks from storage, reads their
   rasters and asks the model (`requestChunks`) only for chunks with none
   stored, rasterising and storing those once loaded (complete chunks only;
   none with hidden items; chunks with images only once their pictures were
   recorded with every bitmap decoded sharp enough, `ChunkPictureCache.isSettled`
   — an image's value names its blob by content hash, so the digest covers it).
   Files go through `StoredRasterIo`: reads queue and run 16 at a time,
   nearest the middle of the view first (sorted once a frame has asked for
   all it shows), and those panned out of view are dropped; writes (a GPU
   read-back on the raster thread, then PNG encoding on the engine's IO
   thread) wait until the view has been idle for 300 ms — no LOD paint, no
   new raster — and go one at a time (at most 32 MB of images wait; all go
   when the view closes).
   A pen, eraser or lasso touching down loads what the view shows
   (`loadVisible`), and zooming in past 128 px loads as before while the
   stored rasters stand in. Views of one surface (split view) register
   separately (`SurfaceViews`), so an overview pane never loads for a
   close-up pane or the other way round. *Select all* loads its area through a
   one-off view, forgotten once loaded (the selection keeps what it holds). Reopening a 40 000-stroke canvas at
   10 %: 442 chunks drawn from 442 stored rasters, no stroke loaded, versus
   9 373 strokes loaded and 442 chunks rasterised (see INK_LAB). Changing
   how content is drawn means bumping `StoredRasters.format`.

Rendering is split into three layers, each behind a `RepaintBoundary`:
paper (repaints on pan/zoom), committed ink (repaints on pan/zoom or edits),
and live ink (repaints on every pointer move — the stroke being drawn and the
eraser cursor), so drawing never re-renders the committed ink.

### Committed ink: tiles (`ink/render/tiles/`)

Impeller has no raster cache: a `RepaintBoundary` only saves rebuilding the
layer, every frame that composites it still re-tessellates and fills every
outline in it. On the tablet a page dense with handwriting cost 45–60 ms of
raster time per frame — every frame of writing on it, pen-up included —
and a full screen of canvas ink 55–125 ms. So committed ink is drawn from
**tiles**: `InkTileCache` (one per surface per view) splits the screen into
512 × 512 *device-pixel* tiles of a `TileSpace` (zoom `k` = device px per
world unit, plus the sub-pixel phase of the view's origin, so every tile
sits on whole device pixels and shows exactly what the vectors would) and
renders each with `Picture.toImage` from the chunk pictures. A settled frame
draws a few dozen images, however much ink is on screen.

- **Pipeline**: `CommittedInkPainter` (canvas) and `DocumentInkPainter`
  (pages, clipped to the page) call `paintTiled`: tile images where they
  exist; for the rest (`VectorFallback`) the chunk pictures as before,
  clipped to the missing tiles. Renders are queued (on screen first, then a
  ring one tile around it), at most two in flight (edits: all at once),
  recordings time-boxed to 4 ms per batch, and run after the frame that
  asked for them; the painter repaints when they land (`InkTileCache` /
  `DocumentSurfaces.rendered`). Requests the view has moved away from are
  dropped.
- **Pen-up** (`SurfaceChange.appended`): `SurfaceModel.addStroke` reports a
  new stroke that lies over everything in its chunks (no highlighter, no
  element above) as an *append*. Tiles keep their images; the stroke is
  drawn as a vector over the tiles it touches (*overlay*) in the very next
  frame, and each such tile is re-rendered as *old image + stroke* off the
  frame. So committed ink never vanishes or flickers at pen-up, and a
  pen-up never re-records a chunk picture or replays a page of ink.
- **Highlighter pen-up** (`SurfaceChange.underlaid`): a highlighter
  paints beneath the pen ink, so it is no append; the tiles it crosses
  keep their images, stale, and draw it as a vector *beneath* them — as
  the live highlighter was drawn, beneath the committed ink — until they
  are re-rendered (urgently, from the chunk pictures). Before, a highlight
  over more than two tiles vanished for the frame or two until they were.
  Zoomed out far, the level-of-detail rasters likewise keep their images
  and draw new highlights beneath them (new pen strokes over them) instead
  of a frame of vectors (`test/pen_up_frames_test.dart` checks every frame
  around pen-up, pen and highlighter, on a canvas at 50–200 % and 1×/2×,
  and on a continuous notebook's page from tiles and from rasters).
- **Loads** (`SurfaceChange.loaded`: stored content arriving) keep the
  images of the tiles they touch as stale stand-ins until re-rendered (that
  content was not on screen yet), so a loading canvas never drops to
  vectors.
- **Other edits** (erase, undo, lasso) touch only the tiles under the edited
  items' bounds (`SurfaceChange.areas`, not whole chunks). Up to two tiles
  are dropped and drawn from vectors for a frame or two (an eraser stroke
  shows at once); larger edits (undoing a lasso move) keep the old images
  until the new ones, all rendered at once, replace them together — a
  frame or two late, but never frames of vectors over the whole screen and
  never half done.
- **Idle caches**: a cache not painted for 500 ms (its view zoomed out to
  level-of-detail images, say) renders nothing on edits; appended strokes
  wait as overlays until it is painted again, so it never takes raster
  time from what is on screen.
- **Pan**: panning keeps the space and its tiles, by fractions of a pixel
  too: the view is aligned to the tiles (`TileView.alignedTo`, committed
  ink off by under half a device pixel) rather than every tile re-rendered
  when a scroll stops; the ring renders while panning.
- **Zoom**: the current tiles are drawn transformed (`FilterQuality.medium`)
  while the gesture lasts, rendering only those missing on screen (and the
  ring when zooming out); zooming out more than 1.5× from the tiles adopts
  the new zoom at once. After 150 ms still the new zoom is adopted and
  rendered; old tiles (never stale ones) stand in wherever they exist.
  Once a cache has zoomed, the parts they do not cover (the rim a fast
  zoom-out exposes) stay empty for the frame or two until their tiles
  render, rather than being drawn from vectors every frame meanwhile —
  which cost as much as rendering them, per frame. Tiles dropped by an
  edit (`InkTile.edited`) and a cache's first show still draw vectors.
- **Memory**: tile images live in one `TilePool` (LRU by bytes, 160 MB =
  160 tiles of 1 MB) shared by every surface and view; evicted tiles are
  re-rendered when needed. Beyond 256 tiles known per cache, those without
  an image or pending work are forgotten.
- **Pages ahead**: paged documents load (`DocumentController`) and render
  (`InkTileCache.prefetch`) the pages within half a screen of the view, so
  a page scrolls in complete and without vector frames.
- **Split view**: page models are shared between the panes of a notebook
  (`PageModels`), tile caches are not — each view has its own zoom and its
  own `PageSurface` (chunk pictures + tiles), all listening to the shared
  model's `changes`.
- **Level of detail**: zoomed out far (canvas, and pages: each
  `PageSurface` has its own `ChunkRasterCache`, 4 MB at most),
  `ChunkRasterCache` images are drawn instead (see *Level of detail* above); on an
  append they too keep their (stale) images with the new strokes drawn
  over them until re-rasterised. Crossing into LOD, the tiles stand in
  until the rasters are made (`InkTileCache.paintStandIn`).

Two more things keep pen-up and first show off the frame:

- **Write-behind** (`SurfaceModel(writeBehind: true)`, editors only): stroke
  inserts and deletes reach SQLite in a post-frame callback after the frame
  that shows them (`len.persistStrokes`), not inside the pointer-up
  handler. Reads, `reload`, `dispose` and `SurfaceModel.flushAll()`
  (exports, page copies and deletions) flush first.
- **Outlines off the frame** (`OutlinePreparer`, `platform/
  outline_preparer*`): strokes read from storage get their outlines built
  before the model adds them — on up to three worker isolates
  (`BackgroundOutlines`, as plain command lists turned into `Path`s on the
  UI isolate) and, between frames in steps of ≤ 3 ms, on the UI isolate
  too (the workers run on the slower cores), except while a pointer is
  down or was lifted < 400 ms ago. The model adds them a chunk's worth at
  a time as they arrive, the chunks nearest the view first
  (`len.insertLoaded`); a page of 2 000 strokes no longer stalls the frame
  that first shows it for 1–3 s. Tests build them inline
  (`InlineOutlinePreparer`); the web, without isolates, on the UI thread
  in slices of ≤ 8 ms with a turn of the event loop between them
  (`SlicedOutlinePreparer`): opening a 4 000-stroke notebook no longer
  blocks the tab for 0.4–0.6 s per page (`tool/web_explore.py` fails a
  WebAssembly build with a task over 500 ms once started).
- **Reads in blocks** (`SurfaceLoader`): a range of more than 36 chunks (a
  canvas seen from afar) is read in 4 × 4-chunk blocks, middle first, so
  the first ink shows within a second rather than after reading (and
  copying between isolates) tens of thousands of strokes. Chunks whose
  outlines are being built count as loaded for the next read.
- **Previews** (`ThumbnailRenderer`): ink thinner than 1.5 px in the
  preview is drawn as plain lines along its points
  (`StrokeRenderer.drawSketch`), without building outlines. Page thumbnails
  (`ThumbnailCache`: page overview, go to page) do the same below 2.5 px
  (the regular pens) and are rasterised once at the size shown (48 MB LRU),
  so scrolling the overview draws images instead of every page's outlines.
  A page waiting to be recorded is dropped from the queue once no
  thumbnail shows it (scrolled past). Each overview tile's ⋯ is a
  `MenuIconButton(staggered: true)`: the glyph first (it opens the menu
  too), the IconButton with its tooltip completed by `StaggeredBuild` (a
  few a frame, not while the grid scrolls).

Measuring: `test/perf/ink_render_perf_test.dart` replays the scenarios
headlessly and counts the work (see docs/INK_LAB.md); profile builds with
`--dart-define=LEN_PERF=true` log frame and
pen-up latency summaries (`PerfProbe`, see docs/INK_LAB.md, *Rendering
performance*); timeline markers `len.renderTile`, `len.commitStroke`,
`len.persistStrokes`, `len.recordChunk`, `len.handwritingCluster`,
`len.outlineStep`, `len.insertLoaded`, `len.thumbnail` show up in Perfetto /
DevTools.

**Navigation** (`ink/navigation/`, `features/editor/canvas/`): `KineticPan`
measures the viewport's own motion during a navigation gesture (fingers,
trackpad, middle-button drag) and `ViewportAnimator` glides on after a fling
(iOS-like deceleration; no glide after a pause or a pinch), after settling and
spring back (see *Navigation feel* under *Input*). The input controller
only reports begin / track / release. `ViewportAnimator` also animates zooms
(geometric scale, focal point fixed) and fits. Canvases add a zoom indicator
(shown while zooming; tap for 50 / 100 / 200 %, "fit content" (exact
bounds from the outermost chunks) or "back to start": their only menu), keyboard zoom and arrows (`+` `-` `0` Shift+1 Home ← ↑ → ↓) and a background: template and
paper colour (`notebooks.paper_color`). Paged documents glide too (single-page flow
only when zoomed in; at the whole page it settles back or turns the page).

**Minimap** (`canvas/canvas_minimap.dart`, a layer of `EditorLayers`; "⋯" → View →
*Minimap*, Shift+M; local setting `canvas_minimap`): a `FloatingPanel`
window onto the paper in the bottom-right corner, clear of the chrome and the audio strip
(`ChromeLayout.covered`), shaped like the free area (1:1 to 16:10; 176 dp, 120 on phones).
Content comes from storage — `StrokeReader.chunkDensity` (items per populated chunk, in the
background reader), re-read 500 ms after a non-load `SurfaceChange` (the model flushed
first) — and `MinimapContent` merges the chunks into at most 48 × 48 soft blocks, shaded by
density, so painting costs the same on any canvas; per frame only the painter runs
(blocks, origin cross, the view's frame in the accent for the paper's brightness).
`MinimapFrame` picks the world area shown: content ∪ the visible area
(`CanvasNavigation.visibleArea`, the screen minus the chrome) with 12 % room, held still
while the view moves inside it and refitted (gliding, `Motion.medium`) when the view leaves
it or it grows 1.8× larger than needed. Input (touch, pen, mouse): a tap glides there
(`CanvasNavigation.centreOn`); a drag moves the view live, the map frozen under the finger
(grabbing the frame keeps the grabbed point under it, elsewhere centres the view there);
two fingers pan and pinch (`zoomBy`); a mouse wheel zooms in steps (`zoomStep`, claimed
through the pointer-signal resolver); long-press / right-click opens its menu (*Hide minimap*). It fades out
(`ChromeFade`) while the pen draws (back 1.2 s after it lifts, not between strokes), on an
empty canvas and in focus mode. Paged documents have none (the page overview and navigator
serve them).

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
visible pages (plus a few recently seen ones), and loads just their visible
chunks; a page's `SurfaceModel` outlives its view while undo can reach it
(`PageModels`). It also provides **notebook-wide undo**: the
most recently edited page is undone first, back at most 200 steps on at most
24 pages (older steps, and the models only they kept, are dropped) (a step may span pages: see
*Selections across pages* under *Editing tools*). Painting mirrors `InkSurface`
(paper → committed ink → live ink layers) across every visible page.

Page management (`PageActions`, `DocumentCommands`, `PageOverview`): insert,
duplicate (copies stroke rows wholesale via `SurfaceCopier`, so stroke
columns added later are copied too), delete (with an Undo snack bar that
re-saves the page's strokes; the overview's selection goes through
`DocumentCommands.deleteMany` → `PageActions.deleteAll`, one step with one Undo
that restores every page in place — at least one page always remains), reorder (fractional sort keys, `PageOrder`;
the list is renumbered only when a gap is exhausted; inserting finds the page to follow by
id; in the overview by drag, or Ctrl+arrows on a focused tile — a place along, a row across,
one undo step each, announced, focus following the page: `overview/page_moves.dart`), bookmarks, templates, and moving or copying pages to another notebook
(`PageTransfer`, one transaction; its undo never deletes work done since:
changed copies stay, a notebook made for the pages goes to the Trash, and redo
reuses the copies still there).
Every page change goes through `PageEdits` (`document/page_edits.dart`), which
records a `PageEdit` (undo / redo callbacks) as a step of the notebook-wide
history in `PageModels`: Ctrl+Z takes back a template, a move, bookmarks, added
or deleted pages in order with ink. Snack bars' Undo calls
`PageModels.undoEdit`, which also takes back an older step on its own.

## Editor screen (`features/editor/`)

- **`EditorSession`** owns the engine side of one open notebook: `ToolSettings`, live ink,
  `InkInputController` + `CanvasGestures`, `ContentTools`, undo, and either the canvas
  `SurfaceModel` + viewport or the `DocumentController` + `DocumentCommands`.
- **`EditorScreen`** is the editor's composition root: it owns the parts and wires them,
  each of which lives in its own file — `EditorSession` (engine side: tools, input,
  content tools, undo, canvas or document), `EditorLayers` (`editor_layers.dart`: what is
  stacked over the surface, bottom to top — a feature drawing over the surface adds its
  layer there), `EditorChromeHost` (`editor_chrome_host.dart`: toolbar, top bar, menus and
  page navigator wired to `EditorScreenCommands`; `ToolbarMeasure` and the chrome
  layout), `EditorLifecycle` (`editor_lifecycle.dart`: app hidden, view memory, closing
  after a remote deletion, touch + sync after edits), `editor_commands.dart` (rename,
  canvas background), `editorScreenShortcuts` and `canvasMenuAt`. It composes
  `EditorCanvas` (surface, "Add page" footer, content layer) with `EditorChrome`
  (`chrome/`): `EditorTopBar` (fixed clusters: navigation — back, ▦ pages, the title,
  start-aligned, tap to rename, with the folder as a quiet subtitle — then the tools when
  they are docked inside the bar, then actions — the 🎙▾ audio split button, undo/redo and
  "⋯" `EditorMoreMenu`; phones keep back, the title, undo/redo and ⋯), the toolbar
  (inside the bar, attached under it, the phone's bottom row, or floating in `ToolbarSlot`
  by a grip; see *Toolbar*), `PageNavigator`, `GestureHud` (counts
  repeats: "Undo ×3"), `TipBanner` and, in focus mode, only a `FocusHandle`.
  The `3 / 12` page indicator peeks on every screen (`chrome/peeking.dart`):
  it shows when the notebook opens and while the document viewport moves,
  fades after 1.5 s (stays while touched or hovered), lets touches through
  and excludes itself from accessibility when hidden, and takes no room in
  `ChromeLayout.covered`. Tap to go to a page; long-press for the overview.
  `ChromeLayout` says how much of each screen edge
  the chrome covers; the document pads its scroll bounds by it (in screen pixels, so it
  is re-applied on zoom), and the selection / text menus and the canvas's zoom pill and
  fit button (`CanvasView`) avoid it (passed down as `MediaQuery.padding` / insets).
  On canvases the "⋯" menu also holds the background (template and paper colour); the
  navigation commands live in the zoom pill. Chrome menus are
  `ChromeMenuAnchor`s: they report to a `CanvasGuard`, which blocks the surface while one is
  open (the tap that closes a menu never draws) and closes them on Escape (a menu opened
  by tap leaves keyboard focus on the editor, where Escape would otherwise clear the
  selection instead).
- **Hints** (shown sparingly, never blocking): an empty infinite canvas shows a quiet
  "Draw anywhere" note with how to move around (`canvas/canvas_empty_hint.dart`; gone at
  the first edit). `TipsController` (`chrome/editor_tips.dart`) teaches each input
  without an affordance once per device, on a budget (R9-1): at most one tip per editor
  (notebook opening), ≥ 10 min apart (`SettingsRepository.lastTipAt`), none within 60 s
  of a snack bar anywhere in the app (`MessageQueue.activity`: a `MessageActivity` keeps
  when one was last up, so a notebook opened after a snack bar elsewhere waits too), and
  only once the pen has rested 2 s (`LiveInk`: pens and shapes; `LassoPath`: a lasso loop
  being drawn). A tip never replaces another (a later trigger is dropped and waits for its next
  one); several due at once go by priority (`EditorTip` order): the side button (a stylus
  contact, from the second opening on: the first has the "Stylus detected" message;
  phrased for `PenButtonAction`), hold to snap (a hand-drawn line or shape,
  `HoldToStraighten.wouldSnap` via `InkEvents.shapeDrawn`; writing on puts it off to the
  next shape), the lasso (when picked; never over a selection, and a selection is the
  tip done), scribble to erase (the eraser picked again). Each only while its setting
  is on. `TipBanner` (`chrome/tip_banner.dart`) sits at the bottom above the toolbar,
  ignores all pointers (strokes go to the page), fades while the pen is down and hides
  behind snack bars; its 10 s stop meanwhile, and it counts as seen
  (`SettingsRepository.seenTips`) only after 3 s on screen. The gesture HUD names
  multi-finger taps when they happen (no tip for them).
- **Tabs** (`tabs/`): `OpenNotebooks` (in `AppServices`) holds up to 8 open notebooks,
  the active one, and each tab's `EditorViewState` (page, zoom, pan). The library opens
  notebooks through `openNotebook()`, which pushes one `EditorWorkspace` route; it shows
  the active tab's `EditorScreen` (keyed by notebook), which saves its view on dispose
  and restores it on creation. Closing the last tab leaves the workspace.
  `WorkspaceMemory` (`tabs/workspace_memory.dart`, in `AppServices`) keeps the tabs,
  the active one and the split view in the settings (`workspace`) while the workspace
  is shown, and the notebooks opened lately (`recent_notebooks`, the library's Recent
  row); the library restores the workspace at launch, leaving it clears it.
  The workspace route is a `NotebookOpenRoute` (`tabs/notebook_open_route.dart`): opened from
  a library cover (`NotebookOpenOrigin` from the library's `CoverLocator`), the cover's rect
  grows to the screen with easing corners, fades into the paper colour and the editor (scaled
  and clipped to the flight, never relaid out) fades in; back (and predictive back) reverses
  into the cover's current rect, or fades if it is gone. Without a cover (search, new, import)
  it fades and scales in; with reduced motion it only fades. The library does not move.
- **Split view** (`split/`; tablets in landscape and desktops: `SplitView.fits`, ≥ 900 px
  wide and ≥ 560 px on the short side — never phones or portrait tablets): a second pane
  shows another open tab or the active notebook again (two places in one notebook).
  `OpenNotebooks.splitId` / `splitFraction` / `splitView` hold it (memory,
  like tabs). Opened from "⋯" → *Open in split view* (`SplitViewMenu`: this notebook
  or another tab; while split: *Swap panes*, *Close split
  view*) or a tab's menu (right click / long press → *Open in split view*). `SplitView`
  lays out the panes in a `Stack` whose first child keeps its place in every layout, so
  opening or closing the split never rebuilds the first editor; a 12 px divider resizes
  (drag, ← / → when focused, double tap: halves; panes ≥ 320 px). Each pane is a full
  `EditorScreen` with its own `EditorSession` (viewport, tools, chrome); the
  second has no tab strip (an empty strip-coloured band in its place while the first
  shows one, via `SplitView.primaryWidthOf`, so the bars line up), its back button closes it, Ctrl+W closes it, it keeps its
  view in `OpenNotebooks.splitView` only, and it has its own `ScaffoldMessenger`
  (messages show in the pane they belong to). When the screen gets too small for two
  (a tablet turned to portrait) the second pane is **parked**, not closed: it stays
  in the tree offstage (`SplitView`'s `_Parked`: `Offstage` + `ExcludeFocus` +
  `TickerMode`; `SplitView.parkedOf`), so its editor, undo history and a running
  recording live on; it takes no files and is no drop target, and shows again in
  landscape. `SplitController` (owned by the workspace; editors `attach` a
  `SplitPane`) coordinates them:
  - **Drag between panes (copy)**: `LassoTool.dragOut` (a `SelectionDragOut`) reports
    a selection being moved; over the other pane, that pane is outlined with *Drop to
    copy here* and a half-transparent preview of the copy at its zoom; dropped there,
    the source cancels its move and the target pastes a copy
    (`SelectionController.pasteItems`) centred where the selection's centre was, on the
    page under it, selected with the lasso (one undo step in the target).
  - **Two views of one notebook** need no mirroring: they share the notebook's models
    (see *Shared notebooks* below), so an edit, undo or redo in one shows in the other
    at once, and both undo one history (nothing erased in one comes back through the
    other's undo). While one pane has a selection or edits a text box, those items are
    hidden in the other view too (hiding is per model).
  - **Linked tools** (always): `ToolSettings.adopt` copies tool, quick colours and
    widths, eraser, shape and text defaults from the pane that changed them.
  - **Focus mode** in a pane shows that pane alone (`SplitView.solo`; the other stays
    alive offstage); when that editor goes (tab closed or switched, split closed),
    the other pane shows again.
  - **Views across layout changes**: before tabs change, `OpenNotebooks.captureViews`
    (set by the controller) records where both panes look, so swapping panes keeps each
    notebook's view, and closing the active tab next to the split tab moves that notebook
    into the first pane where it was. The tab limit never closes the split tab. Incoming
    files go to the pane that last had keyboard focus.
  - **Deleted on another device**: an editor closes only the dialogs, sheets and pages
    it opened (`RouteOwners`, `ui/route_owners.dart`: an observer on the app's
    navigator that records which editor — the last one touched or focused — pushed
    each route), never the other pane's; the second pane's message shows in the first
    (`SplitController.messageOther`), since its own messenger goes with it.
- **Shared notebooks** (`shared/`): `SharedNotebooks` (`AppServices.sharedNotebooks`)
  holds one ref-counted `SharedNotebook` per notebook open in any editor; every editor
  of a notebook (a tab and the second pane, or both panes) `acquire`s the same one and
  the last to close disposes it. It holds the notebook (`update` renames or changes
  paper in every editor and the tab), its `NotebookAudio` (one recorder and player, one
  recordings list), the PDF caches (`PdfBackgroundCache`, `PdfPageInfoCache`), the
  canvas's `SurfaceModel`, or the pages' `PageModels` (`document/page_models.dart`:
  ref-counted page models plus the notebook-wide undo order; each view's
  `DocumentSurfaces` acquires the pages it shows and keeps its own render caches; a
  model goes once no view holds it and undo can't reach it). Page list changes in one
  view reload the others (`attachDocument`). It follows remote changes once for all
  its editors (notebook record, page lists, surfaces, PDFs) and sets `gone` when the
  notebook is deleted or trashed elsewhere. One microphone: a notebook can't start
  recording while another records ("Already recording in …").
- **Focus mode** (`EditorScreen._setFocus`; "⋯" → View → *Focus mode*, F11, Ctrl/⌘+.) hides
  all chrome (`ChromeLayout.focus`) but the `FocusHandle`, and goes immersive / full
  screen (`platform/fullscreen*`: the browser's fullscreen API on the web; Android hides
  the system bars; Linux and Windows windows go full screen through the runners'
  `len/window` channel). It is also the way to present: **F5** enters it with the laser
  pointer as the tool (put back on leaving). Space / Shift+Space turn pages in it, next
  to the usual ← / → / Page Up / Page Down. Esc, back, F11 or F5 leave it. **External
  displays**: Android mirrors the screen by default; a separate audience window
  (Android `Presentation` API, desktop multi-window) is out of scope — Flutter's
  multi-window API is not stable yet.
- **Zoom window** (`zoom/`; "⋯" → View → *Zoom window*, `M`): GoodNotes-style writing
  through a magnifier. A `ZoomFrame` (surface id, origin, scale) marks a rectangle on a page
  (or the canvas) with the box's aspect; `ZoomBox`, docked above the bottom chrome
  (`ChromeLayout.zoomBox`, counted in `covered` so the page scrolls clear of it), shows it
  magnified with the page's paper and ink. Pointers in the box go to the window's own
  `InkInputController` over `ZoomBoxViewport` (a `ViewportController` the window sets; finger
  pans and pinches move or size the frame instead), so ink is smoothed, pressure-shaped,
  live and undoable exactly as on the page; the pen keeps its page width. `ZoomRules` is the
  pure geometry: the start scale (three ruled lines fill the box), the advance zone (the
  frame's right 30 %: ink lifted there moves the frame on after `ZoomWindow.pause`, at once
  past 90 %, leaving the ink a quarter in), the wrap to the line start a whole ruled line
  (or ink height) down, and past a page's bottom on to the next page (`DocumentCommands
  .addPageAfter` adds one after the last). `ZoomHost` (`DocumentZoomHost`, `CanvasZoomHost`)
  is what the window needs of the editor: bounds, paper and margin, models (held with
  `DocumentSurfaces.acquireModel`), activating the frame's page (its live ink shows there),
  and `reveal` so the main view follows the frame. `ZoomFrameOverlay` draws the frame on the
  page (an accent hairline over a 5 % wash, the zone washed deeper, a tab on the top edge at
  the left, a square at the corner): drag the tab to move it (lines then start there), the
  square to size it. Only the two handles take pointers (their targets mostly outside the
  frame), so the pen writes inside the frame on the page as anywhere. While an advance waits
  for the pen to rest, `ZoomWindow.armed` is set and the box's zone band (`ZoneBand`,
  `ZoneBandPainter`: 10 % of the paper's pattern colour at rest) deepens over the pause, so the
  glide that follows is expected; the pen coming back disarms it. The box's top edge (`ZoomBoxGrip`, two ticks in the
  paper's pattern colour; `BoxHeightDrag`) sizes the box with a finger or the mouse (a stylus
  writes up to the edge): `ZoomWindow.boxHeight`, kept by `ZoomBox.heightFor` to at least
  `least` and clear of `pageRoom` of the page. The rail (`ZoomBoxRail`: ✕ and ⋯ at the top, ↵ at
  the bottom) opens the box's own menu (`zoom_box_menu.dart`): *Left-handed* docks the box
  under the top chrome (`AppPreferences.zoomBoxAtTop`, `ChromeLayout.zoomBoxAtTop`, counted in
  `covered.top`; the grip moves to its bottom edge) so a left arm writing in it hides none of
  the page and the frame (GoodNotes' answer for left-handers; the advance stays at the right,
  as writing runs left to right whichever hand holds the pen), and *Automatic height* undoes a
  dragged one. Palm: a stylus in the box tells the page's input
  (`InkInputController.stylusElsewhere`: a finger drawing or panning there stops, new ones
  are ignored as between strokes) and `ZoomWindow.blocksPage` absorbs new page touches for
  `palmQuiet` after the pen lifts. Each notebook keeps its window (`ZoomWindowState`: the frame
  while open, the chosen box height) in the settings (`zoom_window.<id>`, written with
  `editor_view.<id>`); it reopens there (`ZoomWindow.restore`: the frame kept on its page and
  lines starting at it; a page since deleted opens afresh). The second pane neither keeps nor
  restores it.
- **Opening where you left off**: `EditorViewState` (`tabs/open_notebooks.dart`: zoom,
  pan, current page, viewport size, page fit) is kept per tab in memory and per notebook
  in the settings (`editor_view.<id>`, written on dispose and when the app is hidden).
  Restored only at the same viewport size; otherwise a paged notebook re-fits its
  current page, and a canvas keeps the same world point in the middle. A canvas without
  a saved view opens centred on its content (`CanvasNavigation.open`: `contentBounds`,
  fitted into the area the chrome leaves free, at most 100 %; an empty canvas stays at
  the origin), after the chrome's insets are known so nothing starts under the toolbar.
- **Page zoom** (`document/page_fit.dart`, "⋯" → View, Shift+1 fit page, Shift+2
  fit width, `0` automatic): `PageFit.width` fills the width, `PageFit.page` shows the
  whole page, `PageFit.auto` fits the width but at most 1.4× and so that ≥ 55 % of the
  page's height shows (landscape tablets and desktops see most of a page instead of a
  third); single-page flow always shows whole pages. The fit applies on open and on page
  jumps; a fitted view that the user hasn't moved is re-fitted when the chrome or the
  screen size changes. Saved per notebook in `EditorViewState.fit`.
- **Page navigation**: `DocumentController.scrollToPage` animates the viewport with
  `DocumentScroller` (centre point glides, zoom eases; jumps longer than two screens
  start near the target); it stops an inertial glide first (`beforeJump`). Single-page
  flow fits the whole page and slides it in. At the whole-page zoom it turns pages by
  gesture (`document/single_page_turns.dart`): a one-finger swipe or a trackpad swipe
  (`PageSwipe`: a flick ≥ 32 px at ≥ 300 px/s, or a drag across 30 % of the width,
  mostly sideways; event timestamps), or the wheel (one 50 px step turns one page,
  then it rests 300 ms so one flick turns one page). Zoomed in, they pan.
- **Shortcuts** (`editor_shortcuts.dart`): Ctrl/⌘+Z, Ctrl/⌘+Shift+Z, Ctrl+Y; tools
  P / H / E / L / S / T / K; 1–5 quick colours, [ / ] width; F11 or Ctrl/⌘+. focus mode; F5 focus mode with the laser;
  M zoom window; Ctrl/⌘+E export, Ctrl/⌘+G go to page (paged), Ctrl+F search;
  Ctrl+Tab / Ctrl+Shift+Tab / Ctrl/⌘+W tabs. Canvases (`canvas/canvas_shortcuts.dart`):
  arrows move around (15 % of the screen, gliding), `+` / `-` (also with Ctrl/⌘),
  `0` 100 %, Shift+1 fit content, **Home back to start**, Shift+M minimap. Paged notebooks
  (`document/document_shortcuts.dart`): ← / → and Page Up / Down turn pages, ↑ / ↓
  scroll (turn pages in single-page flow), `+` / `-` zoom 1.25× steps, **Home first
  page**, End last page. Single keys are ignored while text is edited.

## Templates (`domain/templates/`, `domain/paper_pattern.dart`)

- **Registry.** `PaperStyle` (`templates/paper_style.dart`) is the registry of built-in
  templates: stored name (id), label, `TemplateCategory` (Paper, Writing, Planners; My
  templates for the user's own), pitch, search keywords, whether it tiles an infinite canvas
  (`canvas`) and, for planners, the `PlannerPeriod` one page covers. `PaperStyle.image` stands
  for a user's image template. Built-ins: blank, dotted; narrow / college / wide ruled, Cornell,
  to-do list, meeting notes; daily planner, weekly planner, monthly calendar, year overview; small / large
  grid, graph paper (1 mm / 5 mm / 1 cm), engineering (5 per inch, bold inches, header),
  isometric, music staff, storyboard.
- **Paper.** A page's template is a `Paper` (`templates/paper.dart`): the style plus what it
  needs — for a planner page the `date` (the first day of its period, UTC) and its
  `PlannerCalendar` (week start, language), or the `image` blob of a user's template — and its
  **look** (`templates/paper_look.dart`, `PaperLook`): spacing in mm (for styles with a
  `PitchKind`: lines, grid, dots, staff; `Paper.pitch` is the effective pitch), line weight and
  dot size (× default), pattern colour (null = the paper colour's) and opacity, the ruled margin
  line on/off and a header area (`PaperStyle.hasHeader`: a band of 9 % of the page ruled off at
  the top, the pattern below it). Stored as `pages.paper` (style name) + `pages.paper_data`
  (JSON, `Paper.toData`, look under `look`), synced as `paper` + `paperData`. Equality includes
  calendar and look; planner links match with `Paper.sameSheet` (any look), and `sibling` /
  `next` keep the look. A notebook's `paper` (default for new pages, canvas background) is a
  `Paper` without parameters, look included (`notebooks.paper` + `paper_data`). `Paper.next` is
  the following period: "add page" after a planner page continues the dates (in its calendar).
- **Paper colour.** `PaperColor` is a preset (white, cream, grey, dark) or `PaperColor.custom`
  (stored `#RRGGBB`), whose pattern and text colours are derived from its luminance.
- **Geometry ("painter").** `PaperPattern.of(paper, area, page:, minPitch:)` builds a
  template's pieces for an area, independent of the target: lines with weights (`fine`,
  `normal`, `heavy`, `margin`), dots, `PatternLabel`s (printed text: dates, headings), tinted
  `PatternFill`s and planner `PatternLink`s. Layouts are extensions on `PatternBuilder`
  (`patterns_basic.dart`, `patterns_writing.dart`, `patterns_planner.dart`); page layouts scale
  with the page (margins, cells) and adapt to landscape (week grid 4 × 2, storyboard 3 columns).
  Repeating detail closer than `minPitch` (too dense at the current zoom) is left out while
  structure stays, so graph paper gains its millimetre lines as you zoom in.
- **Drawing.** `PaperRenderer` (`ink/render/paper_painter.dart`) draws a pattern on screen, in
  thumbnails, miniatures and PNG export, with the look's colour, opacity, line weight and dot
  size (lines are device-pixel hairlines × weight) — vector lines and text in the UI font (laid-out
  paragraphs cached), crisp at any zoom; image templates are drawn over the page from a
  `PaperImageLookup` (the shared `ElementImages` cache; the editor repaints when one is
  decoded). `PdfTemplateWriter` writes the same pattern into exported PDFs as vectors, labels
  in the embedded bundled Inter (shared with text boxes via `PdfTextWriter.font`; subset, with
  ToUnicode, covering Latin, Greek and Cyrillic); image templates are embedded like PDF
  backgrounds.
- **Planners** (`templates/planner_dates.dart`, `planner_calendar.dart`, `planner_labels.dart`,
  `planner_plan.dart`). `PlannerDates`: pure UTC calendar arithmetic — weeks from Monday or
  Sunday, week numbers (Monday weeks ISO 8601; Sunday weeks the US rule: the week holding
  1 January is week 1, so late-December days can be in week 1 of the next year — what US
  calendars print, and the only rule where week 1 always contains New Year), month calendars of
  4–6 rows, years. `PlannerCalendar` = `WeekStart` + `PlannerLanguage` (a curated list of 19:
  English UK/US, Czech, Danish, German, Spanish, French, Italian, Dutch, Norwegian bokmål,
  Polish, Portuguese Brazil/Portugal, Finnish, Swedish, Turkish, Greek, Russian, Ukrainian —
  all covered by the bundled Inter). `PlannerLabels` formats month and day names and dates
  with `intl` (CLDR); its date symbols are compiled in and initialised synchronously
  (`ensureDateSymbols`) before any label is built. Fixed headings ("Week", "Schedule",
  "Notes" …) stay English. New planners take the device locale's language (if listed,
  else English UK; there is no language picker) and its CLDR first day of the week (changeable
  under the planner options' collapsed "More options"). `PlannerPlan` (first month, 1–12 months,
  `linked`, `yearOverview`, calendar) generates the papers of a planner: a page per day, per
  week overlapping the range, per month or per year — monthly with `yearOverview`: the year
  overview before the first month and each January; linked: each month followed by its weeks,
  each week by its seven days. The year overview shows twelve mini calendars (3 × 4 portrait,
  4 × 3 landscape). Pages link year → month (titles) and day, month → year (the year label),
  week (week numbers) and day (cells), week → day (day headers) and month (that of its middle
  day), day → week and month — always in the page's calendar. A link is
  resolved at tap time to the first page with that exact `Paper`, so reordering, deleting or
  adding pages never breaks links; a missing target offers "Add page". Links are followed by a
  finger tap when fingers navigate (stylus mode), a Ctrl/⌘-click, or the long-press menu ("Go
  to …") — `LinkTaps` only watches pointers, so drawing is never disturbed.
- **My templates** (`templates` collection, `TemplateRepository`, `UserTemplate`): an image blob
  plus the page size it suggests. "Import…" in the picker takes an image (`ImageImport`) or a
  PDF page (rendered to a 2000 px PNG); "Save page as template" (page menu) renders the page
  as it looks (paper, background, ink, content). Pages made from a template reference the
  blob directly (`Paper.image`), so renaming or deleting a template never changes them.
- **Picker** (`features/documents/templates/`). `TemplateChooser` (search, then the
  `TemplateGallery` of live miniatures under category headings, no filter chips;
  `PlannerOptions`, `PaperOptions`, page size) is shared by
  the template picker (new page, change one / all pages, canvas background) and the
  new-notebook sheet; `templateSections` / `TemplateSelection` (`template_catalog.dart`) hold
  the logic. Planners generate a range when creating or adding ("Add 31 pages"); "Apply to all
  pages" with a planner dates the pages period after period. Image templates fix the page size.
  The picker opens through `showDialogOrSheet` (`ui/dialog_or_sheet.dart`, shared with New
  notebook, Export and the cover sheet): a centred dialog from `Breakpoints.medium`, where the
  chooser is `split` — gallery left, `TemplateOptions` (preview, planner options, paper colour,
  size) in a 300 dp column right, each scrolling on its own — and a bottom sheet on phones,
  stacked. **`PaperOptions`** (`paper_options.dart`, rows in `paper_option_rows.dart`) is the
  one compact "Paper" section: an actual-size `PaperSwatch` of the page's top-left corner, paper
  colour dots (+ custom picker, `ui/color_picker/pick_color.dart`), pattern colour (Auto,
  presets, custom) and opacity, spacing (slider + `PitchKind.presets`, e.g. narrow / college /
  wide), line weight or dot size, and Margin line / Header chips — only what the style uses;
  Reset restores the standard look. Choosing another template keeps the look but not the
  spacing (`TemplateSelection.paperFor`); the selected tile shows the selection itself.
  `TemplateGallery.fillWidth` picks the column count whose tiles come closest to the
  preferred width and stretches them to fill the row; paper colours and formats are
  `EvenChoices` (equal-width chips in one row, or two even rows).
- Pages carry their paper colour and size; new pages copy the current page's paper and size.

## Blobs and PDFs

Large binary data is **content-addressed**: a blob's id is the SHA-256 of its
bytes. `BlobStore` keeps a `blobs` table (size, mime, uploaded flag) and the
bytes in a `BlobBackend`: files under `<app support>/blobs/<sha[0..2]>/<sha>`
natively, an IndexedDB object store on the web, memory in tests. Its API is
path-free (`read`, `openRead`, `localPath` — null on the web). Each sync cycle first reads
`/v1/health` (the server's id, blob limit and last garbage collection), then uploads
pending blobs that live rows reference (`BlobSync`, `HEAD` then `PUT`), then pushes
records. One blob never stalls the others: a blob over the server's limit (or
refused with 413) is marked too large (`blobs.rejected_limit`), skipped from then on
and its records sync without it, shown as "1 file too large to sync" by the sync
button and in Settings → Sync (with Retry); a raised server limit is noticed
automatically. Any other failed upload is retried next sync, and records
referencing a still-pending blob are held back for up to
`SyncEngine.maxHoldBackAttempts` syncs, so a record normally never reaches the
server before its blob. Blobs are fetched lazily when a page needs them
(`SyncController.fetchBlob`).

`BlobReferences` is the reference graph (live page backgrounds, elements and
recordings; the trash is live, "delete forever" releases after 30 days, see
*Sync*). `LocalBlobGc` (started 20 s after launch, at most daily; old tombstones'
payloads are dropped first, 2,000 rows per transaction) deletes blobs unreferenced for 7 days
(`blobs.unreferenced_since`); it runs exclusively with `BlobStore`'s `put`
methods, and storing a blob again restarts its grace period. The server has its
own admin-run collector (server/README.md).

PDF import (`features/documents/pdf/`) stores the file once as a blob and
creates one page per PDF page with background `{type: pdf, blob, page}` and
the PDF page's size. PDF pages are rendered with PDFium via `pdfrx`
(`PdfRenderer`, serialised; PDFium runs on pdfrx's worker isolate natively
and in a web worker, never on the UI thread). `PdfBackgroundCache`
(`PageBackgrounds.paint`) renders a whole page up to 2048 px wide at the
zoom quantised to √2 steps; deeper zoom renders only the **tiles** in view
(`PdfTiling`: 512 px squares of levels whose page widths are powers of two,
4096 … 65536 px). Until a tile arrives the whole-page image and any cached
tiles of neighbouring levels are drawn beneath, so pinching stays smooth;
tiles are drawn without anti-aliasing so neighbours meet without seams.
Images and tiles share one LRU within a memory budget (160 MiB); requests
are served newest first (whole pages before tiles, the middle of the view
before its edges) and dropped when no paint repeated them for 2 s.
A PDF that is neither on the device nor fetchable (or that PDFium can't
read) is *missing* (`PageBackgrounds.isMissing`): its pages and their
thumbnails paint a hatched "PDF page unavailable" placeholder
(`missing_pdf_painter.dart`) instead of staying blank, and the editor shows
`MissingPdfNotice` with Retry (`retryMissing`, also run after each sync) and
Relink… (`relinkPdfFlow`): the same file restores the blob; a different one,
once confirmed and only if it has enough pages, replaces it page for page
(`PageRepository.relinkBackground`, synced like any page edit).
PDFium itself is a native asset downloaded at build time by `pdfium_dart`'s
build hook (Linux, Windows, Android), so no system package is needed; on the
web `pdfrx` runs PDFium as WebAssembly in a worker. `PdfRenderer` opens a
blob from its file when it has one (PDFium reads on demand) and from memory
otherwise (web).

Long imports and exports run behind `runWithSteps(…, cancellable: true)`:
the progress dialog's Cancel sets `TaskProgress.token` (a
`CancellationToken`, `domain/cancellation.dart`); the task throws
`Cancelled` at its next `step` / `stageStarted` / `check` and cleans up
after itself. An import checks while hashing the picked file
(`BlobStore.putFile(cancel:)`) and before creating pages (one transaction,
so nothing half-made remains) and deletes a blob it stored that nothing
references (`BlobStore.discardIfUnreferenced`); an export saves nothing and
disposes what it rendered.

Export (`features/documents/export/`): `PdfExporter` (package `pdf`) writes
ink as filled polygons flattened from the exact outline paths the app
renders, templates as vector lines, and **imported PDF pages as vectors**:
`PdfPageSources` parses each source PDF once with Len's own pure-Dart
reader (`export/vector/`: lexer, classic and stream cross-references,
object streams, `/Prev` chains, a recovery scan for broken files) and
`PdfPageImporter` copies a page into the export as a Form XObject — its
content stream(s) and a deep copy of its resources (fonts, images, shadings,
… written once per source however many pages share them), clipped to the
crop box, rotated by `/Rotate` — with annotation appearances (`/AP /N`)
flattened above it, so text stays selectable text and vectors stay sharp.
Encrypted (empty user password) or otherwise unreadable files are first
rewritten by PDFium (`PdfRenderer.normalized`: `encodePdf(removeSecurity:
true)`) and parsed again; a page that still cannot be copied (e.g. an
unsupported filter in a split content stream) is embedded as a 150 dpi
image, so export never fails because of one page. Text boxes are written as
selectable text in the embedded bundled fonts (`pdf_text.dart`, see *Text
boxes*). PNG export rasterises a page with the same painters as the editor.
**Links** (`PdfLinkWriter`) become link annotations after all pages are
written: link elements and planner links (to the first exported page with
the target template) as URI or GoTo actions to named destinations
(`page-N`), and the links of imported PDF pages — read from the source
`/Annots` by the copier (`vector/pdf_source_links.dart`: `/URI`, `/GoTo`,
`/Dest`, explicit or named via `/Dests` or the `/Names` tree), or from
PDFium (`PdfRenderer.links`) for pages embedded as images. Their areas are
normalised to the page as shown, so `/Rotate` and crop boxes are already
applied; page links go to the exported page showing the target (the next
one after the link's page) and are dropped if it is not exported.
The export sheet (`export_sheet.dart`) yields `ExportOptions` (format, page
indices from a range like "1-3, 5", templates and PDF backgrounds on or off;
PNGs are always 288 dpi, `pngScale`); without templates pages are exported as blank white paper.
**Canvases** export their whole drawing as one page (`exportCanvasFlow`, the
same sheet with `canvas: true`: no page choice, "Background" instead of
templates): `NotebookExporter.canvasPage` takes the content bounds plus a
48-unit margin, moves the ink and elements onto that page and records its
`worldOrigin`, so `paintWholePage` and `PdfExporter` lay the pattern from
the world's origin as the canvas does (grids line up with the screen).
Canvas PNGs shrink to at most 8192 px on the long side.
Files are saved with a save dialog on desktop (`file_selector`), the share
sheet on Android (`share_plus`) and downloaded in browsers
(`platform/file_export*`); several PNGs (`saveOrShareAll`) are shared at once
on mobile and written into a folder the user picks on desktop. On Android the
export sheet also offers Save to device: the system's save dialog (one file)
or folder picker (several), `SaveDocumentPlugin.kt` on `len/save_document`
(recordings offer Share and Save to device the same way).
The saver returns `ExportedFiles` (where they went), so the flow can say
"Saved “Lecture.pdf”" with Show in folder on desktops; an `ExportReport`
collects what was left out (missing PDF pages or images, PDF pages included
as pictures) for the same message, and failures show their raw text only
under Details.

**Why a Dart copier** (not PDFium page import): PDFium's
`FPDF_ImportPages` / `FPDF_NewXObjectFromPage` are reachable only through
FFI (`pdfium_dart`), i.e. not on the web, and would mean writing the ink
through PDFium's page-object API instead of package `pdf`. pdfrx's page
assembly (`PdfDocument.pages = …` + `encodePdf`) moves whole pages between
documents but cannot draw on top of them. Copying page objects in Dart
works identically on Android, Linux, Windows and the web, keeps one export
writer, and PDFium remains the fallback for files the reader declines.
Trade-offs: form-field annotations are not carried over (their
appearances are drawn), optional-content groups hidden by default in the
source may show, and the copied XObjects are drawn via `drawImage` on a unit
square because package `pdf` 3.13's `drawXObject` writes an invalid resource
name.

### PDF pages in the editor (`features/editor/pdf/`)

`PdfInteraction` (per paged editor, in `EditorSession.pdf`) reads text with
character boxes, links and outlines through `PdfInfoSource`
(`PdfrxInfoSource`: the documents `PdfBackgroundCache`'s renderer already
opened, so no second copy of the PDF) into `PdfPageInfoCache` (LRU per page;
`PdfLayer` preloads the pages in view).

**Rotated pages.** PDFium reports character boxes and link rectangles in the
page's own space (before `/Rotate`); `pdfRectToDisplay`
(`domain/pdf_page_space.dart`) normalises them to the page as shown (what
the import's page size and the renderer use), for every quarter turn.
`PdfGlyphs.lines` (`data/search/pdf_glyphs.dart`) then groups characters
into lines from the boxes themselves — consecutive non-space boxes that
step the same way (left→right, top→bottom, right→left or bottom→top) and
overlap across the line, broken at line breaks — so text on turned pages,
or set at an angle, selects along its direction: hit tests measure "along"
and "across" per line, handles sit at the line's start / end corners
(`PdfTextLine.startCorner`, knobs beyond the tops / bottoms of the
letters), highlights run along the line's middle in reading order, and
search highlights use the same boxes.

- **Select text** — there is no text tool: a finger long press or right
  click on PDF text with any tool selects the word instead of opening the
  canvas menu. With the lasso the pen selects text too (`PdfInteraction`
  is the lasso's `LassoText`, `ink/tools/lasso_tool.dart`): where no ink or
  element is hit, a tap on text selects the word, a press held still
  selects it and dragging on extends it, and a quick open drag (not a
  loop; with the rectangle lasso, any drag) that selects no ink selects the
  text it spans; a loop starting on
  text still selects the ink it circles. Dragging the selection's handles (`PdfSelectionHandles`,
  touch targets over the painted knobs that keep the press from the canvas)
  extends it — also onto other PDF pages: `PdfSelection` is a list of
  per-page `PdfSpan`s (`PdfInteraction.selectRange`: the anchor's page from
  the anchor on, pages between whole, the focus's page up to the focus),
  copied with a blank line between pages and highlighted page by page. `PdfLayer` paints the selection (one box per line, with
  handles) and a menu (`PdfSelectionMenu`; it and the handles follow the view
  at layout time, without rebuilding): **Copy** (also Ctrl/⌘+C; icon only under 480 dp),
  **Highlight** as the highlighter's quick colours (`PdfHighlightSwatches`:
  up to 3, the current one first and ringed; one tap highlights in that
  colour, the highlighter keeps its own), select all on the page.
- **Highlight** turns each selected line (`PdfGlyphs.rectsFor`) into one
  highlighter stroke along its middle (`PdfHighlights`, shared with the
  text-aware highlighter, see Input), 1.1 × the line's height, with the
  colour picked (by default the highlighter's) and the highlighter's opacity
  (no pressure thinning or stabiliser),
  committed to the page's `SurfaceModel` as one `InkEdit` — so it
  is ordinary ink: undoable, erasable, selectable, synced and exported.
- **Links** (`loadLinks`, incl. URLs detected in the text): tapped with a
  finger while fingers navigate (stylus only), or, with any tool, from the
  menu of a selection made on them (long press or right click: **Open
  link**). Internal links scroll to the notebook page showing the target PDF page (the next
  one after the link's page if the PDF appears twice); web links ask first
  ("Open link?") and open in the browser (`url_launcher`).
- **Outline** — the page overview's *Outline* filter (▦ → Outline, or
  "⋯" → *Outline*, which opens the overview on it; `NotebookOutlineView`
  hosting `OutlinePanel`): the notebook's own entries (add, nest, rename,
  relink, delete) and the bookmarks of every PDF in it as collapsible trees
  with notebook page numbers; entries whose page was deleted are disabled.
  Picking one closes the overview on its page. The overview's filter is
  All / Bookmarked / Outline (`OverviewFilter`; labels only on phones).

## Images (`ink/images/`, `features/editor/images/`)

- **Import** (`ImageImport`): PNG, JPEG and WebP files up to 4096 px and 8 MiB
  are stored byte for byte; anything else the platform can decode (larger
  images, GIF — first frame —, HEIC/HEIF on Android, BMP) is decoded by the
  engine at ≤ 4096 px and re-encoded in an isolate (`package:image`): JPEG
  when opaque, PNG with transparency. The bytes become a content-addressed
  blob (so they sync like PDFs) and an `image` element at natural size
  (1 px = 1 world unit), shrunk to 70 % of the view and kept on the page.
  Entry points (`EditorImages`): the top bar button (file picker; on Android
  also the camera via `Camera`, see *Document scans*), Ctrl+V (`pasteboard` reads the system
  clipboard's image, or a copied image file on desktop; a clipboard image
  older than ink copied in the app loses to the ink) and drag and drop
  (`desktop_drop`). Every insert is one undoable edit and selects the image.
- **Decoding** (`ElementImages`, one per app in `AppServices`): bitmaps are
  decoded asynchronously by the engine (`ImageDescriptor`, off the UI thread)
  at mip levels — powers of two from 64 px up to the natural width — and kept
  in an LRU within a memory budget. `imageFor` never blocks: it returns the
  best bitmap cached (or null → placeholder), schedules the decode and later
  reports the blob on `changes`. Missing blobs are fetched lazily with
  `SyncController.fetchBlob`; unavailable ones show a crossed-out placeholder
  until the next sync retries them.
- **Rendering**: chunk pictures record the bitmap that suits the zoom. The
  painters report the zoom (`ChunkPictureCache.setScale`); crossing a power of
  two re-records only chunks containing images, and a finished decode
  refreshes just the chunks showing that blob (`SurfaceModel.refresh`).
  Selections, page-overview thumbnails and library covers re-record the same
  way; PNG export decodes first, PDF export embeds JPEG blobs as they are and
  other formats as pixels, with rotation as a PDF transform and the crop as a
  clip (`PdfImageWriter`).
- **Editing** uses the lasso: tap or lasso to select (ink over an image wins a
  tap; a lasso must enclose most of an image beneath the ink, not just its
  centre), move / resize (corners keep the aspect ratio) / rotate with the
  selection frame (which follows a single element's rotation), bring to front
  / send to back, duplicate, copy/paste, delete. **Crop** (`ImageCropSession`
  + `ImageCropOverlay`) works in the image's unrotated frame: handles move the
  crop edges, dragging inside pans it, and committing keeps the visible part
  exactly where it was on the surface.

## Document scans (`features/documents/scan/`, `platform/scan_runner*`)

Photos of paper pages become notebook pages whose background is the
flattened, cleaned-up photo (`PageBackground.image`, a JPEG blob; see
SYNC_PROTOCOL). All pure Dart, so it works on every platform.

- **Detection** (`QuadDetector`, `QuadHull`, `GreyOps`): luminance at ≤ 400
  px, blurred; bright regions (Otsu's threshold and a stricter one), dark
  ones and strong-edge (Sobel) ones covering ≥ 15 % of the photo become
  convex hulls, simplified; the largest inscribed quadrilateral wins if its
  sides show a clear step in brightness, the same way round, all round.
  `QuadRefiner` then fits each side at the input's resolution (≤ 1600 px):
  the strongest step across it, the same way round, located to a fraction
  of a pixel along ~100 normals, a robust line (Theil–Sen, then least
  squares over the points within 1.5 px) and the corners where the lines
  meet (to ~0.1 px on synthetic photos; implausible results keep the
  coarse quad), then moved 1 px inside (`QuadDetector.inset`): soft or
  stepped paper edges leave no hairline of desk on the white page.
  `ScanPhoto.load` measures the photo (EXIF-upright through the engine),
  keeps it as a JPEG (quality 92) of at most 3200 px when it is larger or
  heavier than a byte a pixel (so a long scan holds no more than the pages
  need: per page that JPEG and an 800-px RGBA working copy), decodes the
  working copy and runs `detectScanQuad` on it; no convincing page → the
  whole photo.
- **Flattening** (`ScanJob`, `scan_warp`, `scan_enhance`): a perspective
  warp of the quad (bilinear, supersampled when shrinking) to a page whose
  sides are the quad's (long side ≤ 2500 px, from the photo decoded at ≤
  3200), turned in quarter turns, then a `ScanFilter`: a coarse paper
  brightness map flattens shading and white-balances; tone curves per
  filter (Colour, Greyscale, B&W). `scan_runner` runs jobs and detection on
  a worker isolate natively and in yielding slices on the web.
- **Screen** (`ScanScreen`, `ScanSession`, `ScanCornerEditor`,
  `ScanControls`): a full-screen route over a session of `ScanPageDraft`s
  (photo, quad, turns; a small flattened preview each, re-rendered latest
  wins; only the current page's photo is decoded for display, at 1600 px).
  The corner editor drags corners and side middles (folds refused, corners
  kept on the photo) and shows a 3× loupe in the top corner away from the
  finger while a corner moves; the outline's preview re-renders when the
  drag ends. A drag's moves notify `ScanSession.outline` (only the corner
  editor listens), not the session, so the rest of the screen stays put. Preview (or tapping the current page in the strip, or Space)
  switches to its result (`ScanResultView`, `ScanResultRenderer`): the page flattened
  and cleaned up at 1600 px from the photo decoded at that size (kept only
  while shown), re-rendered on every change; tapping it goes back.
  The strip (`ScanPageStrip`) reorders by drag (at once with a mouse,
  after a long press on touch); ← / → pick a page, Ctrl+← / → move it.
  Commands: Preview, Rotate, Whole photo (toggles with the page found), Retake
  (camera) / Replace… (files), Remove, + (camera or files), and the look
  for all pages (remembered for the next scan:
  `SettingsRepository.scanFilter`). Without a camera the file picker opens
  at once (nothing picked → the screen closes); with one (Android,
  `image_picker`) the screen starts by offering both. Leaving with pages
  asks first.
  `ScanSources` is the seam for tests (`ScanSources.debugSources`).
- **Camera photos after a kill** (`features/camera/`, `platform/camera_capture.dart`).
  Android may kill Len while the camera app is in front (low memory); the
  photo then comes back only through `image_picker`'s `retrieveLostData()`
  at the next start. Every camera use goes through `Camera`
  (`AppServices.camera`), which keeps a `CameraPurpose` in the settings
  (`camera_purpose`) while the camera is open: a scan into a new notebook,
  a scan into notebook N after page P, or a photo on surface S (page or
  canvas) centred on a point. At startup the library asks once
  (`resumeLostPhoto`, after reopening the workspace) and carries on, saying
  "Recovered the photo you took": the scan screen with the photo (for an
  insert, in the notebook's editor, opened or switched to first), or the
  photo inserted on its page at its spot (`EditorImages.insertRecovered`;
  a canvas scrolls there). Fallbacks: a scan whose notebook is gone (or
  trashed) becomes a new notebook; a photo for a deleted page goes on the
  page shown; a photo whose notebook is gone, or without a purpose, is
  taken like a shared image (into the shown editor, asked, or a new
  canvas). Only the photo survives: pages scanned before it in that
  session were in memory. `CameraCapture` is the platform seam (Android
  only; elsewhere no camera and nothing to retrieve); tests use
  `FakeCameraCapture`.
- **Import** (`scan_flow`, `ScanImporter`): after Done, each page is
  flattened at full size and stored as a blob behind a cancellable progress
  dialog; then one transaction creates the notebook (titled "Scan <date>",
  blank paper) or inserts the pages after the current one
  (`DocumentCommands.insertScan`, undoable as one edit). Cancelled or failed
  imports drop the blobs nothing references. Page size: A4 or Letter (either
  way round) within 3 % of the scan's shape, else A4's area at its shape.

## Opening files from other apps (`features/documents/import/`, `platform/incoming_files*`)

"Open with Len" / "Share to Len" for PDFs and images, GoodNotes-style.

- **Sources** (`platform/incoming_files*`, `openIncomingFiles(args)` → a stream of
  `XFile` batches, wired in `main.dart`):
  - *Android:* intent filters on `MainActivity` for `ACTION_VIEW` (content URIs)
    and `ACTION_SEND` / `ACTION_SEND_MULTIPLE` with `application/pdf` and
    `image/*`. `IncomingFiles.kt` copies each URI (read permission only lasts
    with the intent) off the main thread into `cache/incoming/<uuid>/<display
    name>` and calls `files([{path, name, mime}])` on `len/incoming_files` once
    Dart has called `ready`, so the launch intent (cold start, `onCreate`) waits
    for Dart; later intents arrive through `onNewIntent` (warm start). The
    activity is `singleTask` so a share from another app reaches the running Len
    instead of starting a second engine in that app's task. Copies are deleted
    when the next engine starts. Only other apps' `content:` URIs are read (no
    `file:`, none of Len's own providers: no app can make Len import its own
    private files), and a start from the recent apps (which repeats the first
    intent) imports nothing.
  - *Linux:* paths / `file://` URIs on the command line (`Exec=len %U`;
    `MimeType=application/pdf;image/png;image/jpeg;image/webp;x-scheme-handler/len`
    in the desktop entry). The GTK runner is single-instance (`G_APPLICATION_HANDLES_OPEN`): a
    second `len file.pdf` forwards the files over D-Bus to the running one,
    whose `open` handler sends them on `len/incoming_files`, and exits.
    `LEN_MULTI_INSTANCE=1` or a non-default `XDG_DATA_HOME` (screenshots, tests;
    Flatpak's own `XDG_DATA_HOME` does not count) turn this off.
  - *Windows:* command-line paths (the runner passes them to `main`); the
    installer registers Len in the "Open with" lists of `.pdf`, `.png`,
    `.jpg`/`.jpeg` and `.webp` (and as a choice in *Default apps*, never
    taking over a default). The runner is single-instance
    (`windows/runner/single_instance.cpp`): a named mutex marks the running
    Len, which serves a named pipe (current user only, local only, created
    at start-up so launches during start-up queue). A second launch sends
    its absolute paths (`LEN1` header, one UTF-8 path per line), waits for a
    one-byte acknowledgement and exits; the server thread queues the paths and
    posts a registered window message, and the window sends them on
    `len/incoming_files` once Dart is `ready` (and comes to the front). If the
    running Len is closing (no acknowledgement), the second launch waits for
    the mutex and becomes the instance. Explorer starts one process per
    selected file, so each arrives as its own batch. `LEN_MULTI_INSTANCE`
    turns it off. Forwarded paths that do not exist are dropped (Linux too).
  - *Web:* the installed PWA's File Handling API (`file_handlers` +
    `launch_handler: focus-existing` in `manifest.json`; `launchQueue`
    consumer), Chromium-based desktop browsers only. Files can also be dropped
    onto the library on every platform (`LibraryFileDrop`, `desktop_drop`,
    which supports the web).
- **`IncomingFiles`** (in `AppServices`) buffers batches until the library sets
  its handler (cold start) and holds `ImportTargets`: the shown editor
  registers an `EditorImportTarget` (insert PDF pages after the current page /
  images on the current page or canvas).
- **Sync setup links** (`sync/sync_setup_link.dart`): `len://sync?url=…&token=…`.
  Android's `len://sync` intent filter reaches `IncomingFiles.kt`, which sends
  `link(<link>)` on the same channel (queued until `ready`). On Linux and
  Windows the link is a command-line argument (`len "len://sync?…"`; the
  desktop entry's `x-scheme-handler/len` and the installer's `len` URL
  protocol open links with Len): the primary instance reads it from its
  arguments, a second instance forwards it as a "path" as it is
  (`isIncomingLink`). The Dart side (`incomingLinks`) feeds `IncomingFiles.syncSetup`, which the library turns into
  Settings → Sync and `SyncSettings` takes to fill its form (pasting the link
  into Server URL does the same). A connected device shows the link as a QR
  code (`ui/qr_code_view.dart`, the pure-Dart `qr` package) and Copy link.
- **`ImportRouter`** (pure, tested) classifies files by MIME type, else
  extension (PDF, image, unsupported) and plans `ImportStep`s: with nothing open,
  each PDF becomes a notebook (existing PDF import flow) and all images one new
  canvas; with an editor open, the user is asked "Add to this notebook" or "New
  notebook / canvas" (PDFs always become notebooks when a canvas is open).
  Unsupported files get a friendly message.
- **`ImportFlow`** carries a plan out with the existing flows (progress dialogs,
  messages), one batch at a time; new notebooks open in editor tabs (the last
  one shown; an open editor just switches tabs), and images wait for the new
  canvas's editor (`ImportTargets.waitFor`) to be placed by `EditorImages`.

## Audio (`features/audio/`)

GoodNotes-style lecture recording: audio is captured while writing and
replayed in step with the ink.

- **Data.** A recording is a synced `recordings` row (`RecordingRepository`)
  of a notebook whose audio is an ordered list of **parts** (`RecordingPart`:
  a content-addressed blob and its duration), like PDFs and images.
  Its `segments` (`[startedAt, durationMs]` per stretch between pauses) map
  audio positions to wall time and back (`RecordingTimeline`; ink written
  during a pause belongs to the moment recording resumed). Strokes carry
  `createdAt` = the moment the pen touched down (`InkInputController`,
  `ShapeTool`), elements their creation time, so content needs nothing else
  to be replayed. Its `waveform` is a second, small blob (`domain/waveform.dart`,
  one loudness byte per 100 ms ≈ 36 KB per hour, format in SYNC_PROTOCOL)
  built while recording from the recorder's input level (`WaveformBuilder`),
  so no platform ever has to decode audio. Deleting a notebook tombstones its
  recordings; duplicating copies them (same blobs).
- **Recording** (`RecordingController`): start / pause / resume / stop with
  elapsed time and an input level meter. Natively `package:record` captures
  **raw AAC in ADTS frames** (`audio/aac`, mono, 64 kbit/s ≈ 29 MB per hour):
  every frame carries its own header, so files join by concatenation, can be
  cut between any two frames, and stay playable when cut off mid-frame
  (`adts.dart`: `AdtsReader` finds whole frames and counts their audio). On
  Android and Windows the recorder streams the frames to Len (`startStream`;
  its file mode would write MP4 there), which writes them itself; on Linux
  `ffmpeg` writes the `.aac` file. Browsers record AAC in MP4 (Safari) or
  Opus in WebM, held in memory until the recorder stops; WAV is a last
  resort. Captures under 0.5 s are discarded. Closing the editor stops and
  saves a running recording.
- **Parts: upload while recording** (`RecordingParts`). Every
  `RecordingController.partMs` (5 min) of audio the capture moves on to a
  new file (`AudioCapture.split`): where frames are streamed to Len the cut
  falls between two frames and no audio is lost; elsewhere (Linux, browsers)
  the recorder restarts — a gap of roughly 0.1–0.3 s every 5 minutes. The
  finished file becomes a blob at once (`BlobStore.putFile`, streamed) and
  the `recordings` row is saved with the parts so far (plus the waveform so
  far), so the blob is referenced — uploaded by the next sync, kept by
  garbage collection — while recording continues. The row being made is
  left out of its own device's recordings list until stopped; other devices
  see it grow part by part. Stop stores the last part.
- **Recovery** (`recording_journal.dart`, `recording_recovery.dart`).
  Natively the capture files live in a spool directory,
  `<app support>/recording` (`SpoolStorage`, `platform/spool_storage*`),
  next to a small JSON journal per recording (`RecordingJournal`: notebook,
  title, MIME type, stored parts, pause stretches and the running one's
  start, files not stored yet), rewritten at start, each part, pause and
  resume. A clean stop deletes both. On the next start the library looks for
  journals of recordings not being made (`offerRecordingRecovery`, once per
  run) and asks "Recover recording?": Recover stores the leftover files'
  whole frames as further parts (durations from frame counts) and saves the
  row with a timeline fitted to the audio (`RecordingJournal.timelineFor`);
  Discard deletes the files (parts stored before stay either way). Browsers
  have no spool: a killed tab keeps only the parts finished before.
- **Background recording** (`RecordingKeepAlive`, `AudioBackends.keepAlive`):
  Android hands backgrounded apps silence, so while recording a foreground
  service of type `microphone` runs (`RecordingService.kt`, driven by
  `RecordingServicePlugin.kt` on `len/recording_service`, Dart side
  `backends/android_keep_alive.dart`). It holds a partial wake lock and shows
  an ongoing notification (title, live time, Pause / Resume, Stop; tap opens
  Len); its buttons reach the `RecordingController` that showed it, and it
  ends once the recording is saved. The notification permission is asked
  once, before the first capture (Android 13+); refusing it does not stop
  background recording (the service is then only listed in the system's task
  manager). With the service up, pausing the app (screen off, another app in
  front) keeps recording (`NotebookAudio`); if it could not start (or reports
  `failed`), the old behaviour applies: the recording is stopped and saved
  when the app is paused. Back at the library's root moves Len to the back
  (`MainActivity.popSystemNavigator`; predictive back does the same) instead
  of finishing the activity, which would end the engine and the recording;
  the activity also handles every configuration change Flutter follows by
  itself, as any recreation restarts the engine. Swiping Len away from the recent apps asks Dart to
  stop and save, and the service quits after a grace period (or as soon as
  the engine detaches). Other platforms have no keep-alive (desktop apps keep
  the microphone; browsers keep recording in a background tab).
- **Playback** (`PlaybackController`, `package:audioplayers`): plays one
  recording at a time, fetching missing blobs from the server first. Raw AAC
  parts are joined into one source (natively a temporary file streamed from
  the blobs, a single part is played from its blob file; browsers get a blob
  URL), so playback and seeking across parts are seamless; parts that don't
  join (browser recordings) play one after the other with positions mapped
  across them (`RecordingPartsMap.partAt`) — a short gap at each joint; speed 0.75–2×
  (kept across recordings while the editor is open), skip ±10 s. The backends
  are created only when the user records or plays, so platforms and tests
  that never do never touch the audio plugins (`AudioBackends`; tests use
  fakes).
- **Background playback and media controls** (`PlaybackSession`,
  `platform/media_controls*`, `AudioBackends.mediaControls`). Once a
  recording first plays, the system's media controls show it (title, the
  notebook as album; position and length in the kept audio) until the player
  closes: Android's media session and notification, MPRIS on Linux
  (`org.mpris.MediaPlayer2.len`: GNOME / KDE controls, media keys,
  `playerctl`), the Media Session API in browsers. They are updated on play /
  pause, seeks (`PlaybackController.seeks`), speed and title — not on every
  position, which the system extrapolates — and send back play, pause,
  ±10 s (a headset's next / previous too: a lecture has no tracks), seek
  and stop (closes the player). One owner per app: the notebook that showed
  last. **Android** (`PlaybackService.kt`, `PlaybackServicePlugin.kt` on
  `len/playback_service`, Dart `platform/media_controls_android.dart`): a
  foreground service of type `mediaPlayback`, started when playback starts
  (Len in front, as Android 12+ requires) and kept while the player is open,
  paused or not (resuming from the notification needs no new start); a
  platform `MediaSession` (lock screen, Android 13+ media controls with ±10 s
  and stop as custom actions, Bluetooth buttons), a `MediaStyle`
  notification with the same buttons for Android ≤ 12 (no permission asked:
  media notifications are exempt), and a partial wake lock while playing.
  `PlaybackFocus.kt` holds audio focus (spoken media; `audioplayers` is set
  to `AndroidAudioFocus.none` so Dart's play state is the only one) and
  reports `focusLoss` (another app: pause), `focusLossTransient` (a call:
  pause, play again at `focusGain` unless the user played or paused in
  between), `duck` (Android ≤ 7 only; 8+ ducks by itself; volume 0.2) and
  `noisy` (headphones unplugged: pause); the decisions live in Dart
  (`PlaybackSession`), the plain mappings in `PlaybackEvents.kt` (JVM
  tests). With the service up, a paused app keeps playing (`NotebookAudio`);
  the position keeps arriving, so the ink replay is in step on return.
  Swiping Len away from the recent apps closes the player. **Windows** has
  no system controls (SMTC would need a native plugin with a Rust or C++
  toolchain); there and on Linux without a session bus, the keyboard's media
  keys work while Len is in front (`playback_keys.dart`).
- **Trimming** (non-destructive). A recording's row keeps the audio range
  it plays, `trimStartMs`…`trimEndMs` (positions in the whole audio; `0`
  and the duration when untrimmed), synced with it. Positions stay those of
  the whole audio everywhere; `PlaybackController.startMs` / `endMs` (the
  trim, or `trimDraft` while it is edited) clamp seeking and skipping,
  opening seeks to the start and reaching the end pauses as the end of the
  recording would. The list and the player show the kept length
  (`Recording.lengthMs`), the scrubber shows only the kept audio
  (`WaveformScrubber` `fromMs` / `toMs`; waveform bars and ink density take
  a range). Ink is related to the kept audio only
  (`Recording.inkPositionOf`): ink made before the start counts as written
  before the recording, ink made after the end as written after it — never
  veiled (`veilUntil` → `ReplayVeils.pictureFor(until:)`), not tappable to
  play, no markers. Trim mode (`trim_panel.dart`, `trim_scrubber.dart`;
  from the scissors in the player's title row or "Trim…" in a recording's
  menu) shows the whole waveform framed by two handles (drag; focus and ← /
  → by 1 s, Shift 0.1 s; at least `Recording.minTrimMs` = 1 s apart,
  `TrimEditing` in `trim_range.dart`), audio outside drawn faint; preview
  plays only the kept audio (after moving the end it plays the last 2 s);
  "Keep all", Cancel, Save. Saving is not an editor undo step (recordings
  are not part of a surface, like renaming): its message offers Undo, and
  "Reset trim" in the list restores the whole recording at any time.
  Export of raw AAC keeps the whole frames overlapping the range
  (`AdtsReader.cut`, ≈ 23 ms at 44.1 kHz, exact sample counting); browser
  recordings (MP4 / WebM files, which would need remuxing) export the whole
  parts the trim touches (`exportGroups`; the message says so when that is
  wider, `exportsWider`).
- **Freeing a trim's storage** (`domain/recording_release.dart`,
  `trim_release.dart`, `ui/free_up_space.dart`). The trim stays adjustable
  until the user frees it: a recording whose trim leaves parts wholly
  outside offers "Free up 12 MB…" in its menu (the bytes of those parts on
  this device not shared with another recording, e.g. a duplicated
  notebook's — `NotebookAudio.releasableSize`). Confirmed, the row is
  rewritten without them (`withoutPartsOutsideTrim`): the kept parts, their
  duration, the trim and the timeline (`RecordingTimeline.slice`, wall times
  kept, so ink maps to the same moments) moved to begin at the first kept
  part, and the waveform cut likewise into a new blob (`Waveform.slice`;
  `''` if it can't be had). It is one synced row update
  (`RecordingRepository.replace`), so other devices converge on the shorter
  parts list (last writer wins on the whole row, so parts, trim and timeline
  always agree); the dropped blobs are then unreferenced and freed by blob GC
  after its grace (7 days on devices, 30 on the server), which is what makes
  the message's Undo (`NotebookAudio.restore`, the old row as a new version)
  safe. An open player reopens audio whose parts changed (positions moved),
  paused at the kept start.
- **Overview** (`recording_overview.dart`): per recording the waveform (loaded
  once, fetched when missing) and the `InkActivity` — the audio positions at
  which the notebook's strokes and elements were made
  (`RecordingRepository.contentTimes`, indexed by `strokes(surface_id,
  created_at)`), re-read whenever a recording is opened. Bursts of writing
  (separated by ≥ 4 s without any) become markers.
- **Ink replay** (`replay/`): while a recording is open, `InkReplayLayer`
  draws a veil over strokes, text boxes and images created after the moment
  being heard (`InkReplayPainter`: one cached picture of the "future" content
  per visible chunk, filled in the paper colour at 82 % opacity — text boxes
  as their glyph silhouettes, images as their box, with past ink cut back out
  of a later image beneath it — re-recorded only when that set changes).
  Ink appears from when it was *begun*. With "tap ink to play" on, a tap on a
  stroke, text box or image seeks to 1.5 s before it was made (in the open
  recording, else the latest recording of the notebook covering that time);
  drags and pinches still pan and zoom.
- **UI.** Tablets and desktops get a top bar slot (microphone, recordings
  list, and while recording flat `RecordingControls`: time, level, pause and
  stop); phones get "⋯" menu entries and the recording controls in the audio
  strip (`AudioLayer`). The strip is docked along the bottom of the canvas
  (Board, a hairline on top; its height in `NotebookAudio.stripHeight` lifts
  the page indicator and tips) and holds the player (`PlaybackBar`): title and time, a
  `WaveformScrubber` (played part in the accent colour, ink density strip with
  a dot per burst; tap or drag to seek, a tap near a dot plays from just
  before that writing), skip ±10 s, play / pause, speed menu, "tap ink to
  play", recordings, close. Keys while the player is open
  (`playback_keys.dart`, ahead of the editor's shortcuts, never while typing):
  Space play / pause, ← / → ±10 s (instead of turning pages), Shift+← / → the
  previous / next burst of writing. The recordings sheet shows each
  recording's date, (kept) duration and size and the total; tap plays, ⋯
  renames, trims (or resets the trim, or frees the space trimmed away), exports or deletes; long press or "Select" picks several to export or
  delete at once. Export hands the audio file (`.aac` with the parts
  joined; browser recordings in parts as one `.webm` / `.m4a` per part the trim touches)
  to the existing save / share path (`platform/file_export`: save dialog on
  desktop, share sheet on Android, download on the web). `NotebookAudio`
  owns all of it per open notebook (one per notebook, shared by its editors
  through `SharedNotebook`; saved when its last editor closes) and reloads when
  sync reports `recordingsOfNotebooks`. `RecordingController.busy` keeps to one
  recording at a time across notebooks.

## Input (`ink/input/ink_input_controller.dart`)

Raw `Listener` pointer events (no gesture arena → no latency, full pressure data).
The controller only routes: the drawing contact (ink, erasing, pointer tools, commit
and bounce) is `input/ink_drawing.dart`, point thinning and pressure
`input/stroke_sampler.dart`, pan/zoom, wheel and trackpad `input/pointer_navigation.dart`.

- **Stylus** draws; the **eraser end** erases; the **side button held** (S Pen) does
  the user's `PenButtonAction` (`input/stylus_buttons.dart`): erase, lasso (a selection
  made that way stays live — pressing on it moves it, pressing elsewhere drops it and
  draws again; it follows the lasso options, a rectangle included) or nothing.
  A stylus touching down cancels a stroke a resting palm may have started.
- **Touch**: with *stylus only* (palm rejection) on, fingers pan/zoom; off,
  one finger draws and a second finger turns it into a pinch.
  Stylus-only switches on automatically the first time a stylus is used.
  **Palm**: a touch landing while the pen touches, hovers, or lifted < 300 ms ago
  (`InkInputController.palmQuiet`, `StylusProximity`) neither navigates nor draws —
  between strokes the pen only lifts briefly.
- **Mouse**: left draws, middle/right drag pans (a right click without dragging opens the
  context menu), wheel scrolls (stops a glide), Ctrl+wheel zooms about the cursor
  (`exp(-dy/400)` per event, at most 2× per event).
- **Trackpad**: two-finger pan, pinch zoom about the cursor (the event's total scale, so
  it follows the fingers exactly); fingers back on the pad (`PointerScrollInertiaCancel`)
  catch a glide.
- **Navigation feel** (`input/pointer_navigation.dart`, `navigation/kinetic_pan.dart`):
  the fingers' centroid pans and their spread zooms about it, so the point under the
  fingers stays there; fingers landing or lifting never jump the view. Like native
  scroll views a gesture moves the view only once a finger passes `kTouchSlop` (the
  view then lags by the slop, never jumps), and zooms only once the spread changes by
  8 px — taps and resting fingers never nudge the page, two-finger pans never drift in
  zoom (and glide). A gesture that moves the view is never a tap, double tap or long
  press (`CanvasGestures.navigated`). Past the zoom limits a pinch stretches the zoom
  with resistance (`ViewportController.stretchAt`, at most 1.25×) and springs back on
  release. When a gesture lets go, `KineticPan` first asks `settle` (a pinch ending
  within 8 % of the home zoom — page fit, 100 % on canvases — snaps to it,
  `DoubleTapZoom.snap`; single-page flow glides back to the whole page unless zoomed in,
  `DocumentController.settleSingle`), then springs back, then glides (iOS-like decay:
  travels v/2, stopped by any touch, wheel or page jump).
- **Canvas gestures** (`input/canvas_gestures.dart`) watch the same events without
  claiming them: a quick, still two-/three-finger tap (`MultiFingerTapDetector`:
  ≤ 300 ms, ≤ 24 px travel) → undo / redo; a still one-finger long press with a
  navigating finger, or a right click (`LongPressDetector`, `SecondaryClickDetector`)
  → the canvas context menu; a navigating finger's double tap (`DoubleTapDetector`:
  two ≤ 250 ms taps ≤ 300 ms apart, ≤ 40 px from each other, ≤ 18 px travel, never
  with a second finger down — so two-finger taps stay undo) → **double-tap zoom**
  (`features/editor/double_tap_zoom.dart`: the page fit — 100 % on canvases — ⇄ 2× or
  the zoom last left this way, about the tap, animated). Fingers that draw (palm
  rejection off) never zoom: their taps are dots. Palm safety: taps, double taps,
  two-finger holds and long presses are ignored while a stylus touches, or was seen
  touching or hovering within 600 ms. The recognisers live in `CanvasGestures`, so
  `ink_input_controller.dart` is unchanged.

Stroke outlines come from the in-house engine in `ink/render/` (see *Ink
rendering* below); paths are memoised per stroke. PDF export flattens the same
paths.

### Dense stylus input on Android (`input/sample_source.dart`, `platform/stylus_samples*`)

Android batches input: each `ACTION_MOVE` carries every digitiser sample since
the previous frame (240+ Hz with an S Pen) as *historical* samples, but
Flutter's embedding (`AndroidTouchProcessor`) forwards only the newest one —
about one point per frame. `MainActivity.dispatchTouchEvent` therefore hands
each stylus `MotionEvent` to `StylusCapture.kt` first, which sends all of its
samples (position in Flutter-view pixels, pressure, `AXIS_TILT`,
`AXIS_ORIENTATION`, time) as one binary message on `len/stylus_samples`
(`StylusBatchCodec`: packed float32/float64, one message per event, no
per-sample calls), then lets Flutter have the event untouched.

The input controller asks a `SampleSource` for the samples between two pointer
events of the drawing contact (`begin` on pen-down, `between(event)` before each
move and before the up, `end`). `StylusSampleMerger` matches batches by Flutter
device id (`pointerId << 3 | toolType`), the contact's down time and the event
time (a `PointerEvent.timeStamp` *is* its `MotionEvent`'s event time): for the
event's own batch it inserts the historical samples, for a batch whose event
never reached Flutter all of them. Positions go physical px → logical px
(`devicePixelRatio`) → the event's local space (its `transform`) → world
(viewport), and pressure is normalised with the event's range, so a merged
sample is indistinguishable from a pointer event. Batches that arrive after
their event was handled are dropped (never out of order), duplicates and
anything after `end` are ignored, so a late or silent channel just means
today's one-sample-per-frame input. Other platforms get no source (web
browsers and desktop embedders already deliver every sample). Tilt and
orientation are carried but not used yet.

### Low-latency ink (Android; `WetInk*.kt`, `platform/low_latency_ink_native.dart`)

Flutter shows a pen sample about 30 ms after the digitiser took it (p50;
40 ms p90; Galaxy Tab S8+, 120 Hz; `docs/INK_LAB.md`, *Low-latency ink*):
input waits for the next frame, the frame is built on the UI thread (merged
with the platform thread), rasterised, queued and latched by
SurfaceFlinger. So on Android (10+) the newest part of each pen stroke is
also drawn by the platform, straight into the buffer the display scans
out, the way Samsung Notes and Notewise do: there it shows about 5.5 ms
after the digitiser event (4 ms after it reaches the app; p99 under one
120 Hz frame), measured the same way.

- **Input**: `MainActivity.dispatchTouchEvent` hands every event to
  `WetInkOverlay` before Flutter. At a stylus down it asks for
  *unbuffered dispatch*, so each S Pen sample arrives on its own (240 Hz)
  instead of in one batch per frame.
- **Rendering** (`WetInkLayer`): a translucent `SurfaceView` (media-overlay
  z-order, same bounds as the Flutter view) drawn only through the **front
  buffer** of androidx.graphics' `CanvasFrontBufferedRenderer`: no buffer
  swap, no vsync wait. Each frame clears what the previous one covered and
  redraws the whole wet ink (a few millimetres), so ink can also be taken
  away. At most one frame is queued; newer input replaces a waiting one.
  The hull pieces of a stroke are filled as **one path** (they wind the same
  way), so their antialiased edges are not darkened where they overlap.
- **Same ink as Flutter**: `WetInkModel.kt` is a line-for-line port of the
  Dart model the Ink Lab measures (`ink/lab/wet_ink_model.dart`), which
  applies the outline's own rules — point thinning (`PointSpacing`), the
  pressure curve and filter, the causal radius smoothing, the start and
  tip rules,
  the pen-down and pen-up hooks (`HookFinder`), the dot rule and the
  shaper's position smoothing — in screen pixels (a view is a translation
  and a uniform scale, so the rules scale with it). Each piece is the hull
  of two circles; with flat ends, the pieces in an end's zone (the
  stroke's start, the moving tip) are flat nib sweeps cut off at the butt
  cap's line, as Flutter's flat ends are (`WetInkEnds`), and the tail
  starts two widths before Flutter's shown tip, whose zone has less ink
  than the line will have there. With the stabiliser on, it draws what Flutter's live
  ink does: only the final, smoothed line (the shaper's `finalCount`,
  ported), from where Flutter's shown frame ends (the lag reach before
  its newest input), and no predicted tip or line to the raw sample
  (`WetContact.predicts`) — the smoothed line, as soon as the smoothing
  allows. Two checks keep the ports equal: a shared golden
  (`test/inklab/wet_ink_golden_test.dart` writes/compares
  `android/app/src/test/resources/wet_ink/`, `WetInkModelTest.kt` checks
  the Kotlin model against it: `tool/wet_ink_check/unit_test.sh`, or
  Gradle `:app:testDebugUnitTest`) and
  `tool/wet_ink_check/check.sh` (every Ink Lab case and recording, equal
  to ≈ 1e-13).
- **Prediction** (`WetInkTip`, `WetInkPrediction`): androidx.input's
  `MotionEventPredictor` (Android's own predictor where the device has
  one, else a Kalman filter) extrapolates the pen; `WetInkPrediction`
  (pure Kotlin) draws only a short, cautious piece of it, at the tip's
  radius: points at most 15 ms ahead, no further along them than the recent
  speed covers in 15 ms, 12 tip radii, or the length over which a straight
  line leaves the current curvature by 0.4 radius; scaled smoothly to
  nothing while the pen slows down, turns (15–45° between the last two
  8 ms windows), lifts (pressure falling or low) or the predictor has just
  missed (the samples landed 1–3 tip radii from the prediction kept about
  a frame earlier), and none in the first 16 ms. The pen-up's frame has no tip at all (no prediction, and no line
  to the raw pen-up sample, which could draw a pen-up hook the model cut).
  Predicted points are only drawn, never stored; each event replaces them
  (in reused buffers). With the stabiliser on (`WetInkModel.stabilised`)
  `WetContact.predicts` is false: the whole tip is off (only the model's
  ink is drawn). Measured by replaying the Ink Lab
  recordings: `docs/INK_LAB.md`, *Low-latency ink → Prediction*.
- **Only opaque pen ink** (`WetInkStyle`): the highlighter, translucent
  colours, the eraser, lasso, shapes, text and
  straightened strokes stay on the Flutter path, as do fingers and other
  platforms. Overlay and Flutter ink overlap, so only opaque ink can look
  the same where they do.
- **Hand-over**: Flutter keeps drawing the live stroke as before; the
  overlay only adds the part Flutter may not show yet. Dart reports after
  each built frame the newest input it contains (`progress`); the overlay
  keeps every point until 70 ms after that report (`SHOWN_AFTER_MS`;
  report to present measured 21 ms median, 41 ms p99, 48 ms at most), and
  the whole tail until 70 ms after `end` (sent after the frame with the committed
  stroke). Retracting earlier would open a gap; later only means more
  opaque ink lying exactly on Flutter's. Nothing is left behind: when no
  stroke needs it, the front buffer is cleared and hidden.
- **Pen-down**: while the S Pen hovers over a surface with the pen tool,
  Dart sends `arm` (how a stroke starting now would look, re-sent every
  150 ms), so the overlay draws from the first sample; `begin` (sent when
  the input controller starts the live stroke) confirms or restyles it,
  `skip` takes it back (a down that is not ink — another tool, a
  selection, a menu over the canvas: a global pointer route answers every
  stylus down no surface took). Unconfirmed after 150 ms, it is dropped.
- **Clip and transform**: `WetInkView` (Dart) gives the writing area — the
  surface less the chrome insets (toolbars), and on a page only the page,
  where committed ink is clipped too — and the view transform. A pan or
  zoom during a stroke (or straightening it) sends `cancel`: the overlay
  drops its ink at once and Flutter draws the stroke.
- **Lifecycle**: the layer is created at `onStart` (or the next touch) and
  follows the Flutter view; the renderer rebuilds its buffers on surface
  changes (rotation, split screen, resume). A pen-up Dart never ends is
  dropped after 1 s.

Markers for system traces (atrace app `dev.len.len`; event times are
`CLOCK_MONOTONIC`): `len.wet <eventTimeNs>` (recording a frame),
`len.wetDone <eventTimeNs>` (frame rendered), `len.progress <eventTimeNs>`.
`tool/wet_ink_check/latency_trace.cfg` (Perfetto) and `latency.sql`
(trace_processor) turn a trace into the latency table of `docs/INK_LAB.md`.

Resting the pen for 600 ms at the end of a stroke snaps it, in place
(`input/hold_to_straighten.dart` + `shapes/shape_recognizer.dart`). A real
S Pen at rest still reports samples drifting about a pixel: the rest
starts after the last place the pen was more than 4 screen px from where
it is now (it slows down first), the hold counts from there on the
events' clock, and only the stroke up to there is recognised (the drift
would make a line's detour or an arrow's wings). Open
strokes become an arrow (a straight shaft and a wing on each side of its
tip) or, if nearly straight already (no point off the chord by more than
8 % of it, the path at most 1.15 × the chord), a line whose end then
follows the pen; closed ones (ends within 30 % of the bounding diagonal)
an ellipse/circle or a polygon, whichever fits better: the polygon's
corners are RDP vertices (two closer than 10 % of the diagonal are one
rounded corner) moved to where the sides, fitted as lines, meet
(`Polyline.fitCorners`: a hand rounds corners off), less any corner a fit
with one fewer matches within 0.4 % of the diagonal (a bowed side, the
overshoot closing the loop: long rectangles stay rectangles), then 3 → triangle, 4
→ diamond (diagonals along the axes), rectangle (right angles; rotated or,
within 6°, axis-aligned, each side midway between its corners), else
polygon (five or more corners must have half the ellipse's error: a ring
around a word is no hexagon). Strokes under 48 screen px long and closed
ones under 48 px across stay as written (letters such as "l", "o" or
"0"), and handwriting, curves and scribbles are never recognised.
Snapped shapes have the shape look (`ShapeBuilder.styleFor`) and their
geometry (`LiveInk.shape` → `Stroke.shape`); only the clean shape is
committed. The recogniser is tested on hand-drawn samples
(`test/support/hand_shapes.dart`: rounded corners, bowed sides, gaps and
overshoots, landing hooks, tilt) and on simulated handwriting that must not
snap, and against the Ink Lab's real S Pen recordings: replayed as written
nothing snaps (writing never rests that long), every real stroke held
with the real pen's rest snaps only if it is a shape or a straight
stroke, and shapes drawn with real strokes' timing, pressure and jitter
snap (`docs/INK_LAB.md`, *Gestures on real ink*).

**Scribble to erase** (`input/scribble_detector.dart`, on by default, a
switch in Settings → Writing): a pen (ballpoint) stroke holding a fast
back-and-forth scribble — `ScribbleDetector`: two quick back-and-forths
(≥ 4 passes within 0.8 s), each nearly reversing the last, ≥ 14 screen
px, the inner ones at most twice the median, fairly straight, all in a
band at most 0.3 of their length wide (letters — cursive m / n / u / w,
printed z / N / M / w — reverse as sharply but move on), drifting pass by
pass rather than mostly in one jump (cursive "ll" goes up and down one
letter, then the next) — erases instead
of becoming ink when it crosses ink. Only the part that zigzags counts
(`ScribbleDetector.windows`: each run of passes that makes a scribble, its
outer passes cut to the span of the inner ones, overlapping runs joined),
so a lead-in or a run-on erases nothing. The detector looks every 4
points at the stroke's last 0.8 s only, so its cost doesn't grow with the
stroke. `SurfaceModel.eraseScribbled` (`ink/scribble_hits.dart`) removes
the strokes a zigzag touches that lie mostly inside its bounds (a long
line under a scribbled word stays) and are not an outline around it (a
stroke whose bounds hold the zigzag's, give or take 20 %, with no ink in
the zigzag's middle half: a checkbox being filled in), as one `InkEdit`.
Over blank paper it stays ink (shading); over text boxes or images only,
it is dropped and the editor says "Scribble erases ink only"
(`InkEvents.scribbleMissed`). A stroke hold to snap made a line or shape
is never a scribble (latched, as the pen-up clears `LiveInk.straightened`).
`ScribbleErase` (`input/scribble_erase.dart`) runs it for `InkDrawing`:
once the stroke so far holds a scribble it previews what will go
(`SurfaceModel.scribbled`, again only when the zigzags grew), hiding
those strokes as an owner (`setHidden`) and drawing them at 30 % as its
lifted content (fading in over 100 ms, frame callbacks only while
fading); the stroke ending any way un-hides them before the erase. It is
held to zero false positives on the Ink Lab's real S Pen recordings
(at 0.25–3× and up to 3× as fast, `test/real_ink_gestures_test.dart`),
simulated writing at 1–4×, cursive and printed zigzag letters and words at
many sizes and speeds, and zigzag hatching spaced a tenth of its length or
more (`test/scribble_detector_test.dart`); denser hatching over ink is a
scribble (the dimming shows it before anything goes; Settings turns
scribble to erase off).

**Text-aware highlighter** (`input/highlight_snap.dart`, set by paged
editors to `features/editor/pdf/PdfHighlightSnap`): always (it needs no
hold, whatever hold to snap is set to), a highlighter stroke of which
≥ 70 % runs along lines of PDF text (within 0.85 × a line's height of its
middle, ≥ 1.5 line heights along each line it counts, its middle on
average within 0.35 × the line's height of the line's middle or within
half the stroke's width, so an underline stays ink) is committed as the
clean highlights a selection's Highlight makes
(`PdfHighlights.stroke`, one per line) over the characters it covers,
widened to words it covers half of and trimmed off words it covers less of;
one undo step. Anything else (circles, margin notes, strokes across lines,
underlines, non-PDF pages) stays as drawn. Lines run any way a turned page
shows them (tested at 0°, 90°, 180° and 270°).

The lasso, shape, text and laser tools are `PointerTool`s
(`ink/tools/`): `InkInputController` hands them the drawing pointer
(after palm rejection / navigation / stylus-eraser routing) instead of
making ink. `ContentTools` bundles them with their shared state for one
editor; `features/editor/tools/ContentLayer` shows that state over the
surface.

## Editing tools

- **Shapes** are ordinary strokes whose points trace a clean outline at
  constant pressure (`shapes/shape_builder.dart`), so they render, erase,
  select and sync like ink, and that carry their geometry
  (`Stroke.shape`, `domain/shape_geometry.dart`: the kind and its control
  points — line ends, corners, vertices, an ellipse's centre and conjugate
  semi-axes, a star's frame and inner radius), so they stay editable.
  Every kind is described by points an affine map takes to the same kind,
  so moving, scaling and rotating a selection maps them
  (`TransformItems.stroke`); the pixel eraser's pieces are free-hand ink.
  A shape's look is the pen's colour, width and opacity as an even line
  with round ends (`ShapeBuilder.styleFor`: no pressure, taper, flat ends
  or stabiliser). The Shape tool (`tools/shape_tool.dart`) previews the
  shape from the press to the pointer on every move (Shift, pressed or
  released at any time: regular shapes — squares, circles, equilateral
  triangles, regular stars (`ShapeBuilder.regularAspect`) — and 15° lines) and commits exactly the shape
  last shown; a tap on a shape selects it. The live outline is rebuilt
  whenever the live points are replaced rather than extended
  (`LiveInk.generation`; the incremental builder would otherwise keep the
  outline of an earlier preview).
  **Fill:** a closed stroke (`Stroke.isClosed`: last point = first, as
  closed shapes are built) shows `StrokeStyle.fill` (ARGB, translucent for
  tints) beneath its outline as the polygon of its points
  (`StrokeRenderer.fillPathOf`; the PDF writes the same polygon). The
  Shape tool takes `ToolSettings.shapeFill` (`ShapeFill`: none, three tints
  of the ink, solid; `FillChoices`), the selection's Style sets it
  (`SelectionController.refill`; a tint follows a recolour). A filled
  stroke is indexed in every chunk its bounds cover; taps select it by its
  fill, erasers only take the outline (cut pieces are open, so unfilled).
- **Lasso** (`selection/`): its options (`LassoConfig` in `ToolSettings.lasso`,
  the Lasso popover, read at each press) set the shape (a freehand loop, or a
  rectangle dragged corner to corner: `LassoPath.rectangle`), how much of an
  item must be inside (`LassoCover`) and which kinds it takes (`LassoKind`:
  ink, which includes shapes; highlighter; text; images, with links). By
  default (*mostly*) a stroke is selected when at least half of its
  *length* is inside the lasso polygon (segments are subdivided and weighted
  by length, so sampling density does not matter); an element when its
  centre (or most of its outline) is. *Whole* needs every point inside and
  no segment crossing the outline; *touching*, a point inside or a crossing
  (an image beneath the ink is not touched by a lasso drawn within it). A
  tap selects the topmost item of the kinds taken. A rectangle that selects
  no ink and started on PDF text selects the text from corner to corner.
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
- **Editing a shape's points**: a single shape selected on its own surface
  (`SelectionController.shapeStroke`, by the lasso or a tap — with the
  lasso, or the Shape tool on a shape) shows its control points as handles
  instead of the frame's resize handles (`ShapeHandles`,
  `SelectionChrome.shapeHandles`: line and arrow ends, rectangle and
  diamond and triangle corners, polygon vertices, an ellipse's bounding
  corners, a star's five points — turning and sizing it about its centre —
  and a small solid dot setting its inner radius). Rectangles and
  ellipses keep their side directions (the opposite corner stays); lines
  and arrows have no frame (their ends move and turn them; Shift: 15°)
  and move only from near the stroke (`SelectionChrome.grabs`), closed
  shapes keep the rotate handle; Shift on a rectangle's or ellipse's corner
  keeps its proportions. A turned rectangle, ellipse or star gets a frame
  turned with it (`ShapeHandles.angleOf`, `SelectionFrame.around`), so the
  handles sit on it. Handles are 6.5 px knobs like the frame's, reached
  within `SelectionChrome.shapeHitRadius` (24 px, a fingertip; inside a
  small shape's frame less, so it still moves by its middle; the rotate
  handle wins when nearer), grabbed where they are (no jump). Dragging one (`LassoTool`, mode reshape) shows the shape
  rebuilt (`ShapeBuilder.reshaped`: outline 2 px apart at its zoom, same
  look and fill) as the selection's picture; the release commits it as one
  `InkEdit` (remove + add, so it syncs), keeping it selected. During moves
  and rotations the handles follow the preview transform.
- **Selections across pages** (paged notebooks, continuous flow): the
  selection stays bound to the active page's surface, but
  `SelectionController.surfaces` (a `SelectionSurfaces`, given by
  `DocumentSelection` from the document layout) lets it reach the other
  pages. `SelectionReach.pick` moves the lasso into each overlapping page's
  coordinates (`Lasso.shifted`) and selects there too; items of other pages
  are held as copies moved into the active page's coordinates, with a
  `SelectionSource` (page model, shift, stored original) per id, and are
  hidden on their own page (a page holding hidden items is never released,
  `PageSurface.pinned`). Every edit goes through a `SelectionPlan`, which
  sorts removals and additions by page and converts items back into each
  page's space; on a move (`commitPreview`), duplicate and paste each item
  goes to the page under its centre (on no page: where it was), so dropping
  a selection on the next page moves it there — strokes are re-added,
  elements keep their id and are re-parented (all removals are committed
  before any addition, so storage and sync see a re-parent). Edits on
  several pages run in `PageModels.group`: one notebook-wide undo step that
  undoes each page's part backwards and redoes it forwards. The selection
  picture is clipped to all page frames (not just the active page), so it
  shows on every page it covers and while dragged between pages. With one
  page laid out (single-page flow) nothing else is reachable. A page that
  goes (deleted here or elsewhere) first drops a selection reaching onto
  it; a disposed `SurfaceModel` ignores edits.
- **Text** (`elements/text_edit_session.dart`): tapping with the Text tool
  creates or edits a box; double-tapping a box with the lasso edits it too.
  While editing, the element is hidden and a real `TextField` is laid out
  in world units and transformed by the viewport — `TextLayout` gives the
  field and the renderer the same complete (non-inheriting) styles, so text
  wraps identically while edited and once committed. The whole session is
  one undoable edit (an emptied box is deleted). See *Text boxes*.
- **Laser pointer** (`tools/laser.dart`, `render/laser_painter.dart`,
  `render/laser_ribbon.dart`, `features/editor/tools/laser_overlay.dart`): `LaserTrail` keeps
  the samples (at least 1.5 px apart on screen; the dot follows every one) in a fixed-size ring
  buffer of typed arrays, stamped with frame time; `LaserOverlay` owns a `RepaintBoundary`, a
  `CustomPaint` repainting from the trail (no widget rebuilds) and a ticker that runs only while
  something is visible. `LaserPainter` draws, in screen space, a centripetal Catmull-Rom curve
  through the samples as two vertex meshes with per-vertex colours (`LaserRibbon`: a wide soft
  glow, a bright core whitened in the middle — lanes transparent at the edges, so no blur
  filter), narrowing and fading with age (smoothstep), plus a radial-gradient dot at the pointer.
  `LaserConfig` (in `ToolSettings`, persisted): dot or trail mode, colour (six presets or
  custom), size and when the trail fades (`LaserFade`): each point a set time after it was
  drawn (0.3–3 s), or, *when I stop*, all of it together once `hold` (0.5–5 s, default 2 s)
  has passed since the last lift (`LaserTrail.holding`: the trail and dot stay in full while
  writing, a press within the hold keeps everything, then a 400-ms fade; frames during the hold
  repaint nothing, and a hovering mouse doesn't stop the countdown; the same with a mouse,
  pen or finger and presenting with F5, `test/laser_hold_input_test.dart`). Set in the tool's options
  popup (`LaserOptionsPanel`, with a live preview). The old painter drew two lines per sample, one
  with a blur mask filter — hundreds of blurs per frame; `test/perf/laser_perf_test.dart`
  measures a move (0 rebuilds, 1 paint) and a full trail against it.

`InkEdit` carries strokes and elements; merging cancels intermediate
values on both, so undo/redo and sync treat text and ink alike.

## Text boxes (`domain/text/`, `ink/elements/`, `features/editor/tools/text/`)

GoodNotes-style rich text inside a box.

- **Model** (`domain/text/`): `TextData` keeps the **plain text** whole (lines
  split by `\n`; the search index reads it directly), character formatting as
  normalised `StyledRange`s of `SpanStyle` (bold, italic, underline,
  strikethrough, colour, highlight, size, font; unset = the box default), one
  `ParaStyle` per line (heading 1/2, bullet / numbered / checklist item with
  indent level, ticked) and the box defaults (`TextFont`, size, colour,
  alignment, `autoWidth`). Stored compactly (see SYNC_PROTOCOL). Editing logic
  — inserting, joining and splitting lines (lists continue, headings do not),
  numbering — is pure Dart in `RichTextBuffer`, unit-tested without Flutter.
- **Fonts** (`TextFont`, `assets/fonts/`, built by `tool/build_fonts.py` from
  Google Fonts and subset to Latin/Greek/Cyrillic + symbols): Inter (sans),
  Lora (serif), JetBrains Mono and Caveat (handwriting; no italic, it is
  slanted), all SIL OFL 1.1 with their licence files, registered in the licence page
  (`core/font_licenses.dart`). Boxes use only bundled fonts, so they measure and
  wrap the same everywhere and in exported PDFs; characters they lack fall back
  to system fonts.
- **Layout** (`ink/elements/text_layout.dart`): `TextLayout.spanOf` builds one
  `TextSpan` tree; list markers are **inline placeholders** at the start of their
  line (one U+FFFC each), sized by indent level, so bullets, numbers (1. / a. /
  i. by level) and checkboxes take part in wrapping and alignment identically in
  the canvas (`TextBoxLayout` paints them via `ListMarker`), the editor
  (`WidgetSpan`s) and PDF export. **Hanging indents**: a paragraph cannot
  indent its wrapped lines, so `TextWraps` wraps each list item on its own at
  the box width minus its marker column; the laid-out text then gets, at each
  of those offsets, a line break plus a gap placeholder as wide as the marker
  (`MarkerOffsets.wrapText`), so continuation lines start under the item's
  text at every level. Canvas, thumbnails, PNG and PDF export (via
  `TextBoxLayout`) and the editing field (`RichTextController.wrapWidth`, set
  to the box width; auto-width boxes never wrap) share that layout. The caret
  steps over the gap; backspace at a continuation line deletes the character
  before. `MarkerOffsets` maps text offsets to laid-out offsets
  (`marker_offsets.dart`). The editing field disables the strut, so headings
  keep their line height while editing.
- **Editing** (`features/editor/tools/text/`): `RichTextController` (a
  `TextEditingController`) renders the spans and maps the field's edits back
  onto the buffer (common prefix/suffix diff, the caret disambiguating repeated
  characters); the field's text is the laid-out text with placeholders, which
  the caret steps over. Backspace after a marker removes the list, Enter on an
  empty item ends it. Formatting acts on the selection, or with a collapsed caret
  on what is typed next; in an empty box font, size and colour set the box
  defaults (remembered as the default text style, also in the Text tool's
  settings). Copy / cut put the plain text on the clipboard and remember its
  formatting, so pasting the same text into a box (or onto the canvas) keeps it.
  `TextFormatBar`: font, size, B / I / U / S, colour, highlight, paragraph style,
  bullet / numbered / checklist, alignment (scrolls on phones; delete and done
  stay). Shortcuts: Ctrl/⌘+B / I / U, Ctrl+Shift+X strikethrough, Ctrl+Shift+7 /
  8 / 9 lists, Ctrl+Alt+1 / 2 headings (Ctrl+Alt+0 body), Tab / Shift+Tab indent,
  Ctrl+Enter ticks, Esc finishes.
- **Size**: new boxes are **auto-width** (as wide as their text, growing up to
  the screen edge, then wrapping there); dragging a side handle sets a width and
  wraps from then on. Lasso corner scaling scales every size in the box.
- **Checklists**: ticking (tap the box while editing, or with the Text tool on a
  committed box, `TextHitTest`) is undoable; ticked items are struck through and
  faded.
- **Lasso**: *Style* (`selection_style_panel.dart`) changes font and size of the
  selected boxes and pen type / width of selected ink (`SelectionController
  .restyleText` / `restyleInk`, one undo step each); *Colour* recolours all text.
- **Paste**: Ctrl+V on the canvas with plain text on the system clipboard (newer
  than ink copied in the app) adds a selected text box at the screen centre.
- **Rich paste from other apps**: `textFromHtml` (`domain/text/html_text.dart`,
  pure Dart over a small tolerant tokenizer, `html_tokens.dart`, and inline-CSS
  reading, `html_css.dart`) turns clipboard HTML into a box's `TextData`: b /
  strong / i / em / u / s / del and `font-weight` / `font-style` /
  `text-decoration` styles (the style wins, so Google Docs' wrapping
  `<b style="font-weight:normal">` is not bold), colours and highlights that are
  not grey (so a web page's own black / white / theme colours are dropped),
  code / pre as mono, h1 → heading 1, h2 / h3 → heading 2, ul / ol / li nested
  → list indent (or Google Docs' flat `aria-level`, Word's `mso-list … levelN`
  paragraphs with their `<![if !supportLists]>` marker deciding bullet or
  number), checkbox inputs / ARIA checkboxes → checklist, one line per block,
  browser whitespace collapsing, entities; `<head>`, style and script are
  skipped and the Windows CF_HTML header / `StartFragment` markers cut. Sizes
  and fonts stay the box's. `RichTextBuffer.insertRich` inserts it at the caret
  (the caret's font, size and colour where the fragment sets none; the first
  line keeps its paragraph style unless the paste fills it). Ctrl+V in the
  editing field (`RichPasteAction` overriding `PasteTextIntent`, and the
  context menu's Paste) and on the canvas (`EditorImages.paste`) use it when the
  clipboard has HTML and its text is not what was last copied from a box here
  (that keeps its remembered formatting); otherwise plain text as before. Undo
  is the box edit's / new element's. Ctrl+Shift+V pastes plain text.
  HTML comes from `platform/clipboard_html*`: **Windows** CF_HTML, **Android**
  `ClipData` HTML text (both via `pasteboard`), **Linux** `text/html` (added to
  our vendored `pasteboard`; UTF-16 from Firefox decoded), **web** the
  capturing `paste` event's `text/html` (a browser paste into the editing field
  is matched by its plain text in `RichTextController._applyEdit`; Ctrl+Shift+V
  there is the browser's plain paste) or else the async Clipboard API (may ask
  for permission). macOS / iOS are not targets (`pasteboard` returns no HTML
  there). RTF-only clipboards (WordPad) paste as plain text.
- **Export**: `PdfTextWriter` writes boxes as real text in the embedded
  (subsetted) fonts, each word at the position the app's layout gives it, with
  vector highlights, decorations and markers; boxes with characters the bundled
  fonts lack are embedded as images. PNG export and thumbnails use the canvas
  renderer.

## Pens (`ink/pen/`, `ink/render/`)

The toolbar offers exactly two inks — the **pen** (`InkTool.ballpoint`) and the
**highlighter** — plus the eraser. A stroke's look = its `InkTool` + its
`StrokeStyle`:

- **`PenDefaults`** (pen, highlighter): default colours, widths, feel settings
  and the width range offered in the UI.
- **`StrokeStyle`** (per stroke, stored in `strokes.style` and synced as
  `data.style`): opacity, thinning (pressure sensitivity), streamline
  (stabiliser), the zoom it was written at (`unit`), and end shape (round,
  flat or tapered, with independent start/end lengths in stroke widths);
  required and parsed
  strictly (as is the tool: an unknown one makes the stroke malformed). So
  a stroke renders identically on every device, whatever the local tool
  settings.

**One engine for both inks.** The highlighter is the pen's engine (sampling,
smoothing, stabiliser, outline, `StrokeStyle`; `StrokeRenderer.specFor`
reads only the style) with what makes it a highlighter on top: translucent
(one even layer where it crosses itself), drawn before other ink in each
chunk picture (the live stroke on a layer beneath committed ink), straight
lines on offer, snapping to PDF text, and flat chisel ends by default.
`PenDefaults.endStyles` lists the ends each offers: the pen round, tapered
or flat; the highlighter flat or round (a taper makes no sense for a
translucent band; parsing rejects it). Highlights a PDF selection makes
are always flat (`PdfHighlights`: the band ends where the text does).

User customisation lives in `ToolSettings`, persisted as JSON in the local
`settings` table: per ink a `PenConfig` with **independent quick colours and
quick widths** (1–5 slots each, one of each selected) and feel settings
(pressure sensitivity, stabiliser, ends, straight lines; opacity for the
highlighter — the pen is always opaque), plus eraser options,
hold-to-straighten and the 8 **recent colours** (`RecentColors`: colours
newly put into an ink's quick slots or given to text or the laser, noted when
the tool options popover closes, and colours picked with `pickColour`; shown in
the popovers' colour block and in the selection's Style colours). Stroke
widths are shown as millimetres on the page (`formatWidth`: world units are
96 per inch, so "0.65 mm" is the printed size and the size at 100 % zoom;
below 1 mm they round to 0.05 mm).
Parsing is strict (`PenConfigJson`,
`EraserConfig.fromJson`): a part with a missing or invalid field keeps its
defaults as a whole.

The ink panels (`features/editor/pen/`) are self-contained:
`PenOptionsPanel` (live preview, pressure sensitivity, stabiliser, ends)
and `HighlighterOptionsPanel` (preview, opacity, pressure sensitivity — off
by default —, stabiliser, ends: flat or round, straight lines); on their
own, their Reset restores the feel settings. The writing
gestures hold to snap and scribble to erase are app preferences
(`AppPreferences.holdToSnap` / `scribbleToErase`), whose one home is
Settings → Writing beside "Tap to undo and redo"; the editor mirrors them
into `ToolSettings` (not saved with the tools). The Shapes popover points
there, and the eraser panel mentions scribbling while it is on.
The preview (`StrokePreview` / `PreviewCard`, `pen/stroke_preview.dart`)
draws with the real renderer at the real size and colour on the paper the
user writes on (`InkPaper`, provided by the editor chrome from the current
page's colour and carried into popovers; ink and paper are not themed, so
it looks the same in dark mode, framed by a hairline): two joined-up words
with a hand's pressure (`pen/preview_strokes.dart`) on a faint rule for the
pen, a highlight over three grey lines of "text" for the highlighter, one
gentle stroke for a size on its own. The
tool options popover hosts them unchanged under *Feel* (`InkOptions`,
`pen/ink_options.dart`), inside an `EmbeddedOptions` scope that makes
their title row (`FeelHeader`) and `PreviewCard` step aside, since the
popover shows its own above: so a setting added to a panel shows up in the
popover with no other change. The
stabiliser shows "Off" at 0 (the pen's default: ink under the nib) and up to
100 % (the live ink then trails the pen by ~6–15 px). **Straight lines**
(`PenConfig.straight`, offered for the highlighter): every stroke is the line
from pen-down to the pen — `HoldToStraighten.begin(straight: true)` makes
the live stroke straight from its first point, like a held line, so it
stays on the Flutter path (no low-latency overlay) and is committed with
stabiliser 0 (`PenConfig.styleFor`); the stabiliser and hold to snap are
greyed out meanwhile.

### Toolbar (`features/editor/`, `toolbar/`)

`EditorToolbar` is built from `ToolDescriptor`s (`editor_tools.dart`, a fixed
order): icon, label, shortcut, ink colour, a quick-control *strip* (with its
width) and its section of the options popover. More tools slot in by adding an
`EditorTool` value and a descriptor. The tools are Pen (P), Highlighter (H),
Eraser (E), Lasso (L), Shapes (S; its icon is the current shape), Text (T) and
Laser pointer (K), then **Insert ⊕** (`toolbar/insert_menu.dart`; a button, not
a tool: Image…, Take photo on Android, and in notebooks Pages from PDF…; a page
with a template is "Add page after" held down in the page menu).

- **`ToolCluster`** (`toolbar/tool_cluster.dart`): the tool buttons in fixed
  cells (44 dp with a pointer, 48 on touch) over one neutral `xs` plate
  (`Surfaces.pressed`) that slides to the active tool in `Motion.fast`.
  Inking tools show their colour as a bar under the glyph. Tap selects; tapping
  the active tool, a long press or a right click opens its options.
- **`ToolStrip`** (`toolbar/tool_strip.dart`): the active tool's quick
  controls, cross-fading as it changes: Pen and Highlighter, their **colour
  slots then width slots** (`pen/ink_strip.dart`; 3 + 3 by default, 1–5 each,
  independent); Eraser, three size slots; Shapes, the pen's slots (the kind
  is picked in its options; the Shapes button shows it); Laser, three colour
  slots (red, green, blue); Lasso and Text, none.
  Slots (`pen/slot_button.dart`) are 22-dp swatches or neutral dots at real
  size (4–20 dp) in 36-dp cells (44 on touch); the selected colour gets a
  2-px `onSurface` ring with a 2-px gap, the selected size (and eraser size)
  the neutral `Surfaces.pressed` plate, so the two never look alike. Tapping
  the selected pen or highlighter slot, a long press or a right click edits
  that slot alone (`pen/slot_editors.dart`, anchored, a compact sheet on
  phones): a colour slot the palette, Recent and Custom; a size slot a
  logarithmic mm slider with a live preview. The ink's full options open
  from its tool button only. (Eraser and laser slots still open their
  tool's options.) Picking a quick colour or width from a tool that draws
  no ink switches to the pen.
  Phones show the previous tool beside the switcher (`PreviousToolButton`,
  `ToolSettings.previousTool`, the eraser at first): one tap swaps them. When a
  stylus is in use and its side button erases (`penButtonErases`), the slot skips
  the eraser and starts at the highlighter: pen ↔ highlighter is one tap.
  The slots give up to 4 dp of their 44-dp cells for it (`ToolbarDensity.slot`)
  and it steps aside when they would go under 40 (narrow phones, 5 + 5).
- **One options popover** (`toolbar/tool_options_popover.dart`,
  `showToolOptions`): `showAdaptivePopover`, anchored and 320 dp wide (368
  on touch: seven 48-dp swatch cells), a
  sheet on phones (the sheet covers the toolbar, so only it repeats the
  quick slots); the body scrolls with a fading edge (`ScrollFade`); edits
  apply live. Every section starts with its title and Reset (`OptionHeader`,
  `ResetButton`: every setting the section shows back to its defaults, then
  Undo until something else changes; none where there is nothing to reset)
  and picks colours with one block,
  `ColorChoices` (`ui/color_picker/color_choices.dart`: "Colour" with Custom,
  which opens the HSV picker in place, a palette, recent colours). Sections:
  inks (`InkOptions`: live preview, the selected slot's colour — the pen
  palette, or `ColorSwatches.highlighter`'s light hues — and Size, a
  logarithmic slider in mm, then *Feel* collapsed (the header's Reset resets the feel only and
  keeps the quick colours and sizes),
  then *Quick colours and sizes* collapsed ("3 and 3": "Quick colours / Quick
  sizes − n +"); the pen palette is 2 × 7 (`ColorSwatches.palette`, holding
  the pen and text defaults), the highlighter's 2 × 5); `EraserOptionsPanel`;
  none for the lasso (`ToolDescriptor.options` null: tapping it again does
  nothing; a one-time tip explains it); Shapes (`ShapeOptionsPanel`: seven
  kinds in one row, the fill (`FillChoices`), and a caption pointing to hold to snap in Settings →
  Writing, or saying it is off there);
  `TextOptionsPanel`;
  `LaserOptionsPanel` (`ToolSettings.laser`: dot / trail, colours, size,
  trail length). `pickColour` (`tools/colour_sheet.dart`; text and
  selection colours) is a popover too: no Apply, it previews live and
  closing it keeps the last colour picked.
- **Where it goes** (`ToolbarDock`, decided by `ToolbarMeasure.dockFor` from
  the *pane's* width, so split panes lay out on their own): with
  `ToolbarPlacement.docked` it sits **inside the top bar** when the bar fits
  it on one row (`ToolbarMetrics.oneRow`: navigation with a 120-dp title,
  the tools, the reserved strip, the actions; about 1 040 dp), centred when
  the clusters beside it have room; else in a **48-dp row attached under the
  bar** (tools centred, the strip after them; short of room, as in a split
  pane on touch, its cells shrink to the 40 / 36-dp visuals through
  `ToolbarDensity`, and shorter still the strip scrolls); in panes under 600 dp in a
  **56-dp bottom row** (`ToolSwitcherButton` `[✎▾]`, whose popover is a 4 × 2
  grid of the tools and Insert, then the strip, scrolling if needed). With
  `ToolbarPlacement.floating` (⋯ → View, its only home) it is a
  `raised` palette dragged by its grip (`ToolbarSlot`; it covers no edge).
  The strip's width is reserved at its widest across tools, so switching
  tools moves nothing and never changes the layout.
- **Rebuilds**: the cluster, strip and switcher listen to `ToolSettings`
  themselves; the chrome host, top bar and canvas never rebuild on a tool
  change (`test/toolbar_test.dart` counts rebuilds). `ToolbarMeasure`
  notifies only when the reserved strip width changes (slots added or
  removed), which may move the toolbar between the bar and its row.

Shortcuts: P / H / E / L / S / T / K, 1–5 colour slots, [ / ] thinner /
thicker (plus the canvas keys `+` `-` `0` Shift+1 Home Shift+M). Palm rejection is
automatic (on at the first stylus contact); "⋯" → *Draw with finger* turns it
off once a stylus has been seen.

### Ink rendering (`ink/render/`)

Every pen stroke — live and committed — goes through one pipeline with a
**fixed reach**: ink further than a few pen-widths behind the tip of a stroke
in progress is *final* (bit-identical in every later frame and in the
committed stroke), so nothing behind the pen moves, and the cost per frame
does not grow with the stroke's length.

1. **Points** (`input/ink_input_controller.dart`): samples closer than
   0.75 screen px to the last point are dropped, except the extreme of a
   dropped run (a cusp tip, `PointSpacing`); stylus pressure goes through
   the `PressureCurve` (`4p / (3p + 1)`: handwriting presses lightly, so
   device pressure 0.2 is medium, the pen's nominal width; fingers and the
   mouse are 0.5, medium too) and is filtered (`PressureFilter`); the
   overlay's Kotlin model applies the same. A **mouse** reports whole
   pixels (web, desktops), a staircase that zoomed out — the pen a fraction
   of a pixel wide on screen — showed as squiggles the outline's smoothing
   (bounded relative to the pen's width, which keeps its geometry exact)
   cannot level; so when the pen is under 2.5 px wide on screen its path
   is first resampled every pixel and smoothed with a centred Gaussian in
   screen space (`MouseSmoother`: what the outline lacks, up to 2 px for a
   hairline, trailing the mouse by at most 6 px like the stabiliser, the
   ends where the mouse went down and up). Wider pens (the default at 100 %)
   get the mouse's positions unchanged, without lag
   (`test/mouse_zoom_smoothness_test.dart`).
   **Ink shows from the first sample**, under the nib
   (latency beats purity): every contact is drawn from pen-down, even one
   that turns out to be a bounce (`BounceFilter.isBounce`, decided at its
   lift: it showed as a dot where the pen just lifted for < 80 ms and is
   not committed), and the pen-down hook is trimmed retroactively (below).
2. **Unit** (`StrokeStyle.unit`, `StrokeOutline.unitOf`): digitiser jitter
   and hooks are screen-sized, so the outline smooths in screen units. The
   controller records the world size of a screen pixel (1 / zoom) in the
   stroke's style at pen-down, so a stroke written zoomed in 7× is smoothed
   7× finer in world units, from its first frame on (and a stroke scaled
   by the lasso is smoothed as if written at that zoom). Strokes without it
   (shapes, older data) estimate it from the spacing of their first points
   (the controller keeps points ≥ 0.75 screen px apart); that estimate is
   often 20–60 % off, so pen strokes do not use it.
3. **`StrokeShaper`** (incremental; each stage looks a fixed number of
   samples ahead and keeps what is final):
   - dedupe; the **pen-down hook** is decided once from the first few
     screen px (`HookFinder`: a short end piece meeting the body at a
     *local* kink, ≤ 3 px for the start, ≤ 4 px for the end, whatever the
     pen; curves that merely start or end the stroke are kept). Until then
     the line is *provisional*: computed from the first sample, nothing of
     it final, rebuilt each frame (a few px, so cheap). If a hook is found,
     its ≤ 3 px of ink disappear once, under the nib, 1–6 frames after
     landing (about 20 % of real strokes); otherwise nothing changes;
   - **resampling** every `step` (≈ σ/3, 0.15–0.6 screen px) along a
     centripetal Catmull-Rom spline through the points, from the stroke's
     start, so samples never move as the stroke grows. A piece cut out by
     the pixel eraser (`geometry/stroke_splitter.dart`) keeps the
     original's phase (`StrokeStyle.startPhase`), and its cut ends trim no
     hooks (`cutEnd`), so the rest of the ink stays where it was;
   - **corners**: where the line turns by > 100° within a short baseline
     (cusps of `n`, `v`); the corner is the run's tip (the sample furthest
     along the direction the line came in from, not the sharpest turn,
     which can lie a sample past it); smoothing never crosses them;
   - **positions**: the finite low-pass `(1 + a)G − aG∘G` (`LineFilters`)
     per stretch between corners, each stretch continued beyond its ends
     by a local quadratic fit (no lag, tips stay put). σ grows from 0.7
     screen px at stabiliser 0 to 4 px at 1 (`ShapeParams.sigmaFor`; a
     little more for wide pens): never 0, so at stabiliser 0 the
     digitiser's sub-pixel jitter is still removed. The sharpness a goes
     from 1 (flat response: curves barely shrink) at stabiliser 0 to 0.25
     (nearly the plain Gaussian, which takes out more of a shaky hand's
     wobble for the lag it costs) at 1 (`sharpnessFor`);
   - **radii**: causal (two cascaded exponential passes over the resampled
     line, then a slope limit), so final as soon as their sample is; the
     start does not swell and is levelled; the moving tip follows the same
     end rules within a short reach. Ends are round caps at the width
     the pressure gives (or flat: the highlighter's default).
4. **`RibbonEmitter`**: the outline is the envelope of the circles along
   the line. A *run* of samples becomes **one closed contour** — left side
   forward, a cap, right side back, a cap — whose sides are cubic Béziers
   fitted to the offset points (within 0.002–0.004 world units, tangent at
   every join), so edges are smooth at any zoom and a whole stroke is a
   handful of contours (2–24 sub-paths in the Ink Lab cases, against
   thousands of capsules before). Runs end where the envelope would fold
   (corners, bends tighter than the radius); such segments are exact
   capsules (`capsule_emitter.dart`). All contours wind the same way, so
   the non-zero fill unions them (and one translucent highlighter stroke
   is one even layer where it crosses itself: every renderer fills a
   stroke as one path). Runs are cut at fixed sample indices
   (`block`, ≈ 24 screen px), so pieces can be frozen. **Flat ends**
   (`flat_ends.dart`; the highlighter, the pen's flat ends) are square to
   the smoothed line; near them (the samples whose circles touch the
   end's) folds are the area a flat nib sweeps between cross-sections
   instead of round capsules, and the stretch running the end's way is
   cut off at the end's line (`HalfPlaneClip`), so tight curls do not
   round the end off. A live stroke's moving tip is such an end too, so a
   flat pen's tip is square in every frame, as its committed end will be.
5. **Live stroke** (`live_stroke.dart`, `LiveStrokeBuilder`): per frame,
   only new points are fed to the shaper; pieces that became final are
   appended to a **frozen path** once, and only the **tail** after them is
   rebuilt (≈ 20 µs per frame on desktop, flat with length; with flat
   ends nothing within two widths of the tip, its end's zone, is frozen).
   The tail starts with a round cap inside the frozen part, so opaque ink fills
   the two without a seam (`LiveInkPainter`); translucent ink fills one
   combined path. **With the stabiliser on** (> 0) live ink shows only
   the final line (`StrokeShaper.liveLength`, `ShapeParams.lag`): it
   trails the pen by the reach of the smoothing (kernel, corner test and
   resampling: ≈ 6 px at 0.2, 10 px at 0.4, 15 px at 1) — the least the
   smoothing needs — instead of drawing a
   provisional tip that wags into place; the first sample shows as a dot
   from pen-down, and at pen-up the end catches up with the pen. At 0 the
   live line reaches the pen, as below.
6. **Commit** (`LiveStrokeBuilder.finishLive`): at pen-up the shaper rolls
   back to a recent **checkpoint** that does not depend on the last
   samples, and completes from there with the pen-up hook trimmed and the
   last pressures settled; the frozen part is reused. Pen-up handling
   takes 0.2–1.5 ms on the Ink Lab's cases and recordings and 1–3 ms on
   its 8 s stroke (desktop, JIT; noisy), and
   the committed outline equals the last live frame except at its very
   end. Committed outlines are memoised per stroke (`StrokeRenderer.adopt`).

`OutlineSink` lets tests record the exact segments; `test/ribbon_exactness_test.dart`
checks that the fitted contours cover what the circles cover, and
`test/live_stroke_test.dart` that live frames and the committed stroke agree.
Specimens of synthetic 240 Hz handwriting are rendered at 1×–16× in
`test/ink_specimen_test.dart`.

### Ink Lab (`ink/lab/`, `features/inklab/`, `test/inklab/`)

Input recordings (`.leninput`), a frame-by-frame replay through the real
input pipeline, quality metrics against a simulated S Pen's ground truth and
real recordings, an opt-in visual report and a hidden on-device recording
screen (Settings → About, tap the version 7×). The engine above passes
every metric on every entry (`known_failures.dart` is empty). See
[`INK_LAB.md`](INK_LAB.md).

## Erasing

`SurfaceModel.eraseAlong` either removes whole strokes or, in *pixel* mode,
cuts the ink under the eraser out (`geometry/stroke_splitter.dart`): the stroke
is removed and its surviving fragments are added as new strokes (keeping the
original `createdAt`, so paint order is unchanged). One drag is one undoable
`InkEdit`; fragments cut and erased again within the drag cancel out.
Optionally only highlighter ink is erased. The Eraser tool stays the tool
after an erase stroke; quick erasing comes from the S Pen side button and the
eraser end (temporary), the phone's previous-tool slot and the one-tap tablet
bar. Both modes test against the ink as
rendered: its radius at each point depends on pressure, thinning and the pen's
easing (`StrokeHitTest.inkRadius`), not just the nominal width.

## Persistence

`package:sqlite3` (bundles SQLite via build hooks on every platform).
`InitialSchema.create` creates the whole schema (`PRAGMA user_version`
1). Later schema changes append a migration to `SchemaMigrations.all`;
once released, never edit one.
After migrating, `SchemaCheck` (`data/schema_reset.dart`) compares the
database's shape (tables with their columns, index and trigger names; the
optional FTS index aside) with that of a freshly migrated in-memory
database. A newer `user_version`, a failing migration or a different shape
(pre-release migrations were rewritten) resets the database: the file is
copied to `<path>.schema-<version>-<time>.bak` (native only), everything is
dropped and recreated, the sync login is carried over (the server URL and
the token's secure-store slot, or the token while it is in the database; so
synced notebooks come back), and the library says so once
(`AppDatabase.schemaReset`).
All writes go straight to SQLite; in-memory state is a cache.
`AppDatabase.select` / `execute` keep up to 64 prepared statements (LRU) for
constant SQL; the sync and chunk-index hot paths use them (preparing costs
about as much as running a small statement). Scale budgets and numbers:
[`PERFORMANCE.md`](PERFORMANCE.md).

### Len files and backups (`data/archive/`, `features/backup/`)

A notebook, a folder or the whole library can be written as a Len file
(`.len`, a zip of sync records and blobs; format in SYNC_PROTOCOL.md, "Len
files"). `LenArchives` (`AppServices.lenFiles`) writes a `LenScope` through
`LenArchiveWriter` and imports through `LenArchiveReader`: records go out in
~4 MB parts and blobs one at a time, read natively straight from their files
(`platform/len_file_io_native.dart` opens them as `InputFileStream`s and
checksums them in a worker isolate first, `fileCrc32`, so the zip encoder only
copies them; in browsers the encoder checksums each as it writes it); blobs
not downloaded yet are fetched first through sync where it can. The file is
never held in memory whole (`createLenFileOutput`): desktops ask where to
save first and write there (a `.part` file until done), phones write a
temporary file to share or save, browsers write through the save picker
(`showSaveFilePicker`, streamed via `ChunkedOutput`) where there is one,
else into a blob of 4 MB chunks to download, and warn before backing up
more than 500 MB of files. Browsers read a picked file in slices
(`RangedInput` over `Blob.slice`; `RangedZip` loads the zip's structure
first, then each entry as it is read), natively it is read in place;
browsers inflate a records part with their `DecompressionStream`
(`platform/browser_inflate`, off the UI thread; the archive package's
inflater in Dart took seconds of it), and records are parsed and written in
8 ms slices, a transaction each, with a turn of the event loop between them
(`LenArchiveReader.sliceBudget`). An
import opens the file (`LenSource`: the
manifest and, for a backup, the folders and notebooks it holds), stages
everything, remaps ids (`LenRemap`), checks each blob's hash and commits in
one transaction (`LenImportCommit`). Damage (a blob, a line, a part) is
left out and reported, the rest imported; an error or Cancel leaves nothing
behind. What the file is decides where it goes (`importLenFlow`): a
notebook or folder into the library's open folder (`LenArchives.openFolder`)
wherever the import started; a backup, after a confirmation that offers to
skip notebooks already here, at the top level as it was into an empty
library, else into a folder "Backup 13 Oct 2026" (with the time when that
name is taken). A restore keeps the ids of what isn't here, and its Undo
(`undoRestore`) puts its notebooks in the Trash and its folders away.
Entry points: the export sheet's Len format (a notebook or canvas, always
whole; several selected notebooks as one file, `LenScope.notebooks`; a
folder, from its "Export…", which opens the same sheet), ⊕▾ "Import Len file…", "Open
with" / share / drop (`ImportRouter`, `IncomingKind.len`) and Settings →
Backup ("Back up library…", which records `last_backup_at` when nothing was
left out, and "Restore
from backup…"). With sync off, Settings → Backup and the sidebar ("On this
device only") say the notes are only here; the library says so once
(`LibraryNotices`, tip `notes_device_only`) when notebooks are a day old and
nothing was backed up.
The type is registered on Android (intent filters for `application/x-len`
and `*.len`), Linux (`linux/packaging/dev.len.len.mime.xml`, desktop entry),
Windows (installer: `.len` → `Len.File`) and the PWA (`file_handlers`).

Android Auto Backup (`res/xml/backup_rules.xml`, `data_extraction_rules.xml`)
keeps only `len.db` and its WAL; blobs come back through sync (device
transfers also copy them). `InstallIdentity` gives a database restored there
(or copied from another computer) a new device id: the install marker next
to the database, which is never backed up, holds the id; a database without
a matching marker takes a new one and forgets its sync position, so it never
writes as the device it came from.

## Platforms (`platform/`)

Startup (`main.dart`) opens the database and blob store in a try: if either
fails, `ui/startup_error.dart` runs instead of the app (what happened, the
data folder on desktops, Copy details, Try again, which reruns startup).

Platform differences live behind conditional exports
(`export 'x_native.dart' if (dart.library.js_interop) 'x_web.dart'`), so no
`dart:io`, `dart:isolate`, `dart:ffi` or `path_provider` code is compiled for
the web:

| Concern            | Android / Linux / Windows                     | Web                                              |
|--------------------|-----------------------------------------------|--------------------------------------------------|
| SQLite (`sqlite_connection`) | FFI, bundled SQLite, WAL, `<app support>/len.db` | `sqlite3.wasm` + our write-back VFS over IndexedDB (`len`), no WAL; see *Writes on the web* |
| Blobs (`blob_backend`) | files                                     | IndexedDB store `len_blobs` behind `WriteBackBlobBackend` (blobs it can't store wait in memory); if it can't open, memory (`VolatileBlobBackend`), which the library, Settings and a first-write snack say |
| App dir (`app_directory`) | `path_provider` app-support dir         | none                                             |
| Canvas reads (`stroke_reader`) | background isolate, own connection  | UI thread, time-budgeted slices (`SlicedStrokeReader`) |
| Applying large pulls (`pull_worker`) | background isolate, own connection, yielding to the app's writes | UI thread, time-budgeted slices |
| LOD raster cache (`raster_store`) | PNG files in the cache directory (`lod-<format>/`, 96 MB LRU) | none: rasterised again each time |
| Export (`file_export`) | save dialog + Show in folder / share sheet or Save to device | browser download                                 |
| Single instance (`single_instance`) | one process (desktop runners forward later launches) | Web Lock + BroadcastChannel: a second tab waits ("open in another tab") or takes over (*Use here*, `TabHandover`) |
| Page lifecycle (`page_lifecycle`) | nothing (writes are synchronous) | flush on hide / `pagehide`, `beforeunload` guard while a write is pending |
| Incoming files (`incoming_files`) | Android: intents via `IncomingFiles.kt`; Linux / Windows: command line + forwarding from a second instance | PWA `launchQueue` (File Handling API) |
| Handwriting (`handwriting_recognizer`) | ML Kit Digital Ink on Android; none on Linux / Windows | none |
| Stylus samples (`stylus_samples`, `low_latency_ink`) | Android: historical `MotionEvent` samples + low-latency overlay; others: none | none (browsers deliver all samples) |
| Secrets (`secure_store`) | `flutter_secure_storage`: Android Keystore-wrapped keys, Linux Secret Service via libsecret (the desktop keyring; in a Flatpak the secret portal), Windows DPAPI | none: the sync token stays in the database (see *Sync token*) |
| Audio (`audio_files`) | capture to a temp file, play the blob file; Android: microphone permission, MediaPlayer, foreground service for background recording; Linux: `parecord` + `ffmpeg` on the `PATH` to record, GStreamer to play; Windows: Media Foundation | `MediaRecorder` into memory (secure origins only), playback from a blob URL |
| Camera (`camera_capture`, one file: `image_picker` needs no `dart:io`) | Android: the camera app through `image_picker`, and the photo of one cut off by a kill (`retrieveLostData`); Linux / Windows: none | none |
| Media controls (`media_controls`) | Android: media session + notification in a `mediaPlayback` foreground service (`PlaybackService.kt`); Linux: MPRIS on the session bus (`mpris_native.dart`, `package:dbus`); Windows: none (media keys as key events) | Media Session API |

**Why web canvas reads are not in a Web Worker.** The IndexedDB VFS keeps
the database in the main thread's WebAssembly memory and writes changes
back to IndexedDB asynchronously. A worker would have to open its own copy
from IndexedDB: it would lag behind unflushed writes (just-drawn ink missing
from re-read chunks), hold the whole database in memory a second time, and
need a separately compiled worker entry point. Moving reads off the main
thread properly means moving *the* database into a worker (e.g. the OPFS VFS
in a dedicated worker) and making every query asynchronous, while the data
layer is synchronous by design. Instead `SlicedStrokeReader` keeps reads
on the UI thread but bounded: up to 32 missing chunks load synchronously as
before (panning, normal zoom); larger reads load 32 chunks at a time and
yield to the event loop after each 6 ms, and their result arrives
asynchronously through `SurfaceLoader`, like a native background read.

`app/web/sqlite3.wasm` must match the `sqlite3` package version
(`app/tool/fetch_sqlite_wasm.sh` refreshes it). It is loaded once per page:
the app database, the schema check's fresh copy and scratch databases (Ink
Lab) share the module, the latter two on an in-memory file system
(`len-scratch`). The VFS keeps the
database in memory and writes changes back asynchronously, hence the
one-tab lock.

**Writes on the web** (`data/write_back.dart`, `platform/write_back_vfs.dart`,
`platform/idb_block_store_web.dart`). `WriteBackFileSystem` replaces
package:sqlite3's `IndexedDbFileSystem` (same IndexedDB layout: `files` +
4 KiB `blocks`), because that one drops a failed write from its queue and
later writes only the blocks they touch, leaving a torn database behind a
full storage. Ours keeps a set of dirty blocks per file and stores them in one
IndexedDB transaction per flush (a microtask after the change, so a whole
SQLite transaction at once; never while a rollback journal exists, i.e.
never mid-transaction; the journal itself stays in memory). A failed flush
puts its blocks back into the dirty set, so the next one rewrites them from
memory: nothing is dropped and the stored database is always a committed
state. Failures are classified (`QuotaExceededError` → `WriteFailure.full`)
and retried after 2, 5, 15, then every 30 s, and when the tab is shown again.
Blobs go through `WriteBackBlobBackend`: one the storage refuses stays in
memory (readable) and is retried. `StorageWrites` (in `AppServices.writes`;
empty natively) sums both up: `pending`, `failure`, `flush()`, `close()`.
While it fails, `StorageAttention` says so once in a snack bar (Try again;
"Your changes are saved" once it works) and the library and Settings →
Storage show it (same words, Try again).
`platform/page_lifecycle` flushes when the tab is hidden or on `pagehide`, and
registers a `beforeunload` guard (the browser's "Leave site?") only while a
write is pending, so idle pages stay eligible for the back/forward cache.

**Tab handover** (`platform/tab_handover.dart`, browser APIs behind
`TabLock` / `TabChannel`, unit-tested with fakes). The tab holding the Web
Lock `len-database` owns the data; other tabs queue for it and show "Len is
open in another tab" (`ui/open_elsewhere.dart`). *Use here* posts `take:<id>`
on the BroadcastChannel; the holder flushes (if storage is failing it posts
`refused` and keeps running, with its changes), then closes its stores
(later writes fail) and only after everything is stored releases the lock,
posts `released` and reloads, so it waits in turn. The lock is granted in
request order, so a different waiting tab that gets it first gives it back
before opening anything (it saw the other tab's `take`). The new holder posts
`holding`. A holder still starting answers once it is ready; no answer in
5 s shows "isn't answering" (a frozen background tab). Reloading the holder
releases the lock like closing it, but the tab keeps Len: the holder
remembers in `sessionStorage` that it holds the lock, and on a reload
(`PerformanceNavigationTiming.type`) `flutter_bootstrap.js` posts `take:<id>`
before the app has even loaded (`window.lenTab`; `TabHandover.reclaim`). A
waiting tab that got the lock without asking waits a second for such a
request before starting, so it normally gives the lock back before opening
anything; a slower reload takes it back through the usual handover. The
reloaded tab shows the waiting screen only if that takes longer. Web Locks
can't be kept across a reload, and a waiting tab can't tell a reload from a
close, hence the early message. The sync server must allow the app's origin (CORS,
`LEN_CORS_ORIGINS`, default `*`).

**Offline (installed PWA).** `web/flutter_bootstrap.js` (our own; it loads
Flutter without the deprecated `flutter_service_worker.js`) registers
`web/sw.js`. Release builds run `app/tool/build_web.sh`: `flutter build web
--no-web-resources-cdn` (CanvasKit and the fallback Roboto from the app's
origin, no gstatic) and `tool/web_precache.dart`, which writes the build's
file list and a content hash into `sw.js`. The worker precaches it (app
shell, `main.dart.js`, CanvasKit full + Chromium variants, `sqlite3.wasm`,
PDFium wasm + worker, bundled fonts, icons; ≈ 40 MB; never the renderers
the build cannot use), serves the app's static files cache-first and
navigations from the cached `index.html`; anything else on the origin (e.g.
a sync server behind the same host) goes to the network untouched. A new
build changes `sw.js`, so the browser installs the new worker, which takes
over at once and drops the old cache: the running tab keeps its code, the
next start runs the new build. The page also tells the worker which files it
fetched before the worker controlled it (first visit), so cross-origin fonts
fetched on demand are cached too (`len-fonts-v1`). `flutter run` / a plain
`flutter build web` keep an empty precache list (runtime caching only).
Verified in headless Chromium (`app/tool/web_offline_check.py`, Playwright
from nixpkgs; drives the app by label through the semantics tree and by
keyboard, reads back what IndexedDB holds): offline start and reload list
the notebook drawn in online; a full storage keeps an edit in the tab, says
so (library, Settings) and saves it once there is room; a second tab waits,
a reload of the first keeps Len there, and *Use here* brings the latest
edit along. `app/tool/web_upgrade_check.py OLD NEW` checks that a build
opens (and writes to) the data of an older one after a service-worker
update; run against the build before the write-back VFS, the data opened
intact. `app/tool/web_explore.py` walks through the whole app in Chromium
and Firefox (README, Develop) and fails on anything the console or the
network reports.

**Storage.** At start the web app requests persistent storage
(`navigator.storage.persist()`) where browsers decide silently (Chromium,
Safari; an installed app is usually granted); Firefox would prompt, so there
it waits for *Settings → Storage* (web only: status, "Turn on", usage /
quota from `storage.estimate()`, which includes the offline copy).

Web pitfall: dart2js integers are JavaScript numbers — bitwise operators
yield **unsigned 32-bit** values (`-1 << 22` is positive, `1 << 40` is 0) and
`ByteData.get/setInt64` is unsupported. Write `-(1 << 22)`, keep shifts
below 31 bits, and use `float32`/`int32` in binary formats.

### Native shells and packaging

- **Branding:** one design, `app/tool/generate_icons.sh` (glyph =
  Material Symbols "gesture" in `tool/branding/glyph.path`, as the sidebar's
  `Symbols.gesture_sharp`) writes the web icons,
  Android adaptive/themed/legacy icons and splash icon, Windows `.ico` and
  Linux hicolor icons. Don't edit generated icons by hand.
- **Android:** `LaunchTheme` = Android 12+ SplashScreen (surface colour +
  icon tile; the same look via `launch_background` before 12), kept until
  Flutter's first frame. Edge to edge: transparent bars in the window themes,
  and `ui/system_bars.dart` (`MaterialApp.builder`) keeps the bar icons in step
  with the *app's* light/dark theme. Freely resizable (split screen, DeX,
  freeform; `<layout>` minimum 360×400 dp), orientation unlocked;
  `singleTask` with "Open with" / "Share" intent filters (see *Opening files
  from other apps*). Release:
  `android/key.properties` signing (debug-key fallback), R8 + resource
  shrinking, `versionCode` = pubspec build number.
- **Linux:** application id `dev.len.len` (= GTK app id = `.desktop` name =
  icon name, so Wayland docks match the window). The bundle carries `share/`
  (desktop entry with PDF/image MIME types, the `len` scheme and `%U`, icons) and
  `install-desktop-entry.sh`, plus AppStream metadata (`share/metainfo`); the
  runner loads its window icon from there and is single-instance (files
  opened later are forwarded to the running Len). `runner/window_state.cc`
  restores the last size, maximised state and (X11 only; Wayland
  compositors place windows) position from `<data dir>/dev.len.len/window.ini`,
  clamped to the monitor, saved at shutdown (closing the window quits the
  application without destroying it); minimum size 360×400. **Flatpak:**
  `linux/packaging/flatpak/dev.len.len.yml` repackages the release tarball on
  the GNOME runtime (GTK 3, GStreamer, and the `parecord` + `ffmpeg` that
  recording runs; `flatpak/check-runtime-recording.sh` checks a new runtime);
  file access through portals. **AppImage:**
  `linux/packaging/appimage/build-appimage.sh` wraps the bundle as is
  (`AppRun`; `--install-desktop-entry` registers the menu entry, MIME types
  and `len://`); GTK, GStreamer, `parecord` and `ffmpeg` come from the host
  (docs/PACKAGING.md).
- **Windows:** PerMonitorV2 DPI awareness (manifest), initial window centred
  and clamped to the work area, minimum size 360×400. The window remembers its
  placement (`HKCU\Software\Len\WindowPlacement`, saved on close, end of
  session and destroy; restored before the first frame if its monitor still
  exists, maximised if it was). Single instance and "Open with": see *Opening
  files from other apps*. **Installer:** Inno Setup (`windows/installer/len.iss`,
  built in CI): per-user by default (no administrator rights), Start menu
  entry, file associations, uninstaller, upgrades in place (closes a running
  Len). Chosen over MSIX, which only installs when signed with a certificate
  the machine trusts (a paid code-signing certificate or a manual certificate
  import); the installer itself is unsigned (SmartScreen warns until it has
  reputation or a signature).
- **Desktop full screen:** focus mode calls `setFullscreen`
  (`platform/fullscreen*`), served by both runners on `len/window`
  (`setFullScreen`): GTK `gtk_window_fullscreen`; on Windows a borderless
  window over the monitor (style and placement restored afterwards). No
  window plugin (`window_manager`): its Linux plugin rewires the GTK window's
  delete-event and installs a global button-press emission hook, more than
  these three features need.
- **CI / releases:** `.github/workflows/ci.yml` (analyze, tests, all builds,
  server image, the overlay's Kotlin model against the Dart one) and `release.yml` (on `v*` tags; see README *Release*).

### Android review (2026-10)

A code review of `app/android/` against target SDK 36 (Flutter 3.47's default;
min SDK 24), without a device: everything below is verified by reading, the
JVM unit tests (`tool/wet_ink_check/unit_test.sh`: model, flat ends,
prediction, incoming file names), the Dart/Kotlin parity check
(`tool/wet_ink_check/check.sh`) and a release build (R8, the merged manifest
and mapping inspected), **not** on hardware.

- **Fixed:** back at the root finished the activity (Flutter's
  `SystemNavigator.pop` → `finish()`), destroying the engine and a background
  recording → `moveTaskToBack`, plus `enableOnBackInvokedCallback` (predictive
  back on Android 13–15; the default at SDK 36). Leaving focus mode used
  `SystemUiMode.manual`, which turns edge to edge off (Android ≤ 14 then laid
  the app out between the bars) → `edgeToEdge`. Bold text, SIM network and
  touchscreen changes recreated the activity (= an engine restart) → in
  `configChanges`. Reopening from the recent apps re-imported the launch
  intent's files (`FLAG_ACTIVITY_LAUNCHED_FROM_HISTORY`). Incoming `file:`
  URIs and Len's own providers were readable by any sender ("dirty stream")
  → only other apps' `content:` URIs. Stopping the recording service between
  its creation and `onStartCommand` skipped `startForeground` (a crash on
  some versions) → it ends once foreground. Save to device left Dart waiting
  forever when the activity went away, and failed on providers without
  `"wt"`. Handwriting recognition rejected whole-number writing areas.
  `RECEIVE_BOOT_COMPLETED` (from ML Kit's WorkManager) removed.
- **Added (2026-10):** background playback, FGS type `mediaPlayback` with
  `FOREGROUND_SERVICE_MEDIA_PLAYBACK` (no runtime prerequisite on Android 14),
  started only from a play in front; a failed start reports `failed` and
  playback pauses with the app as before. Not yet checked on hardware: see
  checklist 14–18.
- **Checked, fine:** FGS type `microphone` with `FOREGROUND_SERVICE_MICROPHONE`,
  started only while visible after `RECORD_AUDIO` is granted (Android 14's
  while-in-use rule; failures report `failed`); `POST_NOTIFICATIONS` asked once;
  immutable `PendingIntent`s; no exact alarms. Backup rules match the data
  layout (`files/len.db` + WAL; blobs only device to device; never the install
  marker or the secure-storage token). R8: own plugins are registered
  directly (no reflection); ML Kit, WorkManager/Room and `jni` keeps;
  graphics-core and motion prediction ship consumer rules. Stylus samples:
  `device` and time stamps match Flutter's `AndroidTouchProcessor`.
- **Left as is:** on Android 14+ the recording notification can be swiped
  away (the service keeps running; reopen Len to stop); ML Kit's datatransport
  telemetry comes with the library; the Play Console needs the microphone
  FGS declaration (a short video of background recording).

**Device checklist (Galaxy Tab + S Pen, release build).** Each line: do →
expect.

1. Write fast loops and dots with the S Pen at 120 Hz → ink under the nib,
   no gap or double edge where the overlay hands over; same in split screen,
   in a pop-up window, rotated, and in DeX on an external display (move the
   window between displays mid-session, then write).
2. Hover, then write with the side button held → no overlay ink (eraser /
   selection); palm resting while writing → no stray ink.
3. Focus mode → bars hidden, swipe from the edge shows them briefly; leave
   (back / handle) → bars back, content still drawn behind them (no jump),
   on Android 14 and 15+.
4. Predictive back: in a notebook, slowly swipe back → the route follows and
   can be cancelled; at the library root → back-to-home animation; reopen →
   same state, no restart (no splash).
5. Start a recording, press back to home, lock the screen 2 min, unlock →
   notification shows time; Pause / Resume / Stop from the notification and
   from the lock screen work; the recording is saved with full length.
6. Fresh install: first recording asks microphone, then notifications; deny
   notifications → recording still continues in the background.
7. While recording: toggle dark mode, Bold text (Settings → Display), font
   size, rotate, split screen, DeX on/off → recording continues, notebook
   stays open.
8. Swipe Len away from recents while recording → the recording is saved
   (open it again); the notification disappears within ~8 s.
9. Files app → open a PDF, an image, a `.len` with Len (cold: Len closed;
   warm: Len open) → imported once; then close Len with back and reopen it
   from recents → **not** imported again. Share 3 images from Gallery → one
   batch. Open a `len://sync?…` link from a message → Settings → Sync filled.
10. Export → Save to device: one file (rename it), several (pick a folder),
    to Google Drive, and over an existing file → content correct, size not
    larger than the new file.
11. "Don't keep activities" (developer options) on, background Len during a
    save dialog and during a share → no crash, Len restarts at the library.
12. Handwriting search / conversion with a downloaded model → results; then
    reboot, open Len → still works.
13. Settings → Apps → Len → Back up (or `adb shell bmgr backupnow dev.len.len`),
    uninstall, reinstall and restore → notebooks back; sync needs its token
    again (not backed up) and runs as a new device.
14. Play a recording, press home, lock the screen 2 min → audio goes on;
    lock screen and notification show the recording and notebook, position
    moving; play / pause, ±10 s, the seek bar and stop work (Android 12 and
    14+); unlock and return → the ink veil matches what is heard.
15. While playing: receive a call (or start the assistant) → pauses; hang up →
    plays on. Start music in another app → Len pauses and stays paused. A
    notification sound → Len ducks briefly, keeps playing.
16. Wired or Bluetooth headphones: unplug / switch off while playing →
    pauses, never blares from the speaker. Headset buttons: play / pause;
    next / previous (where the headset has them) → ±10 s.
17. Pause from the notification, wait 10 min with the screen off, play from
    the lock screen → resumes where it was. Close the player in Len → the
    notification goes; swipe Len from recents while playing → audio stops,
    notification gone.
18. Record while a recording plays (or the reverse), and two notebooks in
    split screen each playing → each notification drives its own; no crash.

## Library (`features/library/`)

- **Data.** Folders are a synced collection (`FolderRepository`, nested via `parentId`).
  Notebooks carry `folderId`, `favorite`, `trashedAt` and `editedAt`
  (content/title edits only, so organising never reorders "last edited"). Readers are
  defensive: a missing parent folder means "root", and folders caught in a parent cycle
  (possible after concurrent moves) are shown at the top level. Deleting a folder
  tombstones its subtree and trashes its notebooks. `NotebookDuplicator` deep-copies a
  notebook column-by-column (`RowCopier`), so columns added later are copied too.
- **State.** `LibraryController` (a `ChangeNotifier`) holds the section (library,
  favourites, trash), open folder and search query, reads the repositories on `reload()`
  and filters/sorts in memory (`LibraryQuery`). The 30-day trash is purged after the
  first frame, a notebook per event-loop turn (deleting a notebook tombstones its rows
  set-based, one statement per surface). `LibraryActions` adds the dialogs and
  confirmations. Layout and sort are preferences (`AppPreferences`).
- **Shell.** From `Breakpoints.medium` (840 dp): a 248-dp sidebar with sections, the folder
  tree (all drop targets), sync status and settings; narrower: the same in a drawer (☰). The
  header (`library_header.dart`) has the title with a caption, search (a field when wide, a 🔍
  that opens it over the title when narrow), ⊕▾ New (wide only) and ⇅ View (sort, grid / list,
  Select…), both `MenuIconButton`s. Notebooks and folders drag with a mouse immediately and
  with touch after a long press (a long press released in place opens the context menu
  instead). Ctrl / ⌘-click toggles a notebook into the selection and Shift-click extends it
  (`LibraryActions.selectWithModifiers`, `LibrarySelection.extendTo`). Shortcuts: Ctrl+N,
  Ctrl+Shift+N, Ctrl+F, Ctrl+A, Delete, Esc.
- **Grid.** `CoverGridDelegate` lays out covers of about 150 dp (at least two columns,
  stretched to the width) with a fixed caption area (`NotebookCard.captionHeight`: two title
  lines and a caption), so every cover in a row is as tall. The columns come from the delegate,
  not a layout builder above the grid: that rebuilt every card on every scroll frame
  (`test/perf/library_perf_test.dart` builds 200 notebooks and counts card builds). Cards and
  rows are found by notebook id (`findChildIndexCallback`), and `LibraryContent` hands back the
  same card widget while its notebook object, caption and selection are unchanged (the
  controller's `reload` keeps unchanged notebooks as the same objects, `Notebook.sameAs`), so a
  sort, a selection change or a reload builds only the cards that changed. In a short
  viewport the delegate adds columns until a cover and its caption take at most 60 % of the
  height (`cover_grid.dart`; not under 96 dp), so a row with its titles fits a phone held
  sideways; the folder row reads the viewport height from a box `LayoutBuilder` around the
  scroll view (it rebuilds on resize only). Folders are a wrapping row of equal compact tiles
  above the notebooks.
- **Undo.** Every library edit says what it did with Undo (`LibraryActions._undoable`): move
  and drop, rename, cover, favourite, folder edit and delete (no confirmation), duplicate
  (Undo trashes the copy), trash. A notebook without a title is named after the day
  (`new_notebook/default_title.dart`, the device's date format, numbered when taken).
- **Selection bars.** The library's floating bar and the overview's docked bar name each
  command under its glyph (`ui/labelled_action.dart`); the library's takes a second row
  under 520 dp. The overview's selection also exports (the export sheet's page range starts
  as the selection, `initialPages`) and retemplates.
- **New… tile.** On wide screens the notebook grid starts with a cover-sized "New…" tile
  (`NewNotebookTile`, `LibraryContent.showsNewTile`) in the library root and in folders (not
  in favourites, trash, search, selection or list layout); ⊕▾ creates everywhere else. Phones
  get the FAB instead, hidden while an empty state offers its own button.
- **New notebook sheet** (`new_notebook_sheet.dart`, `new_notebook/`): one column (title,
  Styles once there are any, Notebook / Canvas, Template (`PaperRow`, "Background" for a canvas) with the recent papers and "All templates…" → the template
  picker, `CoverRow`, page size, then "Save as style…") with `NotebookPreview` beside it in the dialog and as a strip
  on phones. The papers come from `recentPapers` (`AppPreferences.recentPapers`, filled up with
  defaults; canvases only tiling papers); creating a notebook records its paper. Where the
  library has no ⊕▾ (phones), "Import PDF…" and "Import Len file…" are quiet links at the
  sheet's foot, under Create.
- **Notebook styles** (`notebook_styles` collection, `NotebookStyleRepository`,
  `domain/notebook_style.dart`): a `NotebookChoice` (notebook or canvas, a built-in template
  and its look, paper colour, page format and orientation, cover colour; never a user's image
  template) under a name. The sheet's Styles row (`StyleRow`, `style_actions.dart`; only once a style exists) shows
  them as chips that fill in the whole form at once, the one matching the form selected; "Save
  as style…" (`SaveStyleButton`, under the form) names the current choice (hidden when it
  matches a style or uses an image template). Tapping the selected chip
  again, a long press, a right click or the Menu key opens its menu: "Default for new
  notebooks" (a push pin, checked; one default, `setDefault` clears the others; after concurrent marks the
  latest wins), Rename…, Delete…. The sheet starts from the default style, else from
  `AppPreferences.lastNotebookChoice` (what the last *notebook*, not canvas, was made as,
  recorded by `LibraryActions.createNotebook`), else college ruled. Notebooks copy the values,
  so later edits to a style change nothing made with it; new pages in a notebook keep following
  the notebook's own paper. Library backups carry styles (not added twice; a restored default
  only where none is set).
- **Live covers.** `ThumbnailRenderer` draws the first page (paged) or the content nearest
  the origin (canvas) with the editor's own `PaperPainter` and `StrokeRenderer` into a
  `ui.Image`. `ThumbnailCache` keys previews by a cheap per-surface fingerprint
  (`SurfaceStats`: live stroke count + latest version, plus the page's paper and size), renders
  lazily in short time-boxed batches (one per event-loop turn, one notification per batch that
  changed a preview; the latest requests first, so covers on screen beat those scrolled past),
  keeps an LRU of images and is invalidated when an editor closes or sync brings
  strokes. Covers without ink show a plain cover in the notebook's colour (one of
  ten, `Palette.covers`).

## Search (`data/search/`, `features/search/`)

GoodNotes-style full-text search over notebook titles, folder names, text
boxes, the text of imported PDF pages and recognised handwriting (see
*Handwriting recognition*).

- **Index.** A local, derived table `search_docs(kind, ref_id, surface_id,
  body)` — one row per title, folder, text box or PDF page — with an FTS5
  index `search_fts` over it (external content, `unicode61
  remove_diacritics 2`, prefix indexes). It is never synced: it is created
  with the schema and kept current by **SQLite triggers** on `notebooks`,
  `folders`, `elements` and `pages`, so local edits, duplicates and records applied by sync are
  indexed by the very write that changes them, whatever code path made it.
  The triggers fire only when an indexed column changes (moving a text box
  costs nothing). `SearchIndex.rebuild()` recreates it from scratch. Builds
  without FTS5 (checked at open; the bundled native and web sqlite3 builds
  have it) keep `search_docs` and fall back to `LIKE`.
- **PDF text.** `PdfTextIndexer` extracts page text with PDFium (`pdfrx`
  `loadText`, via the `PdfTextSource` interface so tests fake it) into
  `pdf_text(blob, page, text)`, keyed by the content-addressed blob, so a
  PDF shown in several notebooks is read once. It runs in the background —
  one PDF at a time, 8 pages per transaction, PDFium on its worker — after
  an import, before a search (lazily covering PDFs imported before search
  existed or brought by sync), and only for blobs on this device; an
  interrupted run resumes. Page rows pick the text up through their trigger.
- **Queries.** `SearchQuery` splits the input into words; each must occur
  as a word prefix (`"term"*`), ignoring case and accents. The same rules
  in Dart (`SearchText.fold` keeps offsets) find highlight ranges and build
  snippets. Hits carry the notebook, surface and page number (counted in
  SQL from the page order); trashed/deleted notebooks and deleted pages are
  left out. Library results rank by bm25 (title matches first); in-notebook
  results are in reading order.
- **Library.** While searching the library section, `LibrarySearchResults`
  (a sliver below the title matches) lists content matches grouped by
  notebook, with page chips and highlighted snippets. Tapping one files a
  `SearchJump` with `SearchService` and opens the notebook the usual way;
  the editor's search takes the jump, fills in the query and reveals and
  highlights the match.
- **Editor (Ctrl+F or the search button).** `EditorSearchController` holds
  the query, matches (one per text box, one per occurrence in PDF text) and
  the current one; Enter/F3 and Shift+Enter/Shift+F3 move, Esc closes.
  It reaches the editor only through `EditorSearchHost` (document: page
  frames + `goToPage` + pan; canvas: viewport pan, zooming out if needed),
  so the editor hook is a controller, a shortcut, a button (the top bar's
  `search` slot) and one overlay (`EditorSearchLayer`: highlights + bar,
  placed below the chrome; phones start with the match list folded). PDF matches are
  highlighted on the exact glyph boxes, which `PdfGlyphCache` loads on
  demand per page (normalised to the page, merged per line).

## Handwriting recognition (`ink/recognition/`, `platform/handwriting_recognizer*`)

GoodNotes-style handwriting search and lasso "Convert to text", on-device.
Android recognises; the text syncs (`recognised_text`), so every device
searches it.

- **Recogniser.** `HandwritingRecognizer` (strokes in writing order →
  candidates, best first; per-language model download) behind a
  conditional export: **Android** uses Google ML Kit Digital Ink
  (`MlKitRecognizer` synthesises point timestamps from the stroke's start time
  and passes a writing area and pre-context). Recognition goes through Len's
  own channel `len/handwriting` (`HandwritingRecognitionPlugin.kt`): points
  travel packed in typed arrays, the channel decodes on a background task
  queue and builds, recognises and answers on a single-thread executor, so
  none of it runs on the merged platform/UI thread (the plugin's channel did,
  ≈ 40 ms a line). Model downloads stay with
  `google_mlkit_digital_ink_recognition` (already on AGP 9 / built-in
  Kotlin); **Linux, Windows and web** get
  `UnavailableRecognizer` (WinRT ink analysis on Windows is a possible later
  implementation) and search what Android devices recognised (synced). Models are BCP 47 tags (`RecognitionLanguages`); the
  language follows the device locale unless chosen in the settings.
- **`RecognitionService`** (in `AppServices`) holds the language, the
  model's state (checks it at start; with indexing on, a missing model is
  downloaded over Wi-Fi; the settings and "Convert to text" download on
  demand with a progress bar — ML Kit reports no byte progress) and the
  `HandwritingIndexer`. Settings: language, "Search handwriting" (off
  forgets recognised text, on re-recognises everything) and model download
  (Android manages removing models). Without a recogniser the section
  explains that Android devices recognise and lists how many lines arrived
  (no toggles); the indexer always runs there.
- **Clustering** (`InkClustering`): a surface's strokes (highlighter
  excluded) become lines and words. The unit is the median stroke height;
  a stroke joins a line whose letter band it overlaps vertically (small
  strokes — dots, accents, commas — only need their centre near it) within
  3 units horizontally, preferring the previous stroke's line when written
  within 1.5 s; lines on the same band are merged; words split at gaps wider
  than 0.6 × the line's letter height. A line's key is a hash of its stroke
  ids.
- **Index.** Local and derived: `ink_text(surface_id, stroke_key,
  language, text, rect, words)` — one row per line this device can show,
  `words` = per-word boxes when the recognised words match the word
  clusters — and `ink_text_queue(surface_id, version)`, filled by
  **triggers on `strokes`** (insert, delete, and updates of `deleted` /
  `points` / `surface_id`), so local edits, undo, duplicates and sync all
  queue their surface without any call, and on `recognised_text` (remote
  writes only: clean rows). Triggers mirror `ink_text` into `search_docs`
  as kind `handwriting` (ref = row id), searched and ranked like text
  boxes, with page numbers.
- **Sync** (`RecognisedTextRepository`, collection `recognised_text`, one
  record per surface: language + `[[line key, text], …]`, see
  SYNC_PROTOCOL *Recognised handwriting*). Every device clusters its own
  strokes and takes a line's text from the record only while a line with
  that key exists, so edited or erased ink loses its text on every device
  at once; boxes come from the local clustering, so records carry no
  geometry. Per line, the indexer keeps its own row (same strokes and
  language), else takes the synced text, else recognises (with a
  recogniser) or leaves the line without text (without). Only recognising
  devices write the record (`publish`: missing, other lines, or a language
  the user chose here later — never for mere differences in reading, so
  two phones can't ping-pong) and tombstone it when the ink is gone.
  Without a recogniser the indexer only wakes for queued surfaces that
  have a record and skips clustering for the others.
- **Background work.** `HandwritingIndexer` listens to the database's commit
  stream (only on platforms with a recogniser and the model present), waits
  until no commit came for 3 s (the user stopped writing), then drains the
  queue oldest first, one surface and one line at a time (pausing again if
  edits arrive). It also waits while any pointer is down or a trackpad
  gesture runs and for 3 s after the last pointer event (`PointerActivity`,
  `core/`, a global pointer route attached by `LenApp`; a hovering pen
  counts): strokes reach the database only at pen-up, and scrolling or
  zooming commits nothing, so commits alone did not keep clustering and
  recognition out of those. Lines whose key is already stored keep their text, so
  writing a word re-recognises one line; a surface changed while it was
  being recognised stays queued (the queue row is only removed at the
  version that was read). Failures (model missing) leave the queue for the
  next change.
- **Highlights.** The editor search (`EditorSearchController`) turns a
  handwriting hit into one match per occurrence, highlighted on the matched
  words' boxes (`InkMatchRects`) or the whole line; the library lists them
  with a pen icon.
- **Convert to text** (`features/editor/recognition/`): the lasso menu's
  "Convert to text" (disabled with the reason as tooltip where unsupported)
  makes sure the model is present, recognises the selected ink line by line
  (`ConvertToText.recognize`), and shows the reading — editable, with
  alternatives for a single line — to **replace** the strokes with a text
  box (top-left of the ink, its most common colour, font size 1.25 × the
  letter height, at least as wide as the ink; one `InkEdit` via
  `SelectionController.replaceStrokesWith`) or **copy** it.

## Preferences

`AppPreferences` (in `AppServices.preferences`) is a `ChangeNotifier` over
`SettingsRepository`: theme mode (the app's `ThemeData` are built once, with a fixed ink-blue accent),
stylus-only, finger-tap undo and redo (one switch), stylus side-button action
(`PenButtonAction.eraser|lasso|none`), editor toolbar placement (docked / floating, and the floating position),
library layout and sort, the papers of the latest new notebooks and what the last new
notebook was made as (`lastNotebookChoice`). Getters always read
the store, so values written elsewhere are never stale.

## UI design system (`ui/`)

`AppTheme.light/dark()` build a fidelity colour scheme from the fixed ink-blue seed
(`#3B5BDB`) with quiet neutral surfaces (tonal `secondaryContainer` roles are neutral too, so
the accent stays for primary actions), Inter on every platform in a six-role type scale
(Title, Heading, Body, Label, Caption, Overline; Material's other slots alias onto them), Material
Symbols Rounded at weight 300 (`iconTheme`), no ripples (`NoSplash` plus a calm `onSurface`
highlight) and shared component themes (`theme_components.dart`: radii, overlay surfaces, no
Material elevation except menus, Symbols for Flutter's own back / close / drawer icons).
Tokens (how to use them: CONVENTIONS "Design tokens"): `Gaps`, `Radii`, `Palette`
(`app_theme.dart`); `Motion`, `Breakpoints`, `Targets` (by input: `touchFirst` is Android or a
coarse web pointer, `platform/coarse_pointer*`), `Glyphs`, `Shadows` (`design_tokens.dart`);
`Surfaces` (the canvasBackdrop / chrome / raised / overlay roles, the scrim and the calm
overlays) and `OverlaySurface` (`surfaces.dart`).

Shared UI, one primitive per kind of surface (REDESIGN §5): menus (`menus.dart`: `MenuRow`,
18-dp icons in an always-reserved slot, 44 / 48-dp rows; `showContextMenuAt`), popovers
(`adaptive_popover.dart`: `showAdaptivePopover`, an `overlay` 320 dp wide anchored on wide
screens, a sheet on phones), task sheets (`dialog_or_sheet.dart`: `showDialogOrSheet`, centred
dialog on tablets / desktops, bottom sheet on phones; `sheet_parts.dart`: `SheetHeader` with a
left-aligned Heading and ✕, `SheetActions` with Cancel and one filled primary, stacked on
phones), confirms (`app_dialogs.dart`: `confirmAction`, `AppDialog` with a left-aligned title
and a tinted `DialogIcon` only when destructive or in progress, `DialogBody` width) and
messages (`messages.dart`: `showMessage`; `MessageQueue` counts the snack bars up per messenger,
keeps app-wide whether one is up and when one last was (`MessageQueue.activity`) and `MessageQueue.stepAside` fades standing notices such as the missing-PDF card while one shows,
so one message shows at a time), segmented buttons that stack rather than shrink when they
don't fit (`fit_segments.dart`: `FitSegments`). Floating chrome: `floating_panel.dart`
(`FloatingPanel`, the `raised` surface; `radius: Radii.pill` for pills) and `chrome_fade.dart`
(`ChromeFade`: fade plus an 8-px slide toward the edge). Also `text_prompt.dart`,
`sidebar_item.dart` (library sidebar; the selected row carries the accent). Menus opened from a
button use `MenuIconButton` / `showMenuBelow` (`menus.dart`; `MenuRow.shortcut` hints show only
where a keyboard is likely), never `PopupMenuButton`. The chrome's `MenuAnchor`s (⋯, Insert,
zoom) sit in `MenuEdgeMargin`, which adds 8-dp side strips as display features (the anchor's
`MediaQuery` padding never reaches its overlay; display features do). Rows of controls that
scroll sideways (the text format bar's rows, the toolbar's quick slots in a narrow bar) use
`ScrollFade` (`scroll_fade.dart`): an end fades out while content lies beyond it. The
keyboard shortcut reference (`settings/keyboard_shortcuts.dart`, Ctrl/⌘+/) is a list of
`ShortcutGroup`s kept honest by `keyboard_shortcuts_test.dart` (each entry must be bound
in the screen it describes); add a binding there when adding one. Settings (`features/settings/`): General,
Writing, Handwriting, Sync, Storage (web) and About in one centred 640-dp column;
`SettingsSection` is a quiet `SectionLabel` heading over a rounded plate of `SettingsTile`s
(18-dp icon, Body title, Caption subtitle; a `control` trails on wide rows and goes below the
text on narrow ones). Documents UI
(`features/documents/`): `templates/` (`TemplateChooser`: search, categories, gallery, planner
dates, week start, paper colour and page size) used by the template picker and the new-notebook sheet; `overview/` (the page overview
with selection mode; `editor/document/page_overview.dart` re-exports it);
`progress_dialog.dart` (`runWithSteps` + `TaskProgress`: stage, subject, "Page x of n", optional Cancel).
Library selection mode: `library/selection/` (`LibrarySelection` on `LibraryActions`, batch
actions, floating bar). `flows_screenshot_test.dart` and `overview_screenshot_test.dart` cover
sheets, dialogs, empty states, selection, the page overview and 1.3× text; findings are tracked
in `docs/UX_AUDIT.md`.

Accessibility: `test/accessibility_test.dart` checks Flutter's guidelines (tap targets,
labelled tap targets, WCAG text contrast measured in the test font) on the main screens,
popovers and dialogs at phone and tablet sizes, light and dark, and at 2× text; known
exceptions are listed there with their `UX_AUDIT` item. Icon-only controls need a tooltip or
`semanticLabel`; colours are announced by name (`color_picker/color_names.dart`,
`colorName`, also `ColorDot`'s default label); selected and expanded states go into
`Semantics`. `FocusRing` (`focus_ring.dart`, in `MaterialApp.builder`) paints an accent ring
around the focused control while the keyboard drives focus (not for text fields, scopes or
areas over half the window), so no control needs a focus style of its own.

Visual checks: `test/screenshots/` renders the library, settings and the editor (paged and
canvas, tabs, focus mode, toolbar positions, menus, 320 dp phone; the toolbar at every dock, its
options popovers, Insert and ⋯ menus and 1.3× text in `toolbar_screenshot_test.dart`; open-notebook motion frames in `transition_screenshot_test.dart`;
every template at 25 / 100 / 300 % and the picker in `templates_screenshot_test.dart`)
at phone, tablet and desktop sizes in light and dark with real fonts. Run
`flutter test test/screenshots --dart-define=SCREENSHOTS=true` and look at
`app/build/screenshots/*.png`.

## Sync

See [`SYNC_PROTOCOL.md`](SYNC_PROTOCOL.md). Every synced table has
`updated_at / device_id / deleted / dirty`. A cycle pushes dirty rows, then
pulls the server's change feed from the last seen sequence number, applying
records with last-write-wins. Remote records are parsed strictly
(`RecordFields`): every field of the collection's format is required, and a
malformed record is skipped. Open screens subscribe to
`SyncController.remoteChanges` and reload only the affected surfaces.

Robustness (`SyncEngine`): rows are marked clean only for the exact version
the server confirmed (`markClean` by `updatedAt`). Pulls ask for the server's
largest page (1,000 records) and fetch the next page while one is applied.
Decoding a page means JSON, the record checks, and live strokes parsed into
the rows they are stored as (`StrokeRow`, `SyncRecord.prepared`; a stroke
within one chunk is checked on its encoded points without being built).
A `PullApplier` then applies the page in slices, one transaction each; only
the last slice moves the feed position, so a dropped connection never loses
anything: a page cut short is pulled again (re-applying a record is a no-op);
the next cycle resumes. Where that runs:

- **A large pull, natively** (a page of 64 KB or more: a first sync, a big
  catch-up) starts a pull worker (`platform/pull_worker.dart`,
  `sync/background_pull_worker.dart`) for the rest of the pull: an isolate
  with its own connection to `len.db` (`AppDatabase.attach`, WAL) that
  decodes the pages (their bytes move there uncopied) and applies them in
  8 ms slices with a 1 ms pause between, the same `PullApplier` code, so
  triggers (search, the handwriting queue) fire as on the UI isolate. The UI
  thread only fetches pages. Two writers on one file: every transaction
  begins `IMMEDIATE` (one that read first could not upgrade once the other
  had committed) and waits up to 5 s for the lock (`waitWhenBusy`, a busy
  handler that sleeps: the bundled SQLite's default one gives up within
  ~70 ms whatever `busy_timeout` says); a worker slice still finding it
  locked is tried again, and a page's first slice also waits for the app.
  The app's transactions
  raise a count in memory the worker reads (`SharedWriteSignal`, the
  `ffi` package), which ends its slice after the current record and holds
  the next until the app is done, so the app's write waits about a
  millisecond (writes outside a transaction wait at most a slice). The
  worker's commits are announced on `AppDatabase.commits` (the handwriting
  indexer listens), and what the pull changed comes back per page as
  `RemoteChanges` (also what committed before a database error).
  Cancelling stops it after the current slice; it closes
  when the pull ends.
- **Otherwise** (the web, an in-memory database, small pulls) the page is
  decoded in a worker natively (`platform/pull_decoder.dart`; the web
  decodes on the UI thread) and applied on the UI thread in slices of
  about 4 ms with a turn of the event loop between (also between pages), so
  a first sync never holds the UI for a frame.
Each cycle starts with `/v1/health`: its `serverId` decides whether this is
the server last synced with — a new id (another server, or a wiped or
restored one) resets the feed position and marks every row and blob for
upload, so the server gets a complete copy; a changed address of the same
server costs nothing. Push and pull send the last pulled seq; a server that
no longer has it (restored from a backup) answers 409 and takes a new id,
and the cycle starts over once. Either reset is explained once, after the
sync that recovered, by a calm message in the library
(`SyncController.notices`; not on the first sync with a server). Failures are `SyncException`s with a
`SyncFailure` kind and a message that says what to do
(`sync/sync_errors.dart`): wrong token, unreachable / refused / unknown host /
certificate, not a Len server, server too old or too new.

Deletion conflicts (`data/deletion_conflicts.dart`): a page or notebook deleted
on one device while another kept writing in it comes back (a notebook into the
trash) with everything that deletion removed. Each deletion stamps all its
tombstones with one version (`NotebookRepository.delete` / `deletePage`), so the
rows of one deletion are recognisable on every device; tombstoned strokes and
elements keep their payload, and tombstones their blobs, for 30 days
(`TombstonePayloads`, purged by `LocalBlobGc`). After a pull the engine revives
deleted pages / notebooks that hold live content and notebooks / pages whose
tombstone a live record replaced, then pushes the revived rows. Tombstones are
pushed children first, so a half-finished push never looks like a conflict.

Presentation and retries (`SyncController`, `ui/sync_status_button.dart`,
`features/settings/sync_*`): `lastError` is always plain words, with any raw
text in `lastErrorDetails` (Settings → Sync shows it under Details). The
timer, app lifecycle, editor and library call `syncInBackground`, which skips
while `waitsForSettings` (the server rejected the token: retrying can't help);
saving settings or Sync now tries again. A failed status opens Settings at
Sync; `SyncAttention` says once, app-wide, that a rejected token stopped sync.

Sync token (`data/sync_token_store.dart`, `platform/secure_store.dart`): the
access token lives in the platform's secure store under a per-installation
slot (`sync_token_slot` in settings, so installations sharing one keyring
don't share a token); `SyncTokenStore.token` is a synchronous in-memory copy.
Startup reads it without waiting for it (a locked keyring may prompt), then
starts sync. When the secure store fails (no Secret Service in a Linux
session, a locked or refused keyring, a Keystore error) sync goes on: the
token is kept in the settings table (`sync_token`), Settings → Sync says so
once, calmly, and the move is retried at the next start and at most hourly
before a sync. A token found in the database at start (also one saved by an
older build) moves the same way; it is deleted with `secure_delete`. Turning
sync off forgets the slot, so an entry the store couldn't delete is never
read again. In a browser nothing is secret from the origin's own scripts (an
encrypted entry would sit next to its key), so there is no secure store: the
token stays in the database in IndexedDB, readable by anyone with access to
the browser profile. On Android the store's data is not useful in a device
backup (its key stays in the Keystore): after a restore the token is asked for
again.

## Known limitations / next steps

- Canvas chunk reads run in a background isolate, but writes, page surfaces,
  thumbnails and other queries still run on the UI isolate (small and indexed).
- Far zoom-out of a huge canvas loads only chunks without a stored raster
  natively; the web (no raster store) still loads every visible stroke and
  rasterises again after reopening. Paged documents do not store their LOD
  rasters. Chunks with images not on this device yet are not stored (loaded
  when shown far out) until the blob arrives and decodes.
- Stored-raster writes wait for the LOD view to be idle, not for every frame:
  zooming in past the LOD range right away lets them run during tile frames
  (each a small GPU read-back).
- Pixel-erasing a long stroke, or moving a selection, rewrites strokes as
  new records (simple and sync-safe, but more rows than a delta).
- Text boxes: paste keeps formatting from HTML only (RTF-only sources such as
  WordPad paste plain); PDF export places glyphs
  word by word without kerning; boxes with characters outside the bundled
  fonts' subsets export as images.
- Android: historical stylus samples are merged from a platform channel;
  the low-latency overlay is tuned on a Galaxy Tab S8+ only (see *Input*;
  its hand-over delay assumes a Flutter pipeline like that tablet's).
  Small floating panels over the canvas (audio player, search)
  are not cut out of its clip. Stylus tilt/orientation are received but
  unused.
- The web keeps the sync token in IndexedDB (no secure store in browsers);
  the Linux keyring is read synchronously on the platform thread, so an
  unlock prompt may hold up the window until it is answered.
- PDF: tiles are not persisted (re-rendered after reopening) and stop at
  65536 px page width; exported
  PDFs drop the source's form fields (their looks are kept) and links with
  other actions than web addresses and pages of the same file — see
  *Blobs and PDFs*.
- Audio: recordings are stored in 5-minute parts (each a blob, synced once
  finished; a part's download is held in memory). Android background
  recording needs the foreground service to start while Len is in front (it
  does, at the start of a recording); a recording cut off by a killed process
  is recovered on the next start from its journal (browsers keep only the
  finished parts). Linux recording needs `parecord` and `ffmpeg`
  installed, playback needs GStreamer with the `-good` (MP4) and an AAC
  decoder plugin; Opus/WebM recordings from Chrome/Firefox may not play on
  platforms without a WebM decoder. Waveforms come from the recorder's level
  meter (≈ the loudness of the last buffer every 100 ms), not from decoding
  the audio; recordings without one show a flat scrubber. Trimming is
  non-destructive (parts wholly outside the trim keep their storage until
  "Free up …"), trimmed browser recordings export the whole parts the trim
  touches, and Windows has no system media controls (SMTC; media keys only
  while Len is in front); exporting reads the whole audio into memory.
- Planners: fixed headings ("Week", "Schedule", "Priorities", "To do", "Notes") are English
  whatever the planner's language; the language list is curated (scripts the bundled Inter
  covers), hours are always 24-hour, and weeks start on Monday or Sunday only. User templates
  are images (PDF pages are
  rasterised at 2000 px when imported), so they are not vector-crisp at deep
  zoom; a template only travels inside pages, not as a shared file.
- Server blob garbage collection is a manual/cron admin command, and finds
  references by scanning record JSON for sha256 strings (see SYNC_PROTOCOL).
- Image bitmaps are whole-image decodes per mip level (no tiling); a 4096 px
  image is the sharpest it gets. Crop mode shows the image on its own (ink
  over it is hidden while cropping).
- Handwriting: recognised only on Android (Linux, Windows and web search
  what Android devices recognised and synced; text of ink written there
  appears once an Android device has synced and read it; a record of a
  deleted page stays live until an Android device re-reads it, harmless as
  it matches no ink; two Android devices online at once may both read new
  ink before either's record arrives); a changed surface is re-clustered from all its strokes (cheap per
  page, heavier on huge canvases); a phrase is found only within one line;
  drawings made free-hand with the pen are recognised like writing (usually
  as nonsense; shapes, `Stroke.shape`, are left out); no pause while on battery.
- Search: PDF text is only
  extracted for PDFs present on the device (fetched when a page is viewed);
  FTS5's
  `unicode61` tokenizer does not segment CJK text (prefix matches only from
  the start of a run); the editor's matches refresh on query changes and
  when the bar reopens, not live while typing into a text box.
- Web: the whole SQLite database is held in memory (IndexedDB VFS) and PDFs
  are opened from memory, so very large libraries/PDFs cost browser memory;
  browsers may evict IndexedDB under storage pressure unless persistent
  storage is granted (requested at start, except in Firefox, where it
  waits for Settings → Storage, as it prompts) and quotas vary. Writes reach
  IndexedDB a few milliseconds after an edit; closing the tab in that window
  asks first (`beforeunload`), but a crash or a killed browser can still lose
  it, and while storage is full the latest changes live only in the tab (said
  in a snack bar and the library). Reloading the active tab while another tab
  waits hands Len to the waiting tab (lock requests are granted in order). A
  holder whose final store fails after it stopped writing (storage filling up
  within milliseconds) keeps the lock and retries, but stays stopped until
  reloaded. Canvas chunk reads run on the UI thread (in time-budgeted
  slices; a single large chunk still decodes in one go).
- Open with: Android shares mixing PDFs and images arrive as `*/*`, which
  Len does not register for; PDFs dropped onto an open editor are ignored (only
  images are inserted there; drop onto the library or use "Open with").
- Page reorders made concurrently on two devices converge (LWW per page) but
  may interleave differently than either device intended.
