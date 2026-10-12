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
  ring one tile around it), at most two in flight, recordings time-boxed to
  4 ms per batch, and run after the frame that asked for them; the painter
  repaints when they land (`InkTileCache` / `DocumentSurfaces.rendered`).
- **Pen-up** (`SurfaceChange.appended`): `SurfaceModel.addStroke` reports a
  new stroke that lies over everything in its chunks (no highlighter, no
  element above) as an *append*. Tiles keep their images; the stroke is
  drawn as a vector over the tiles it touches (*overlay*) in the very next
  frame, and each such tile is re-rendered as *old image + stroke* off the
  frame. So committed ink never vanishes or flickers at pen-up, and a
  pen-up never re-records a chunk picture or replays a page of ink.
- **Loads** (`SurfaceChange.loaded`: stored content arriving) keep the
  images of the tiles they touch as stale stand-ins until re-rendered (that
  content was not on screen yet), so a loading canvas never drops to
  vectors.
- **Other edits** (erase, undo, lasso) invalidate only the tiles over the
  changed chunks; those are drawn from vectors for a frame or two.
- **Idle caches**: a cache not painted for 500 ms (its view zoomed out to
  level-of-detail images, say) renders nothing on edits; appended strokes
  wait as overlays until it is painted again, so it never takes raster
  time from what is on screen.
- **Zoom and pan**: panning by whole device pixels keeps the space and its
  tiles. Zooming, or a sub-pixel shift, draws the current tiles transformed
  (`FilterQuality.medium`) while the gesture lasts; after 150 ms still the
  new space is adopted and rendered, the old tiles standing in for each
  area until all its new ones exist, so nothing goes blank.
- **Memory**: tile images live in one `TilePool` (LRU by bytes, 160 MB =
  160 tiles of 1 MB) shared by every surface and view; evicted tiles are
  re-rendered when needed.
- **Split view**: page models are shared between the panes of a notebook
  (`PageModels`), tile caches are not — each view has its own zoom and its
  own `PageSurface` (chunk pictures + tiles), all listening to the shared
  model's `changes`.
- **Level of detail**: zoomed out far (canvas), `ChunkRasterCache` images
  are drawn instead; on an append they too keep their (stale) images with
  the new strokes drawn over them until re-rasterised.

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
  that first shows it for 1–3 s. Tests and the web build them inline
  (`InlineOutlinePreparer`).
- **Reads in blocks** (`SurfaceLoader`): a range of more than 36 chunks (a
  canvas seen from afar) is read in 4 × 4-chunk blocks, middle first, so
  the first ink shows within a second rather than after reading (and
  copying between isolates) tens of thousands of strokes. Chunks whose
  outlines are being built count as loaded for the next read.
- **Previews** (`ThumbnailRenderer`): ink thinner than 1.5 px in the
  preview is drawn as plain lines along its points
  (`StrokeRenderer.drawSketch`), without building outlines.

Measuring: profile builds with `--dart-define=LEN_PERF=true` log frame and
pen-up latency summaries (`PerfProbe`, see docs/INK_LAB.md, *Rendering
performance*); timeline markers `len.renderTile`, `len.commitStroke`,
`len.persistStrokes`, `len.recordChunk`, `len.handwritingCluster`,
`len.outlineStep`, `len.insertLoaded`, `len.thumbnail` show up in Perfetto /
DevTools.

**Navigation** (`ink/navigation/`, `features/editor/canvas/`): `KineticPan`
measures the viewport's own motion during a navigation gesture (fingers,
trackpad, middle-button drag) and `ViewportAnimator` glides on after a fling
(iOS-like deceleration; no glide after a pause or a pinch). The input controller
only reports begin / track / release. `ViewportAnimator` also animates zooms
(geometric scale, focal point fixed) and fits. Canvases add a zoom indicator
(shown while zooming; tap for 50 / 100 / 200 %, "fit content" (exact
bounds from the outermost chunks) or "back to start": their only menu), keyboard zoom (`+` `-` `0` Shift+1 Home) and a background: template and
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
most recently edited page is undone first (a step may span pages: see
*Selections across pages* under *Editing tools*). Painting mirrors `InkSurface`
(paper → committed ink → live ink layers) across every visible page.

