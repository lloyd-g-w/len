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
`data` map: `text` (`TextData`: text, size, colour, bold, italic, alignment)
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

## Editor screen (`features/editor/`)

- **`EditorSession`** owns the engine side of one open notebook: `ToolSettings`, live ink,
  `InkInputController` + `CanvasGestures`, `ContentTools`, undo, and either the canvas
  `SurfaceModel` + viewport or the `DocumentController` + `DocumentCommands`.
- **`EditorScreen`** composes `EditorCanvas` (surface, "Add page" footer, content layer)
  with `EditorChrome` (`chrome/`): `EditorTopBar` (back, pages, bookmark, title — tap to
  rename — undo/redo, export, focus, "⋯" `EditorMoreMenu`; a phone variant keeps the
  essentials and moves the rest into the menu), `ToolbarSlot` (hosts the pen toolbar at
  the top, bottom or floating by a grip; animated), `PageNavigator`, `GestureHud` and,
  in focus mode, only a `FocusHandle`. `ChromeLayout` says how much of each screen edge
  the chrome covers; the document pads its scroll bounds by it (in screen pixels, so it
  is re-applied on zoom), and the selection / text menus and the canvas's zoom pill and
  minimap (`CanvasView`) avoid it (passed down as `MediaQuery.padding` / insets).
  On canvases the "⋯" menu also holds the canvas entries: background (template and paper
  colour), fit content, actual size, back to start, show / hide overview. Menus report to a `CanvasGuard`, which blocks the surface while
  one is open, so the tap that closes a menu never draws.
- **Tabs** (`tabs/`): `OpenNotebooks` (in `AppServices`) holds up to 8 open notebooks,
  the active one, and each tab's `EditorViewState` (page, zoom, pan). The library opens
  notebooks through `openNotebook()`, which pushes one `EditorWorkspace` route; it shows
  the active tab's `EditorScreen` (keyed by notebook), which saves its view on dispose
  and restores it on creation. Closing the last tab leaves the workspace.
- **Page navigation**: `DocumentController.scrollToPage` animates the viewport with
  `DocumentScroller` (centre point glides, zoom eases; jumps longer than two screens
  start near the target); it stops an inertial glide first (`beforeJump`). Single-page
  flow fits the whole page and slides it in.
- **Shortcuts** (`editor_shortcuts.dart`): Ctrl/⌘+Z, Ctrl/⌘+Shift+Z, Ctrl+Y; tools
  P / H / E / L / S / T / K; 1–6 quick colours, [ / ] width; F11 or Ctrl/⌘+. focus mode;
  Ctrl+Tab / Ctrl+Shift+Tab / Ctrl/⌘+W tabs. Canvases: `+` / `-` (also with Ctrl/⌘),
  `0` 100 %, Shift+1 fit content, **Home back to start**. Paged notebooks: ← / → and
  Page Up / Down turn pages, **Home first page**, End last page. Single keys are ignored
  while text is edited.

## Templates (`domain/paper.dart`, `domain/paper_pattern.dart`)

`PaperStyle` names are stored and synced and never renamed (`lined` is wide
ruled, `grid` the large grid). `PaperPattern.of` computes a template's
geometry (lines with weights, dots) for an area, independent of the target:
`PaperRenderer` draws it on screen, in thumbnails and PNG export, and
`PdfExporter` writes the same lines as PDF vectors. Pages carry their paper
colour and size; new pages copy the current page's paper and size.

## Blobs and PDFs

Large binary data is **content-addressed**: a blob's id is the SHA-256 of its
bytes. `BlobStore` keeps a `blobs` table (size, mime, uploaded flag) and the
bytes in a `BlobBackend`: files under `<app support>/blobs/<sha[0..2]>/<sha>`
natively, an IndexedDB object store on the web, memory in tests. Its API is
path-free (`read`, `openRead`, `localPath` — null on the web). Each sync cycle first uploads
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
build hook (Linux, Windows, Android), so no system package is needed; on the
web `pdfrx` runs PDFium as WebAssembly in a worker. `PdfRenderer` opens a
blob from its file when it has one (PDFium reads on demand) and from memory
otherwise (web).