Page management (`PageActions`, `DocumentCommands`, `PageOverview`): insert,
duplicate (copies stroke rows wholesale via `SurfaceCopier`, so stroke
columns added later are copied too), delete (with an Undo snack bar that
re-saves the page's strokes; the overview's selection goes through
`DocumentCommands.deleteMany` → `PageActions.deleteAll`, one step with one Undo
that restores every page in place — at least one page always remains), reorder (fractional sort keys, `PageOrder`;
the list is renumbered only when a gap is exhausted), bookmarks, templates.

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
  repeats: "Undo ×3"), `TipBanner` and, in focus mode, only a `FocusHandle`. On phones
  (< 600 px) the page navigator *peeks* (`chrome/peeking.dart`): it shows when the
  notebook opens and while the document viewport moves, fades after ~2 s (stays while
  touched or hovered), lets touches through when hidden, and takes no room in
  `ChromeLayout.covered` — so it no longer covers the page above the toolbar. `ChromeLayout` says how much of each screen edge
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
  the first edit). `TipsController` (`chrome/editor_tips.dart`) shows a one-time tip under
  the top bar, for 10 s or until dismissed, remembered per device
  (`SettingsRepository.seenTips`): the stylus side button (after the first pen contact,
  phrased for `PenButtonAction`; none if it does nothing). Multi-finger taps get no
  tip: the gesture HUD names them when they happen.
- **Tabs** (`tabs/`): `OpenNotebooks` (in `AppServices`) holds up to 8 open notebooks,
  the active one, and each tab's `EditorViewState` (page, zoom, pan). The library opens
  notebooks through `openNotebook()`, which pushes one `EditorWorkspace` route; it shows
  the active tab's `EditorScreen` (keyed by notebook), which saves its view on dispose
  and restores it on creation. Closing the last tab leaves the workspace.
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
  flow fits the whole page and slides it in.
- **Shortcuts** (`editor_shortcuts.dart`): Ctrl/⌘+Z, Ctrl/⌘+Shift+Z, Ctrl+Y; tools
  P / H / E / L / S / T / K; 1–6 quick colours, [ / ] width; F11 or Ctrl/⌘+. focus mode; F5 focus mode with the laser;
  Ctrl/⌘+E export (paged), Ctrl+F search;
  Ctrl+Tab / Ctrl+Shift+Tab / Ctrl/⌘+W tabs. Canvases: `+` / `-` (also with Ctrl/⌘),
  `0` 100 %, Shift+1 fit content, **Home back to start**. Paged notebooks: ← / → and
  Page Up / Down turn pages, **Home first page**, End last page. Single keys are ignored
  while text is edited.

## Templates (`domain/templates/`, `domain/paper_pattern.dart`)

- **Registry.** `PaperStyle` (`templates/paper_style.dart`) is the registry of built-in
  templates: stored name (id), label, `TemplateCategory` (Basic, Writing, Planners, Paper; My
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
  to …") — `PlannerLinkTaps` only watches pointers, so drawing is never disturbed.
- **My templates** (`templates` collection, `TemplateRepository`, `UserTemplate`): an image blob
  plus the page size it suggests. "Import…" in the picker takes an image (`ImageImport`) or a
  PDF page (rendered to a 2000 px PNG); "Save page as template" (page menu) renders the page
  as it looks (paper, background, ink, content). Pages made from a template reference the
  blob directly (`Paper.image`), so renaming or deleting a template never changes them.
- **Picker** (`features/documents/templates/`). `TemplateChooser` (search, category chips,
  `TemplateGallery` of live miniatures, `PlannerOptions`, `PaperOptions`, page size) is shared by
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
`/v1/health` (the server's blob limit and last garbage collection), then uploads
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
recordings; the trash is live, "delete forever" releases). `LocalBlobGc`
(started at launch, at most daily) deletes blobs unreferenced for 7 days
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
Files are saved with a save dialog on desktop (`file_selector`), the share
sheet on Android (`share_plus`) and downloaded in browsers
(`platform/file_export*`); several PNGs (`saveOrShareAll`) are shared at once
on mobile and written into a folder the user picks on desktop.

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
  canvas menu, and dragging the selection's handles (`PdfSelectionHandles`,
  touch targets over the painted knobs that keep the press from the canvas)
  extends it. `PdfLayer` paints the selection (one box per line, with
  handles) and a menu: **Copy** (also Ctrl/⌘+C), **Highlight**, select all
  on the page.
- **Highlight** turns each selected line (`PdfGlyphs.rectsFor`) into one
  highlighter stroke along its middle, 1.1 × the line's height, with the
  highlighter's colour and opacity (no pressure thinning or stabiliser),
  committed to the page's `SurfaceModel` as one `InkEdit` — so it
  is ordinary ink: undoable, erasable, selectable, synced and exported.
- **Links** (`loadLinks`, incl. URLs detected in the text): tapped with a
  finger while fingers navigate (stylus only), or, with any tool, from the
  menu of a selection made on them (long press or right click: **Open
  link**). Internal links scroll to the notebook page showing the target PDF page (the next
  one after the link's page if the PDF appears twice); web links ask first
  ("Open link?") and open in the browser (`url_launcher`).
- **Outline** — "⋯" → *PDF outline* (`PdfOutlinePanel`, a draggable bottom
  sheet): the bookmarks of every PDF in the notebook as a collapsible tree
  with notebook page numbers; entries whose page was deleted are disabled.

## Images (`ink/images/`, `features/editor/images/`)

- **Import** (`ImageImport`): PNG, JPEG and WebP files up to 4096 px and 8 MiB
  are stored byte for byte; anything else the platform can decode (larger
  images, GIF — first frame —, HEIC/HEIF on Android, BMP) is decoded by the
  engine at ≤ 4096 px and re-encoded in an isolate (`package:image`): JPEG
  when opaque, PNG with transparency. The bytes become a content-addressed
  blob (so they sync like PDFs) and an `image` element at natural size
  (1 px = 1 world unit), shrunk to 70 % of the view and kept on the page.
  Entry points (`EditorImages`): the top bar button (file picker; on Android
  also the camera via `image_picker`), Ctrl+V (`pasteboard` reads the system
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
    when the next engine starts.
  - *Linux:* paths / `file://` URIs on the command line (`Exec=len %F`;
    `MimeType=application/pdf;image/png;image/jpeg;image/webp` in the desktop
    entry). The GTK runner is single-instance (`G_APPLICATION_HANDLES_OPEN`): a
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
  when the app is paused. Swiping Len away from the recent apps asks Dart to
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
  recordings (MP4 / WebM) export untrimmed. Storage is not freed: parts
  outside the trim stay (dropping them would need the timeline and
  waveform rewritten and would make trimming one-way).
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
  list, and while recording a pill with time, level, pause and stop); phones
  get "⋯" menu entries and floating recording controls (`AudioLayer`). The
  player (`PlaybackBar`) floats above the bottom chrome: title and time, a
  `WaveformScrubber` (played part in the accent colour, ink density strip with
  a dot per burst; tap or drag to seek, a tap near a dot plays from just
  before that writing), skip ±10 s, play / pause, speed menu, "tap ink to
  play", recordings, close. Keys while the player is open
  (`playback_keys.dart`, ahead of the editor's shortcuts, never while typing):
  Space play / pause, ← / → ±10 s (instead of turning pages), Shift+← / → the
  previous / next burst of writing. The recordings sheet shows each
  recording's date, (kept) duration and size and the total; tap plays, ⋯
  renames, trims (or resets the trim), exports or deletes; long press or "Select" picks several to export or
  delete at once. Export hands the audio file (`.aac` with the parts
  joined; browser recordings in parts as one `.webm` / `.m4a` per part)
  to the existing save / share path (`platform/file_export`: save dialog on
  desktop, share sheet on Android, download on the web). `NotebookAudio`
  owns all of it per open notebook (one per notebook, shared by its editors
  through `SharedNotebook`; saved when its last editor closes) and reloads when
  sync reports `recordingsOfNotebooks`. `RecordingController.busy` keeps to one
  recording at a time across notebooks.

## Input (`ink/input/ink_input_controller.dart`)

Raw `Listener` pointer events (no gesture arena → no latency, full pressure data):

- **Stylus** draws; the **eraser end** erases; the **side button held** (S Pen) does
  the user's `PenButtonAction` (`input/stylus_buttons.dart`): erase, lasso (a selection
  made that way stays live — pressing on it moves it, pressing elsewhere drops it and
  draws again) or nothing.
  A stylus touching down cancels a stroke a resting palm may have started.
- **Touch**: with *stylus only* (palm rejection) on, fingers pan/zoom; off,
  one finger draws and a second finger turns it into a pinch.
  Stylus-only switches on automatically the first time a stylus is used.
- **Mouse**: left draws, middle/right drag pans (a right click without dragging opens the
  context menu), wheel scrolls, Ctrl+wheel zooms.
- **Trackpad**: two-finger pan, pinch zoom.
- **Canvas gestures** (`input/canvas_gestures.dart`) watch the same events without
  claiming them: a quick, still two-/three-finger tap (`MultiFingerTapDetector`:
  ≤ 300 ms, ≤ 24 px travel) → undo / redo; a still one-finger long press with a
  navigating finger, or a right click (`LongPressDetector`, `SecondaryClickDetector`)
  → the canvas context menu; a navigating finger's double tap (`DoubleTapDetector`:
  two ≤ 250 ms taps ≤ 300 ms apart, ≤ 40 px from each other, ≤ 18 px travel, never
  with a second finger down — so two-finger taps stay undo) → **double-tap zoom**
  (`features/editor/double_tap_zoom.dart`: the page fit — 100 % on canvases — ⇄ 2× or
  the zoom last left this way, about the tap, animated). Fingers that draw (palm
  rejection off) never zoom: their taps are dots. Palm safety: taps, double taps and
  long presses are ignored while a stylus touches, or was seen touching or hovering
  within 600 ms. The recognisers live in `CanvasGestures`, so
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
  pressure filter, the causal radius smoothing, the start and tip rules,
  the pen-down and pen-up hooks (`HookFinder`), the dot rule and the
  shaper's position smoothing — in screen pixels (a view is a translation
  and a uniform scale, so the rules scale with it). Each piece is the hull
  of two circles. With the stabiliser on, it draws what Flutter's live
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
  to 1e-15).