Export (`features/documents/export/`): `PdfExporter` (package `pdf`) writes
ink as filled polygons flattened from the exact outline paths the app
renders, templates as vector lines, and imported PDF pages as 150 dpi
images; PNG export rasterises a page with the same painters as the editor.
Files are saved with a save dialog on desktop (`file_selector`), the share
sheet on Android (`share_plus`) and downloaded in browsers
(`platform/file_export*`).

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
  → the canvas context menu. Palm safety: taps and long presses are ignored while a
  stylus touches, or was seen touching or hovering within 600 ms.

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

### Low-latency ink (Android, experimental; `WetInkOverlay.kt`)

Setting *Low-latency ink (experimental)*, default off. A translucent
`SurfaceView` (media-overlay z-order) sits above the Flutter view, rendered
with androidx.graphics' `CanvasFrontBufferedRenderer` (API 29+): the newest
samples of the contact are drawn into the **front buffer** as each
`MotionEvent` arrives — round-capped segments in the stroke's colour with the
outline's radius per pressure (a table sent by Dart) — so the tip appears about
a frame or two before Flutter's frame shows it. Dart (`_LowLatencySource`, a
`SampleSource` decorator) sends `begin` (contact, colour, radii) once the
contact is ink, `progress` (the newest event a built frame contains) after
each frame, and `end` after the frame showing the committed stroke. On each
`progress` the overlay *commits*: the front buffer is cleared and only the
tail Flutter may not have presented yet (samples newer than progress − 2
frames, never older than 5 frames) is redrawn in the multi-buffered layer, in
one SurfaceControl transaction, so nothing tears or flickers and the overlay
never shows more than the last few millimetres of ink, on top of identical
Flutter ink. Only opaque, round, untextured pens qualify (`WetInkStyle`):
highlighter, legacy pencil/fountain, translucent colours, erasing, tools and
straightened strokes are left to Flutter alone.
Known gaps: the overlay is not clipped to the canvas (a stroke dragged under a
toolbar shows its tip above it for a few frames), the first stroke after
switching it on is not accelerated (the surface is created then), start
tapers appear on the overlay only after the tail expires, and the radius uses
plain (not causal-smoothed) pressure, so the tip may differ from the final
outline by a fraction of a pixel.

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
More tools slot in by adding an `EditorTool` value and a descriptor. The
tools are Pen (P), Highlighter (H), Eraser (E), Lasso (L), Shapes (S; its
icon is the current shape, settings = shape picker, strip = the pen's slots,
since shapes are drawn with the pen's colour and width), Text (T; settings =
defaults for new boxes) and Laser pointer (K). For inks the strip is a row of
colour slots beside a row of width slots (dots at scaled real size) — one tap
picks either; tapping the selected slot (or long-pressing / right-clicking
any) edits it (colour picker, or slider with a live stroke preview; both can
remove the slot); `+` adds one. It lays out on one row when it fits, else on
two (phones: tools and palm rejection above, the strip below; the settings
button only if it fits — tapping the active tool opens settings too).
Picking a quick colour or width from a tool that draws no ink (lasso, text,
laser) switches to the pen. Shortcuts: P / H / E / L / S / T / K, 1–6 colour
slots, [ / ] thinner / thicker (plus the canvas keys `+` `-` `0` Shift+1 Home).

Placement is a preference (`ToolbarPlacement`: automatic / top / bottom /
floating, in the "⋯" menu and the settings); `ToolbarSlot` hosts it. *Automatic*
(`resolvePlacement`) puts it under the top bar from 960 px wide if it fits
there on one row whichever tool is active, otherwise at the bottom. The slot
measures the toolbar (one or two rows) and `ChromeLayout` uses that height for
the screen edge it covers, so document scrolling, the page navigator and the
canvas overlays (zoom pill, minimap, fit / overview buttons) keep clear of it.

### Ink rendering (`ink/render/`)

`StrokeOutline` turns points into a filled outline whose edges are smooth at
any zoom:

1. Drop duplicate samples, trim pen-down/pen-up hooks, and densify sparse
   input along a centripetal Catmull-Rom spline (mouse, touch and, without
   the merged historical samples, Android stylus input arrive at about one
   sample per frame, so fast curves arrive as chords). Only gaps wider than
   two resampling steps are filled: dense 240 Hz stylus input passes through
   point for point. Smoothing (positions, radii) is by arc length, not by
   sample count, so denser input neither flickers nor gets smoother; the
   per-sample pressure EMA (`PressureFilter`) is correspondingly lighter in
   time (≈ 10 ms at 240 Hz instead of ≈ 40 ms at 60 Hz).