- **Prediction** (`WetInkTip`, `WetInkPrediction`): androidx.input's
  `MotionEventPredictor` (Android's own predictor where the device has
  one, else a Kalman filter) extrapolates the pen; `WetInkPrediction`
  (pure Kotlin) draws only a short, cautious piece of it, at the tip's
  radius: points at most 10 ms ahead, no further along them than the recent
  speed covers in 10 ms, 6 tip radii, or the length over which a straight
  line leaves the current curvature by a quarter radius; scaled smoothly
  to nothing while the pen slows down, turns (15–45° between the last two
  8 ms windows) or lifts (pressure falling or low), and none in the first
  16 ms. The pen-up's frame has no tip at all (no prediction, and no line
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
  constant pressure, with no stabiliser
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
  page laid out (single-page flow) nothing else is reachable.
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
  custom), size and trail duration (0.3–3 s), set in the tool's options popup
  (`LaserOptionsPanel`, with a live preview). The old painter drew two lines per sample, one
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
  (stabiliser) and the zoom it was written at (`unit`); required and parsed
  strictly (as is the tool: an unknown one makes the stroke malformed). So
  a stroke renders identically on every device, whatever the local tool
  settings.

**Highlighter** strokes are translucent with flat chisel ends (the pen has
round caps), drawn before other ink in each chunk picture, and the live
highlighter stroke is painted on a layer beneath committed ink.

User customisation lives in `ToolSettings`, persisted as JSON in the local
`settings` table: per ink a `PenConfig` with **independent quick colours and
quick widths** (1–6 slots each, one of each selected) and feel settings
(pressure sensitivity, stabiliser, straight lines; opacity for the
highlighter — the pen is always opaque), plus eraser options,
hold-to-straighten and the 8 **recent colours** (`RecentColors`: colours
newly put into an ink's quick slots, noted when the tool options popover
closes; shown in its palette and in the selection's Style colours).
Parsing is strict (`PenConfigJson`,
`EraserConfig.fromJson`): a part with a missing or invalid field keeps its
defaults as a whole.

The ink panels (`features/editor/pen/`) are self-contained:
`PenOptionsPanel` (live preview, pressure sensitivity, stabiliser, hold to
snap) and `HighlighterOptionsPanel` (preview, opacity, stabiliser, straight
lines, hold to snap); Reset restores the feel settings, not the slots. The
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
a tool: Image…, Take photo on Android, and in notebooks Pages from PDF… and
Page with template…).

- **`ToolCluster`** (`toolbar/tool_cluster.dart`): the tool buttons in fixed
  cells (44 dp with a pointer, 48 on touch) over one neutral `xs` plate
  (`Surfaces.pressed`) that slides to the active tool in `Motion.fast`.
  Inking tools show their colour as a bar under the glyph. Tap selects; tapping
  the active tool, a long press or a right click opens its options.
- **`ToolStrip`** (`toolbar/tool_strip.dart`): the active tool's quick
  controls, cross-fading as it changes: Pen and Highlighter, their **colour
  slots then width slots** (`pen/ink_strip.dart`; 3 + 3 by default, 1–6 each,
  independent); Eraser, three size slots; Shapes, a kind button and the pen's
  slots; Laser, three colour slots (red, green, blue); Lasso and Text, none.
  Slots (`pen/slot_button.dart`) are 22-dp swatches or neutral dots at real
  size (4–20 dp) in 36-dp cells (44 on touch); the selected one gets a 2-px
  `onSurface` ring with a 2-px gap. Tapping the selected slot, a long press or
  a right click opens the tool's options on it. Picking a quick colour or width
  from a tool that draws no ink switches to the pen.
- **One options popover** (`toolbar/tool_options_popover.dart`,
  `showToolOptions`): `showAdaptivePopover`, anchored and 320 dp wide, a
  sheet on phones; edits apply live. Sections: inks (`InkOptions`: title and
  Reset, live preview, Colour with − n + for the slot count, the selected
  slot's colour from the palette, recent colours or Custom (HSV, inline),
  Width with − n + and a slider for the selected slot, then *Feel* collapsed);
  `EraserOptionsPanel`; `LassoOptionsPanel` (what it does); Shapes
  (`ShapeOptionsPanel` and "Hold to snap shapes"); `TextOptionsPanel`;
  `LaserOptionsPanel` (`ToolSettings.laser`: dot / trail, colours, size,
  trail length).
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
  `ToolbarPlacement.floating` (⋯ → View, or Settings → Writing) it is a
  `raised` palette dragged by its grip (`ToolbarSlot`; it covers no edge).
  The strip's width is reserved at its widest across tools, so switching
  tools moves nothing and never changes the layout.
- **Rebuilds**: the cluster, strip and switcher listen to `ToolSettings`
  themselves; the chrome host, top bar and canvas never rebuild on a tool
  change (`test/toolbar_test.dart` counts rebuilds). `ToolbarMeasure`
  notifies only when the reserved strip width changes (slots added or
  removed), which may move the toolbar between the bar and its row.

Shortcuts: P / H / E / L / S / T / K, 1–6 colour slots, [ / ] thinner /
thicker (plus the canvas keys `+` `-` `0` Shift+1 Home). Palm rejection is
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
   dropped run (a cusp tip, `PointSpacing`); pressure is filtered
   (`PressureFilter`). **Ink shows from the first sample**, under the nib
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
     start, so samples never move as the stroke grows;
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
     the pressure gives (flat for the highlighter).