2. `Centerline`: resample at a **fixed** arc-length spacing from the stroke's
   start (samples of a stroke being drawn never move as it grows), find sharp
   reversals (tips of `n`, `v`), and low-pass the positions per stretch
   between them with `2G − G∘G` (`LineFilters`): loops keep their size while
   digitiser jitter is removed; ends are continued by a local quadratic fit so
   they neither lag nor bend. At stabiliser 0 the filter only removes
   sub-pixel noise; it grows with the stabiliser and (up to 3×) with width.
3. Radii (from pressure): **causal** smoothing (two cascaded exponential
   passes) and a slope limit, both looking only backwards — the width of ink
   already drawn never changes as the stroke grows, so nothing flickers behind
   the pen tip; non-swelling and levelled ends once the stroke is complete;
   tapers.
4. `CapsuleEmitter`: the outline is the union of *capsules* — the convex hull
   of the circles at consecutive samples (nearly collinear, level runs are
   merged). Each capsule depends only on its two samples, so new input only
   adds geometry; cusps, hairpins and self-overlaps need no special cases
   (the non-zero fill unions them); neighbouring capsules share a circle, so
   edges are tangent-continuous on the outside of bends at any zoom.

`OutlineSink` lets tests record the exact segments; specimens of synthetic 240 Hz handwriting with jitter and pressure
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
| Canvas reads (`stroke_reader`) | background isolate, own connection  | UI thread (`StrokeRepository`)                   |
| Export (`file_export`) | save dialog / share sheet                 | browser download                                 |
| Single instance (`single_instance`) | one process                  | Web Lock: a second tab waits ("open in another tab") |
| Handwriting (`handwriting_recognizer`) | ML Kit Digital Ink on Android; none on Linux / Windows | none |
| Stylus samples (`stylus_samples`) | Android: historical `MotionEvent` samples + low-latency overlay; others: none | none (browsers deliver all samples) |

`app/web/sqlite3.wasm` must match the `sqlite3` package version
(`app/tool/fetch_sqlite_wasm.sh` refreshes it). The IndexedDB VFS keeps the
database in memory and writes changes back asynchronously, hence the
one-tab lock. The sync server must allow the app's origin (CORS,
`LEN_CORS_ORIGINS`, default `*`).

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
  freeform; `<layout>` minimum 360×400 dp), orientation unlocked. Release:
  `android/key.properties` signing (debug-key fallback), R8 + resource
  shrinking, `versionCode` = pubspec build number.
- **Linux:** application id `dev.len.len` (= GTK app id = `.desktop` name =
  icon name, so Wayland docks match the window). The bundle carries `share/`
  (desktop entry, icons) and `install-desktop-entry.sh`; the runner loads its
  window icon from there.
- **Windows:** PerMonitorV2 DPI awareness (manifest), initial window centred
  and clamped to the work area, minimum size 360×400.
- **CI / releases:** `.github/workflows/ci.yml` (analyze, tests, all builds,
  server image) and `release.yml` (on `v*` tags; see README *Release*).

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

## Search (`data/search/`, `features/search/`)

GoodNotes-style full-text search over notebook titles, folder names, text
boxes, the text of imported PDF pages and recognised handwriting (see
*Handwriting recognition*).

- **Index.** A local, derived table `search_docs(kind, ref_id, surface_id,
  body)` — one row per title, folder, text box or PDF page — with an FTS5
  index `search_fts` over it (external content, `unicode61
  remove_diacritics 2`, prefix indexes). It is never synced: it is created
  and filled from the synced tables by an (idempotent) migration and kept
  current by **SQLite triggers** on `notebooks`, `folders`, `elements` and
  `pages`, so local edits, duplicates and records applied by sync are
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
  candidates, best first; per-language model download / delete) behind a
  conditional export: **Android** uses Google ML Kit Digital Ink
  (`google_mlkit_digital_ink_recognition`, already on AGP 9 / built-in Kotlin;
  `MlKitRecognizer` synthesises point timestamps from the stroke's start time
  and passes a writing area and pre-context); **Linux, Windows and web** get
  `UnavailableRecognizer` (WinRT ink analysis on Windows is a possible later
  implementation). Models are BCP 47 tags (`RecognitionLanguages`); the
  language follows the device locale unless chosen in the settings.