4. **`RibbonEmitter`**: the outline is the envelope of the circles along
   the line. A *run* of samples becomes **one closed contour** — left side
   forward, a cap, right side back, a cap — whose sides are cubic Béziers
   fitted to the offset points (within 0.002–0.004 world units, tangent at
   every join), so edges are smooth at any zoom and a whole stroke is a
   handful of contours (2–24 sub-paths in the Ink Lab cases, against
   thousands of capsules before). Runs end where the envelope would fold
   (corners, bends tighter than the radius); such segments are exact
   capsules (`capsule_emitter.dart`). All contours wind the same way, so
   the non-zero fill unions them. Runs are cut at fixed sample indices
   (`block`, ≈ 24 screen px), so pieces can be frozen.
5. **Live stroke** (`live_stroke.dart`, `LiveStrokeBuilder`): per frame,
   only new points are fed to the shaper; pieces that became final are
   appended to a **frozen path** once, and only the **tail** after them is
   rebuilt (≈ 20 µs per frame on desktop, flat with length). The tail
   starts with a round cap inside the frozen part, so opaque ink fills
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
Optionally only highlighter ink is erased. With *auto-deselect*
(`EraserConfig.autoDeselect`, off by default) an erase stroke made with the
Eraser tool switches back to the ink used before it, pen or highlighter
(`ToolSettings.eraserStrokeEnded`); the S Pen side button and the eraser end
are temporary anyway and leave the tool alone. Both modes test against the ink as
rendered: its radius at each point depends on pressure, thinning and the pen's
easing (`StrokeHitTest.inkRadius`), not just the nominal width.

## Persistence

`package:sqlite3` (bundles SQLite via build hooks on every platform).
`AppDatabase._createSchema` creates the whole schema (`PRAGMA user_version`
1). Later schema changes append a migration to `AppDatabase._migrations`;
once released, never edit one.
All writes go straight to SQLite; in-memory state is a cache.

## Platforms (`platform/`)

Platform differences live behind conditional exports
(`export 'x_native.dart' if (dart.library.js_interop) 'x_web.dart'`), so no
`dart:io`, `dart:isolate`, `dart:ffi` or `path_provider` code is compiled for
the web:

| Concern            | Android / Linux / Windows                     | Web                                              |
|--------------------|-----------------------------------------------|--------------------------------------------------|
| SQLite (`sqlite_connection`) | FFI, bundled SQLite, WAL, `<app support>/len.db` | `sqlite3.wasm` + IndexedDB VFS (`len`), no WAL |
| Blobs (`blob_backend`) | files                                     | IndexedDB store `len_blobs`                      |
| App dir (`app_directory`) | `path_provider` app-support dir         | none                                             |
| Canvas reads (`stroke_reader`) | background isolate, own connection  | UI thread, time-budgeted slices (`SlicedStrokeReader`) |
| Export (`file_export`) | save dialog / share sheet                 | browser download                                 |
| Single instance (`single_instance`) | one process (desktop runners forward later launches) | Web Lock: a second tab waits ("open in another tab") |
| Incoming files (`incoming_files`) | Android: intents via `IncomingFiles.kt`; Linux / Windows: command line + forwarding from a second instance | PWA `launchQueue` (File Handling API) |
| Handwriting (`handwriting_recognizer`) | ML Kit Digital Ink on Android; none on Linux / Windows | none |
| Stylus samples (`stylus_samples`, `low_latency_ink`) | Android: historical `MotionEvent` samples + low-latency overlay; others: none | none (browsers deliver all samples) |
| Audio (`audio_files`) | capture to a temp file, play the blob file; Android: microphone permission, ExoPlayer, foreground service for background recording; Linux: `parecord` + `ffmpeg` on the `PATH` to record, GStreamer to play; Windows: Media Foundation | `MediaRecorder` into memory (secure origins only), playback from a blob URL |

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
(`app/tool/fetch_sqlite_wasm.sh` refreshes it). The IndexedDB VFS keeps the
database in memory and writes changes back asynchronously, hence the
one-tab lock. The sync server must allow the app's origin (CORS,
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
from nixpkgs): first visit online, then with the server stopped and the
browser offline the app starts and lists the notebook drawn in on the first
visit.

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
  `Icons.gesture_rounded`, as in the sidebar logo) writes the web icons,
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
  (desktop entry with PDF/image MIME types and `%F`, icons) and
  `install-desktop-entry.sh`, plus AppStream metadata (`share/metainfo`); the
  runner loads its window icon from there and is single-instance (files
  opened later are forwarded to the running Len). `runner/window_state.cc`
  restores the last size, maximised state and (X11 only; Wayland
  compositors place windows) position from `<data dir>/dev.len.len/window.ini`,
  clamped to the monitor, saved at shutdown (closing the window quits the
  application without destroying it); minimum size 360×400. **Flatpak:**
  `linux/packaging/flatpak/dev.len.len.yml` repackages the release tarball on
  the GNOME runtime (GTK 3, GStreamer); file access through portals. Audio
  recording needs `parecord` + `ffmpeg`, which the runtime lacks, so it does
  not work in the Flatpak yet. No AppImage (the tarball + Flatpak cover it).
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
  server image) and `release.yml` (on `v*` tags; see README *Release*).

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
  and filters/sorts in memory (`LibraryQuery`). `LibraryActions` adds the dialogs and
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
  (`test/perf/library_perf_test.dart` builds 200 notebooks and counts card builds). Folders are
  a wrapping row of equal compact tiles above the notebooks.
- **New… tile.** On wide screens the notebook grid starts with a cover-sized "New…" tile
  (`NewNotebookTile`, `LibraryContent.showsNewTile`) in the library root and in folders (not
  in favourites, trash, search, selection or list layout); ⊕▾ creates everywhere else. Phones
  get the FAB instead, hidden while an empty state offers its own button.
- **New notebook sheet** (`new_notebook_sheet.dart`, `new_notebook/`): one column (title,
  Notebook / Canvas, `PaperRow` with the recent papers and "All templates…" → the template
  picker, `CoverRow`, page size) with `NotebookPreview` beside it in the dialog and as a strip
  on phones. The papers come from `recentPapers` (`AppPreferences.recentPapers`, filled up with
  defaults; canvases only tiling papers); creating a notebook records its paper.
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
  implementation). Models are BCP 47 tags (`RecognitionLanguages`); the
  language follows the device locale unless chosen in the settings.
- **`RecognitionService`** (in `AppServices`) holds the language, the
  model's state (checks it at start; with indexing on, a missing model is
  downloaded over Wi-Fi; the settings and "Convert to text" download on
  demand with a progress bar — ML Kit reports no byte progress) and the
  `HandwritingIndexer`. Settings: language, "Search handwriting" (off
  forgets recognised text, on re-recognises everything) and model download
  (Android manages removing models).
- **Clustering** (`InkClustering`): a surface's strokes (highlighter
  excluded) become lines and words. The unit is the median stroke height;
  a stroke joins a line whose letter band it overlaps vertically (small
  strokes — dots, accents, commas — only need their centre near it) within
  3 units horizontally, preferring the previous stroke's line when written
  within 1.5 s; lines on the same band are merged; words split at gaps wider
  than 0.6 × the line's letter height. A line's key is a hash of its stroke
  ids.