- **`RecognitionService`** (in `AppServices`) holds the language, the
  model's state (checks it at start; with indexing on, a missing model is
  downloaded over Wi-Fi; the settings and "Convert to text" download on
  demand with a progress bar — ML Kit reports no byte progress) and the
  `HandwritingIndexer`. Settings: language, "Search handwriting" (off
  forgets recognised text, on re-recognises everything), model download /
  delete.
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
  edits arrive). Lines whose key is already stored keep their text, so
  writing a word re-recognises one line; a surface changed while it was
  being recognised stays queued (the queue row is only removed at the
  version that was read). Failures (model missing) leave the queue for the
  next change. The migration queues every surface with ink.
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
`SettingsRepository`: theme mode and accent (the app rebuilds its `ThemeData` from them),
stylus-only, two-finger-tap undo, three-finger-tap redo, stylus side-button action
(`PenButtonAction.eraser|lasso|none`), low-latency ink (Android, experimental), editor toolbar placement (and floating position),
library layout and sort. Getters always read
the store, so values written elsewhere are never stale.

## UI design system (`ui/`)

`AppTheme.light/dark({accent})` build a fidelity colour scheme from the accent with quiet
neutral surfaces, a tighter type scale and shared component themes
(`theme_components.dart`). Tokens: `Gaps`, `Radii`, `Palette` (`app_theme.dart`) and
`Motion`, `Breakpoints`, `Shadows`, `Accents` (`design_tokens.dart`).

Shared UI: `app_dialogs.dart` (`confirmAction`, `DialogIcon`, `DialogBody` width),
`menus.dart` (`MenuRow`, `showContextMenuAt`), `text_prompt.dart`. Documents UI
(`features/documents/`): `templates/` (grouped `TemplateGallery`, paper colour and page size
rows) used by the template picker and the new-notebook sheet; `overview/` (the page overview
with selection mode; `editor/document/page_overview.dart` re-exports it);
`progress_dialog.dart` (`runWithSteps` + `TaskProgress`: stage, subject, "Page x of n").
Library selection mode: `library/selection/` (`LibrarySelection` on `LibraryActions`, batch
actions, floating bar). `flows_screenshot_test.dart` and `overview_screenshot_test.dart` cover
sheets, dialogs, empty states, selection, the page overview and 1.3× text; findings are tracked
in `docs/UX_AUDIT.md`.

Visual checks: `test/screenshots/` renders the library, settings and the editor (paged and
canvas, tabs, focus mode, toolbar positions, menus, 320 dp phone; the toolbar and its popovers in
`toolbar_screenshot_test.dart`) at phone, tablet and
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
- Android: historical stylus samples are merged from a platform channel and
  the low-latency overlay is experimental (see *Input*); it has not been
  tuned on every device. Stylus tilt/orientation are received but unused.
- The sync token is stored in the app's SQLite database; move it to secure
  storage before shipping.
- PDF backgrounds are rendered as whole-page images (no tiling), so very deep
  zoom on a PDF page is capped at ~2896 px page width; exported PDFs embed
  imported pages as images rather than copying their vector content.
- Blobs are never garbage-collected (neither on devices nor on the server) —
  deleting or replacing images leaves their blobs behind.
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
  glyph highlights skip rotated PDF pages (the page is still shown); FTS5's
  `unicode61` tokenizer does not segment CJK text (prefix matches only from
  the start of a run); the editor's matches refresh on query changes and
  when the bar reopens, not live while typing into a text box.
- Web: the whole SQLite database is held in memory (IndexedDB VFS) and PDFs
  are opened from memory, so very large libraries/PDFs cost browser memory;
  browsers may evict IndexedDB under storage pressure (no
  `navigator.storage.persist()` request yet) and quotas vary. Writes reach
  IndexedDB asynchronously, so closing the tab within milliseconds of an edit
  can lose it. Canvas chunk reads run on the UI thread.
- Page reorders made concurrently on two devices converge (LWW per page) but
  may interleave differently than either device intended.