- **Index.** Local, derived and **not synced** (results depend on the
  device's model; strokes already sync, so every device can derive them —
  syncing `ink_text` would let devices without a recogniser search, see
  limitations): `ink_text(surface_id, stroke_key, language, text, rect,
  words)` — one row per line, `words` = per-word boxes when the recognised
  words match the word clusters — and `ink_text_queue(surface_id, version)`,
  filled by **triggers on `strokes`** (insert, delete, and updates of
  `deleted` / `points` / `surface_id`), so local edits, undo, duplicates and
  sync all queue their surface without any call. Triggers mirror `ink_text`
  into `search_docs` as kind `handwriting` (ref = row id), searched and
  ranked like text boxes, with page numbers.
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
library layout and sort, and the papers of the latest new notebooks. Getters always read
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
messages (`messages.dart`: `showMessage`). Floating chrome: `floating_panel.dart`
(`FloatingPanel`, the `raised` surface; `radius: Radii.pill` for pills) and `chrome_fade.dart`
(`ChromeFade`: fade plus an 8-px slide toward the edge). Also `text_prompt.dart`,
`sidebar_item.dart` (library sidebar; the selected row carries the accent). Menus opened from a
button use `MenuIconButton` / `showMenuBelow` (`menus.dart`; `MenuRow.shortcut` hints show only
where a keyboard is likely), never `PopupMenuButton`. Settings (`features/settings/`): General,
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

## Known limitations / next steps

- Canvas chunk reads run in a background isolate, but writes, page surfaces,
  thumbnails and other queries still run on the UI isolate (small and indexed).
- Far zoom-out of a huge canvas still loads every visible stroke into memory
  (LOD caps rendering cost, not memory); LOD rasters are not persisted, so they
  are rebuilt after reopening. Paged documents do not use LOD rasters yet.
- Pixel-erasing a long stroke, or moving a selection, rewrites strokes as
  new records (simple and sync-safe, but more rows than a delta).
- Text boxes: list items have no hanging indent (wrapped lines start at the
  box edge); text pasted from other apps is plain; PDF export places glyphs
  word by word without kerning; boxes with characters outside the bundled
  fonts' subsets export as images.
- Android: historical stylus samples are merged from a platform channel;
  the low-latency overlay is tuned on a Galaxy Tab S8+ only (see *Input*;
  its hand-over delay assumes a Flutter pipeline like that tablet's).
  Small floating panels over the canvas (audio player, search)
  are not cut out of its clip. Stylus tilt/orientation are received but
  unused.
- The sync token is stored in the app's SQLite database; move it to secure
  storage before shipping.
- PDF: tiles are not persisted (re-rendered after reopening) and stop at
  65536 px page width; selection is per page (not across pages); exported
  PDFs drop the source's form fields (their looks are kept) and links with
  other actions than web addresses and pages of the same file — see
  *Blobs and PDFs*.
- Audio: a recording is one blob, so it syncs only once finished and a
  recording above the server's blob limit (200 MiB by default, ≈ 7 h at
  64 kbit/s) cannot be uploaded (it stays on the device, reported as too
  large to sync); downloads hold the
  whole blob in memory. Android background recording needs the foreground
  service to start while Len is in front (it does, at the start of a
  recording); a recording in progress when Len is swiped away from the
  recent apps is saved only if that finishes within the service's grace
  period, and one in progress when the process is killed is lost. Linux recording needs `parecord` and `ffmpeg`
  installed, playback needs GStreamer with the `-good` (MP4) and an AAC
  decoder plugin; Opus/WebM recordings from Chrome/Firefox may not play on
  platforms without a WebM decoder. Waveforms come from the recorder's level
  meter (≈ the loudness of the last buffer every 100 ms), not from decoding
  the audio; recordings without one show a flat scrubber. No trimming yet;
  exporting reads the whole audio blob into memory.
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
- Handwriting: recognised only on Android (Linux, Windows and web find no
  handwriting; recognised text is not synced, so they cannot borrow it
  either); a changed surface is re-clustered from all its strokes (cheap per
  page, heavier on huge canvases); a phrase is found only within one line;
  shapes drawn with the pen are recognised like writing (usually as
  nonsense); no pause while on battery.
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
  IndexedDB asynchronously, so closing the tab within milliseconds of an edit
  can lose it. Canvas chunk reads run on the UI thread (in time-budgeted
  slices; a single large chunk still decodes in one go).
- Open with: Android shares mixing PDFs and images arrive as `*/*`, which
  Len does not register for; PDFs dropped onto an open editor are ignored (only
  images are inserted there; drop onto the library or use "Open with").
- Page reorders made concurrently on two devices converge (LWW per page) but
  may interleave differently than either device intended.
