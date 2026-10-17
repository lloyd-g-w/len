# Len — performance at scale

What a years-old library costs, how it is measured, and the numbers. The
rule: work proportional to the library never runs before the first frame or
in one event-loop turn; work on screen is proportional to the screen, not to
the notebook.

## Benchmarks (`app/test/perf/`)

`support/big_library.dart` builds the data (`BigLibrary.build`, a synthetic
years-old library) and the helpers (`turnsUntil` / `longestTurnUntil` measure
how long the UI thread is held, `bestMs`, `report`).

| File | Scenario |
|---|---|
| `library_scale_perf_test.dart` | 1,000 notebooks in 50 folders (100 favourites, 200 trashed), 10,000 pages of text and PDF text: open, scroll, search as you type, sort / layout, folder tree, content search |
| `big_notebook_perf_test.dart` | 500-page notebook (45k strokes, half PDF pages): open, go to page 500, scroll; a long session writing on 300 pages (memory, undo) |
| `overview_scroll_perf_test.dart` | page overview of 500 pages of handwriting: a fast drag, a fling and a slow drag (frame times, pages recorded, tiles left blank) |
| `sync_scale_perf_test.dart` | first full pull of 73k records (67k strokes) from a mock server (records encoded ahead, so serving costs the shared thread only a copy) while the app writes every 25 ms (`LEN_PULL_IN_PLACE=1`: applied on the UI isolate, as on the web), then an incremental and an idle sync |
| `scribble_perf_test.dart` | scribble to erase on very long strokes (writing, and a scribble going on): µs per pen move at 4k and 64k moves must stay flat |
| `restore_scale_perf_test.dart` | restore a 21 MB library backup (200 notebooks, 45k strokes, 12 records parts): total time and the longest UI turn |
| `startup_scale_perf_test.dart` | launch with a 335 MB database (325k strokes, 500 blob rows = 5 GB of PDFs, 200 expired trashed notebooks): what runs before the first frame, then trash purge and blob GC |
| `minimap_perf_test.dart` | canvas of 10,000 strokes over 40,000 × 25,000 (3,762 chunks): a pan frame and a pen move with the minimap on and off (widgets rebuilt, render objects painted), and the map's own work (density read, merge, paint) |
| `zoom_window_perf_test.dart` | three full ruled pages: a frame of the page view scrolling with the zoom window open and closed; 60 words written in the box against 60 on the page |
| `ink_render_perf_test.dart` | (with the Ink Lab cases) 2,000 overlapping shapes outlined and filled: first screen of tiles, pan frames |
| `scan_perf_test.dart` | a synthetic 12-MP photo: detection, preview, page render and JPEG; the longest UI stretch of the web's banded path |
| `version_history_perf_test.dart` | making a version of a 1,000-page PDF and of a 50k-stroke canvas: first, after one stroke, unchanged (total, UI turns, peak RSS, blobs written) |
| `version_history_view_perf_test.dart` | the history view of 200 versions of a 100-page notebook and of 12 versions of a 50k-stroke canvas: open, thumbnails, scroll to the oldest |
| `connectors_perf_test.dart` | connector repair after a pull (500 boxes, 1,000 arrows, 5,000 strokes); dragging a box with 50 / 200 arrows (per move, editor frame) |
| `shapes_perf_test.dart` | hold to snap at the end of 2k–10k-point strokes; a curve of 20 / 64 anchors among 2,000 shapes: handle hit test, hover, handle drag |
| `live_collab_perf_test.dart` | live push tick; remote ink by length; editor frames with three other devices writing and pointing; presence changes |
| `mouse_ink_perf_test.dart` | mouse ink early and late in a 20,000-move stroke at stabiliser 0 / 30 % / 1: smoother, pipeline, live outline, one path; editor frames |

Run one file with `tool/light.sh flutter test test/perf/<file>`. The widget
benchmarks run in debug JIT inside the test harness: compare numbers with each
other, not with frame budgets (release is several times faster), and expect
±30 % noise on the shared machine. To see where time goes, run with
`--enable-vmservice` and wrap the part in `CpuProfile` (`support/cpu_profile.dart`).

## Before → after (branch perf/scale, Oct 2026)

| Scenario | Before | After |
|---|---|---|
| Startup, 200 expired trashed notebooks | 8 s purge **before** the first frame | after it, one notebook per turn: longest turn 36 ms |
| Delete a notebook | ≈ 100 µs per stroke (one statement each) | one `UPDATE` per surface |
| Blob GC | before the first frame; tombstone purge scanned every stroke | 20 s after launch; purge is an index range in batches of 2,000; longest turn 316 → 54 ms; reference scan 101 → 33 ms |
| First full pull | 240 µs a record; UI blocked 115 ms median per 500-record page | 104–139 µs a record; slices of 64: UI turns p50 5 ms, p99 ≈ 40 ms; RSS +55 MB |
| Incremental sync (4 records) / idle sync | — | 9–15 ms / 5 ms |
| Long session, 300 of 500 pages written on | 301 pages loaded, +554 MB | 25 page models (9 with render caches), +200 MB; undo reaches 200 steps on ≤ 24 pages |

## Before → after (branch perf/sync-parse, Oct 2026)

Measured back to back on the same machine (debug, harness).

| Scenario | Before | After |
|---|---|---|
| First full pull, 73k records | 95–97 µs a record, 147 pages; UI turns p99 19 ms, max 62–67 ms; RSS +73 MB | 62–67 µs a record, 74 pages; p99 14–15 ms, max 39–42 ms; RSS +105 MB (page cache, a page fetched ahead) |
| Overview, one fast drag through 500 pages | frames median 73 ms, max 154 ms | median 57 ms, max 113 ms |
| Library sort / reload, 17 cards on screen | sort by edited 184 ms, reload 115 ms, every card built | 60–78 ms / 72–82 ms, no card built; search keys 640/300/196/157/160/143/108 → 626/304/137/109/65/65/57 ms |

- **Pull.** A page is decoded in a worker isolate (`platform/pull_decoder.dart`;
  the web keeps decoding on the UI thread): JSON, record checks and live strokes
  parsed into their rows (`StrokeRow`; a stroke within one chunk is checked on
  its encoded points without building it, and its base64 is dropped). Pages
  are 1,000 records (the server's limit) and the next one is fetched while one
  is applied; slices are 4 ms of records instead of 64 records, with a turn
  between pages too (the next page is often in already). A 16 MB SQLite
  page cache (2 MB before) is most of the throughput: writing rows at random
  ids reread index pages. Decoding in place costs 30–40 ms a page; the
  remaining long turns are slices plus a garbage collection (the worker shares
  the heap) or a commit. What remains is SQLite: ~60 µs a stroke row with its
  chunk index (2M strokes ≈ 2 minutes, from ~3).
- **Overview.** The ⋯ of each tile (an IconButton with a tooltip: a quarter of
  a tile's build) is completed a few a frame and not while the grid scrolls
  (`StaggeredBuild`; the glyph stands in and opens the menu too). Thumbnails no
  longer on screen are dropped from the recording queue. The benchmark now
  drags in one gesture (separate drags left the grid idle between frames).
  Recording the thumbnails is still about half of each frame in the harness
  (its time-boxed batches all run within a pump); a per-grid drag target was
  measured at ~1 ms a frame and left as it is.
- **Library.** Cards and rows are found by notebook id, and the same card
  widget is used again while its notebook, caption and selection are unchanged
  (`reload` keeps unchanged notebooks as the same objects). A sort that
  changes the captions (by created) or the cards shown (by name), a layout
  switch and opening a folder still build what they show.
- **Blob GC.** Left as it is: a watermark can't make an incremental reference
  scan correct. A row's references can only be dropped by changing it, but
  whether that released a blob depends on every other row (a reference count
  per blob would have to be kept), and pulled rows keep their remote versions,
  so `updated_at` is no change log.

## Before → after (branch review/round11, Oct 2026)

Today's features (minimap, zoom window, shape fill, notebook styles, scan),
counted in the harness (`debugOnRebuildDirtyWidget`, `debugOnProfilePaint`);
times are debug JIT on a machine at load 20, so the counts are the numbers
to trust.

| Scenario | Before | After |
|---|---|---|
| Canvas pan frame, 10k strokes, minimap off | 38 rebuilds, 77 render objects painted, 10.4 ms | 1 rebuild, 16 paints, 3.6 ms |
| Same, minimap on | 38 rebuilds, 96 paints, 12.1 ms | 1 rebuild, 17 paints (the map's painter alone), 4.2 ms |
| Page view scroll frame, zoom window open (closed: 3 rebuilds, 69 paints) | 19 rebuilds, 182 paints; the box's paper repainted every frame | 11 rebuilds, 82 paints; the box untouched |
| Pen move in the zoom box (steady) | 4 live-ink layers | same; per word ~290 more paints than on the page (the box and frame follow each stroke) |
| Scanned page on the web: longest UI stretch | ~480 ms (Dart JPEG encoder, VM; slower in JS) | 11 ms (render bands; the browser encodes) |

- **Pan frames.** The zoom pill rebuilt on every pan (only its scale is
  shown); the selection menu and the text box editor, with nothing to show,
  rebuilt with the view, and under the editor's `LayoutBuilder` any rebuild
  lays out and repaints the whole editor layer; the link layer and the
  minimap had no repaint boundary. Each now listens to the view only while
  it shows something, and the painters that follow the view are layers of
  their own.
- **Zoom window.** The box's paper listened to the main view (`ZoomHost.changes`)
  though it shows the frame's surface; it now listens to `ZoomHost.surfaces`.
  The frame overlay (it moves with the page) and the box are repaint
  boundaries.
- **Minimap.** Its content costs nothing per frame: 3,762 chunks are read in
  5 ms (reader isolate), merged into 999 blocks in 1–2 ms (UI thread, half a
  second after the last edit) and painted in 0.7 ms. Writing is unaffected
  (8.3 → 8.6 paints a move; the map steps aside).
- **Shape fill.** 2,000 overlapping shapes: tiles 2.5–2.7 s for the first
  screen and pan frames p50 22–24 ms whether outlined or filled (fill paths
  are memoised per stroke, drawn into the same tiles).
- **Scan.** Natively all of it runs on worker isolates: detection 30 ms
  (800 × 600), a 320-px preview 11 ms, a 2,115 × 1,781 page 280 ms plus a
  480 ms JPEG. On the web the page renders in 64-row bands; its encoding
  now goes to the browser (`OffscreenCanvas.convertToBlob`), Dart's
  encoder only where that is missing.
- **Notebook styles.** Two queries of a small table when the new-notebook
  sheet opens; nothing at startup.

## Paged scroll and scan drag (branch perf/paged-scroll, Oct 2026)

Counted as in round 11 (`test/perf/paged_scroll_perf_test.dart`,
`scan_screen_perf_test.dart`, `zoom_window_perf_test.dart`; the counter is
`test/perf/support/frame_counts.dart`): three ruled pages of handwriting
with two text boxes and an image each, or an imported two-page PDF, in a
1000 × 1300 editor, 120 frames scrolling back and forth. Times are debug
JIT on a loaded machine; trust the counts.

| Scenario (a frame) | Before | After |
|---|---|---|
| Scroll, plain pages, top | 3 rebuilds, 69 paints, 5.9 ms | 0 rebuilds, 8 paints (the page layers), 2.1–3.6 ms |
| Scroll, plain pages, "Add page" in view | 41 rebuilds, 92 paints, 6.9 ms | 0 rebuilds, 10 paints, 3.0–4.8 ms |
| Scroll, PDF pages | 3 rebuilds, 69 paints, 2.8 ms | 0 rebuilds, 8 paints, 1.0–2.3 ms |
| Scroll, PDF text selected (menu shown) | 158 rebuilds, 210 paints, 15–16 ms | 0 rebuilds, 18 paints, 2.8–5.5 ms |
| Scroll, zoom window open | 8 rebuilds, 80 paints | 0 rebuilds, 20 paints, 4.9 ms |
| Scan screen, corner drag (3 pages) | 439 rebuilds, 247 paints, 25.9 ms | 2 rebuilds, 6 paints, 4.1 ms |

- **Why a small rebuild cost the whole layer.** The editor sits under a
  `LayoutBuilder` (`EditorScreen`): any widget rebuilt below it lays the
  builder out again, which repaints everything up to the next repaint
  boundary, i.e. the whole editor layer (~60 render objects). So the
  goal per scroll frame is no rebuild at all: whatever follows the view
  does so by painting (`CustomPainter(repaint:)`) or by layout
  (`SingleChildLayoutDelegate` / `MultiChildLayoutDelegate` with
  `relayout:`), behind its own `RepaintBoundary`, and rebuilds only when
  what it shows changes.
- **PDF layer.** Its builder listened to the view (and preloaded the
  pages' text in `build`). Without a selection it now builds nothing;
  preloading follows the view by listener. With one, the highlight
  painter repaints on its own layer, and the handles' targets and the menu
  (`PdfSelectionMenu`) are placed at layout time; they rebuild when the
  selection, the text, the document or its ink change.
- **Add-page footer.** Its button was rebuilt per frame to move it; it is
  now placed by a layout delegate behind its own boundary and rebuilds
  only when it enters or leaves the screen.
- **Zoom window frame.** Same treatment: painted and placed from the
  view, rebuilt only when the frame enters or leaves the screen.
- **Scan corner drag.** `ScanSession.setQuad(preview: false)` notified the
  session, so the whole screen (app bar, strip, controls) rebuilt per move.
  A drag now notifies `ScanSession.outline`, heard only by the corner
  editor (tight, so it is laid out alone, behind a repaint boundary); the
  session still notifies when the strip (a page without a preview yet
  shows the outline's shape) or Whole photo changes.

## Web long tasks (branch perf/web-long-tasks, Oct 2026)

Measured with the walk-through (`tool/web_explore.sh`, Chromium only,
headed under Xvfb with SwiftShader, a shared machine under load). Each long
task was attributed with `LEN_EXPLORE_PROFILE=1`, which now prints, per
main-thread task over 200 ms (from a trace), the frames that took its time
and the app functions it ran under.

| Step | Before | After |
|---|---|---|
| Restore (JS) | 13 tasks, max 2.0 s; the import's own: 1.2–2.2 s a records part (Dart inflate 0.3 s, JSON 0.4 s, writing 1.1 s, one turn) | 11 tasks, max 1.5 s, none the import's: shader compiles, thumbnail read-backs |
| Restore (Wasm) | — | longest task 171 ms |
| Open big notebook (JS) | 36–42 tasks, max 1.2–2.2 s | 32 tasks, max 1.8 s (a shader compile); the rest tile read-backs |
| Open big notebook (Wasm) | — | longest task 98 ms |
| Every other step after start (Wasm) | — | longest task ≤ 103 ms |
| `restore_scale_perf_test` (debug VM) | 13 turns, longest 516 ms, 3.2 s | 320 turns, p99 48 ms, longest 200 ms (the final transaction), 3.5 s |

- **Import.** A records part (~4 MB, thousands of records) was inflated by the
  archive package in Dart, decoded and parsed whole, then written in one
  transaction, all in one turn. Browsers now inflate it with
  `DecompressionStream` and decode it with `TextDecoder` (`platform/browser_inflate`),
  and records are parsed and written in 8 ms slices, a transaction each, with
  a turn between them (`LenArchiveReader.sliceBudget`). A backup's contents
  (the "Restore this backup?" question) parse only up to its first page. The
  final transaction (notebooks added, everything marked for sync) stays one:
  ~160 ms for 45k strokes in the harness.
- **The walk measured itself.** Its IndexedDB reads (`query`, 0.7–0.9 s each
  for a 30 MB database, base64 in the page) were counted as the restore's long
  tasks; they are now left out (`probe`). A reloaded page's tasks were
  skipped (its list restarted below the count already seen).
- **What remains is the renderer's, not the app's.** In the JavaScript build
  every remaining long task is CanvasKit's GL work on the main thread, slow
  under software GL: shader compiles (`getShaderParameter` /
  `getProgramParameter`, 0.2–1.5 s whenever something new is drawn), pixel
  read-backs (`Picture.toImage` / `toImageSync` read the pixels back:
  `readPixels` 0.2–1 s per ink tile, thumbnail or LOD raster, which is where
  the GPU work actually runs), resizing the shared picture-to-image surface
  whenever the size asked for changes (0.1–0.4 s) and, at startup, WebGL
  contexts: flutter.js probing WebGL support (0.6–0.9 s), CanvasKit's
  context (1.0–1.3 s), the first frame (1.0–1.5 s). The app's own startup
  work (the schema check's scratch database, opening the database) is
  ~0.15 s. On a real GPU these are milliseconds. The WebAssembly build
  (Skwasm renders off the main thread) shows the app's own work: nothing
  over 200 ms once started, so the walk now fails a WebAssembly build with a
  task over 500 ms in any step once the page has started (it was the big
  notebook only).

## Leftovers 2 (branch perf/leftovers-2, Oct 2026)

Debug JIT in the harness on a shared machine; trust the counts.

| Scenario | Before | After |
|---|---|---|
| Overview, 500 pages, fast drag (60 frames at 25,000 px/s, stops mid-grid) | frames median 84–91 ms; 476 pages recorded while dragging | median 67–72 ms; 6 recorded while dragging (before it measures fast), 20 once it rests |
| Overview, fling at 12,000 px/s | 142 frames, median 11 ms; 162 pages recorded | median 4–7 ms; 42 recorded |
| Overview, slow drag at 300 px/s | median 2–3 ms; no tile blank for a frame | same |
| First pull, 73k records, the app writing every 25 ms (`LEN_PULL_IN_PLACE=1` for before) | 5.8 s (79–80 µs a record); UI thread busy 4.1–4.2 s, turns p99 6–7 ms, 5–6 over 16 ms (max 37–43 ms); the app's writes waited p50 0.12 ms, p99 0.3–1.2 ms | 6.7–7.1 s (92–97 µs); UI busy 0.72 s, turns p99 0 ms, 4 over 16 ms (max 33–34 ms, as before: not the pull's); writes waited p50 0.7–1.0 ms, p99 3.1 ms, max 3–34 ms |
| Incremental sync (4 records) / idle sync | 7–8 / 4–5 ms | 8–9 / 4 ms (in place, as before) |
| Scan screen, corner drag (a frame) | 2 rebuilds, 6 paints, the one painter drawing the whole photo (≤ 1,600 px) and the loupe's copy of it; 2.7 ms | 2 rebuilds, 7 paints: the photo's painter not at all (a layer of its own), the outline painter's loupe draws only the 37-px patch it shows; 3.0–3.6 ms |

- **Scan corner drag.** The photo is painted by its own painter behind a
  `RepaintBoundary` and repaints only when the photo or its place changes;
  a move repaints the outline, the dimming, the handles and the loupe. The
  harness can't time rasterising, which is where the saving is (one full
  photo `drawImageRect` with mipmaps a frame, two with the loupe); the
  benchmark checks that the photo's painter stays out of the frame. The
  frame counter now names every custom painter and leaves out boundaries
  that are only composited again.
- **First pull in a worker.** A pull whose page is 64 KB or more (a first
  sync, a big catch-up) natively starts a worker isolate with its own
  connection (see ARCHITECTURE *Sync*): pages go there as bytes, are decoded
  and applied by the same `PullApplier` in 8 ms slices with 1 ms between;
  the UI thread only fetches them. Safe as a second writer because every
  transaction now begins `IMMEDIATE` with a 5 s busy wait (a busy handler
  that sleeps, `waitWhenBusy`), and the app's
  transactions raise a shared counter (`SharedWriteSignal`, `ffi`) that
  makes the worker commit after the current record and wait: the app's
  write waits for the lock's first 1 ms poll instead of a slice (without
  the signal: p99 10–12 ms, max ~50 ms, a poll missing the gaps). Triggers
  fire on the worker's connection; its commits are announced on
  `AppDatabase.commits` (the handwriting indexer wakes on them); what
  changed comes back per page. `sync_worker_test.dart` runs the sync
  tests (deletion races, recovery, the convergence properties) with every
  pull in a worker. The cost: the pull takes ~15 % longer (the pauses, the
  waits for the app). The web and small pulls keep the 4 ms slices on the
  UI thread.
- **Overview while scrolling fast.** `FastScroll` (`ui/fast_scroll.dart`)
  measures the grid's speed frame to frame (a drag reports no velocity, so
  `Scrollable.recommendDeferredLoadingForContext` alone sees only flings);
  over two viewports a second, or a fling its physics would defer for, the
  `ThumbnailCache` neither records nor rasterises. Pages scrolled past leave
  the queue; those on screen are recorded once it slows or rests 100 ms.
  The benchmark (`overview_scroll_perf_test.dart`) also flings and drags
  slowly: at 300 px/s nothing is deferred and no tile is blank for a frame.
  Profiled after the change, a fast-drag frame is all framework build and
  layout of the tiles coming in, so the earlier "half of each frame" was
  too high.

## Web read-backs (branch perf/web-readback, Oct 2026)

The JavaScript build (CanvasKit) makes every picture into an image on the
UI thread: `Picture.toImage` is `toImageSync`, which draws it on one shared
offscreen surface (its own WebGL context, so the image can't stay on the
GPU) and reads the pixels back. There is no read-back-free way to make an
image of a picture there, and keeping pictures instead would replay all
the ink of the screen every frame, which is what the tiles avoid. So the
work went into fewer, batched read-backs. The walk-through now counts, with
`LEN_EXPLORE_PROFILE=1`, the read-backs per step by size, the resizes of the
surface read from and the shaders compiled (`gl:` lines, `report.json`).

What each cache needs: ink tiles, level-of-detail rasters and page
thumbnails are only drawn (the persistent LOD store that encodes PNGs is
native only); exports, the selection image for other apps and user
templates need pixels and keep their read-backs; library covers
(`ThumbnailRenderer`, `toImageSync`, one 320 × 444 each) were left alone.

Cost of a read-back under software GL (CanvasKit called from the page,
SwiftShader, the walk's Chromium): ~25 ms for an empty picture, ~70 ms
more when the surface changes size; 16 rasters of 128 px with 25 paths
each 1.06–1.54 s one by one, 72–102 ms on one 512² atlas; 512-px tiles of
150 paths 171 → 98 ms for 4 on a 1024² atlas, 339 → 228 ms for 8. So
batching pays for small rasters (per-call cost dominates) and little for
tiles (the drawing dominates).

- **`RasterBatch`** (`ink/render/raster_batch.dart`): in the JavaScript
  build LOD rasters and page thumbnails asked for until an atlas is full,
  or a turn passes without more, are drawn side by side into a 512² atlas
  (a tile's size: the surface never changes size), one read-back per atlas,
  one atlas a turn; each gets a `RasterImage` (its own handle on the atlas,
  its place, its share of the memory). Power-of-two rasters sit on
  multiples of their size, so mipmaps and minified sampling stay inside
  them (CanvasKit samples up to half a pixel past a source rectangle when
  magnifying). Tiles fill an atlas alone and are made at once.
- **Writing**: a stroke is drawn over its tiles as before, but merged into
  them once the pen rests 1.2 s (or 24 pile up over a tile) instead of
  after every stroke, so no read-back falls between two strokes of a word.
- **Loading**: a surface still loading renders no tiles for up to 1 s
  (empty meanwhile, stale images standing in), instead of every tile again
  as each part of it arrives (`ink_tiles_test`: each tile once; natively
  several times).
- Natively and in WebAssembly (Skwasm rasterises off the UI thread) nothing
  changed.

Walk-through, JavaScript, Chromium under SwiftShader on a shared machine:
two whole walks each, and for the big notebook two more runs of the
restore and `open_big` alone (`LEN_EXPLORE_BACKUP`). Read-backs count / ms:

| Step | Before | After |
|---|---|---|
| Pen stroke (`draw_pen`) | 1 / 65 ms | 0 |
| Undo, redo | 4 / 355–453 ms | 3 / 357–386 ms |
| Go to page (`shortcuts`): 2 thumbnails 68 × 96 | 2 / 48–58 ms, a resize | 1 / 44–94 ms |
| Phone width: 4 LOD rasters 256² | 4 / 184–327 ms, a resize | 2 / 135–146 ms |
| Open the big notebook (`open_big`) | 71–87 / 14.5–16.6 s (tiles and 3–6 thumbnails); step 33–36 s | 67–75 / 16.9–22.3 s; step 36–42 s |
| Whole walk | 145–161 read-backs, 7 resizes | 136–138, 5 resizes |

- **The big notebook** is ink tiles drawn by SwiftShader: ~0.2–0.5 s a tile
  whatever is done around it, ~70 of them (the screen, a tile's ring around
  it and half a screen of pages ahead, at three places). Fewer read-backs
  (tiles rendered once per load, thumbnails on one atlas) did not make it
  faster there: in the measured builds tiles also went through the batch's
  queue, behind tiles already queued for places the view had left, and the
  frames waited longer on shader compiles (3.3–3.8 → 3.6–6.5 s), i.e. on
  GPU work queued before them; the step took 0–5 s longer. Tiles are now
  made at once again, as before; that last change was not rebuilt (the
  round's build budget), so `open_big` is to be measured again.
  Measured again on main after `c27bf200` (tiles immediate again; a full
  Chromium walk with `LEN_EXPLORE_PROFILE=1`, the machine busy with other
  builds): `open_big` 72 read-backs / 18.1 s (all 512², 1 resize), 50 shader
  compiles waiting 4.1 s, step 40.1 s. The count is back in the old range;
  each read-back took ~250 ms against ~200 ms before, which tracks the load
  rather than the batching (tiles no longer queue). Software GL only: on a
  real GPU a read-back is milliseconds.
- **WebAssembly** stays clean: no problem, the longest task once started
  353 ms (the scan step's garbage collection and `convertToBlob`), the
  restore 254 ms, the big notebook 147 ms; no read-back on the UI thread.
- **Still the renderer's**: shader compiles (24–56 per step, 0.1–6.5 s
  waited under software GL) and WebGL context creation at start are the
  largest remaining JavaScript long tasks; on a real GPU and with the
  browser's shader cache they are milliseconds.

## The last day's features (branch perf/r13, Oct 2026)

Version history, its view, connectors, shape handles, live collaboration
and mouse ink, each with a new slow-tier benchmark (`-t slow`, table
above). Debug JIT in the harness on the shared 6-core machine: the
"after" run had load average 4–6 at its start, the "before" runs (the
benchmark at its own commit, before the fix) 1.6–2.1; trust ratios and
counts, not small differences. Where no before run was made, the before
is from the fix's commit message.

| Scenario | Before | After |
|---|---|---|
| Version, 50k-stroke canvas, first | 4.6 s, longest turn 1,293 ms, peak RSS +125 MB | 5.6 s in 902 turns, longest 25 ms, +22 MB |
| Version, 50k-stroke canvas, after one stroke | 3.85 s, longest turn 1,189 ms | 245 ms, longest 13 ms, 2 blobs |
| Version, 50k-stroke canvas, unchanged | 68 ms | 23 ms |
| Version, 1,000 PDF pages, first | 2.1 s, 207 turns, longest 53 ms | 4.4 s, 1,001 turns (p99 12 ms), longest 59 ms |
| Version, 1,000 PDF pages, after one stroke / unchanged | 339 / 306 ms, longest 28 / 35 ms | 351 / 295 ms, longest 20 / 32 ms |
| History view, 50k canvas × 12 versions: thumbnails | 16.5 s in one turn, RSS +1,073 MB; first frame 13.0 s | 1.9 s in 239 turns (max 50 ms), +70 MB; first frame 100 ms |
| History view, 50k canvas: scrolling | max frame 122 s | median 7 ms, max 622 ms |
| History view, 100 pages × 200 versions: thumbnails / scroll | 178 ms in one turn; scroll median 405 ms, max 664 ms | 138 ms in 12 turns; median 94 ms, max 202 ms |
| Connectors, repair after a pull (1,500 shapes, 5,000 strokes): a stroke / a box moved | 25 / 25 ms | 0.04 / 6.6 ms (median 8.6, max 39); full reload 35 ms |
| Connectors, dragging a box with 200 arrows | 566 ms a move | 4.9 ms (50 arrows 1.8 ms); commit ~50–58 ms |
| Connectors, drag frame in the editor (50 / 200 arrows) | 3.6 rebuilds, 34.4 paints | 0.6 rebuilds, 2.0 paints; 5.7 / 7.3 ms |
| Shapes, a handle of a 20-anchor curve dragged | 13.5 ms a move | 0.15–0.19 ms (64 anchors 0.18–0.20) |
| Shapes, hold to snap at 2k–10k points | (new) | 0.4–5.0 ms, flat with length |
| Live push tick (a 600-point stroke) | 1.9 ms | 1.1–1.5 ms |
| Remote ink, a message + a paint at 120 / 600 / 2,400 points | 6.3 / 25.9 / 101.5 ms | 1.0 / 1.0 / 2.1 ms |
| Editor frame, 3 remote writers / local pen + 3 writers | 13.2 / 6.0 ms | 3.0 / 3.2 ms |
| Presence join / leave, a frame | 376.5 rebuilds, 497.5 paints, 19.8 ms | 11.5 rebuilds, 497.5 paints, 10.3 ms |
| Presence, a name changes | (new) | 13 rebuilds, 500 paints, 8.1 ms |
| Mouse ink, live ink in one path at 58k samples (stabiliser 0) | 651–656 µs a frame (appended verb by verb) | 146–166 µs (a block copy; 30 %: 105, 1: 85) |
| Mouse ink, a move early → late (input / live outline) | (new) | 38 → 54 / 111 → 126 µs; editor 0.0–0.2 rebuilds, 2 paints a frame |

- **Version history** packs only runs whose content key changed
  (`version_runs`), reads stroke ids in slices with a mark check, reuses
  table runs and encodes large ones off the UI thread, links blobs in one
  statement, and waits while a pointer is down. A first version takes
  longer in total (sliced into many short turns) but no turn is long; the
  version after one stroke of a big canvas is 16× cheaper.
- **History view** loads thumbnails one after another in slices, shares
  decoded tables and strokes between versions, doesn't copy canvas
  content, sketches thin ink and paints each thumbnail once.
- **Connectors**: lines following a dragged shape are drawn as even lines
  (no outlines per move) and copies near their ends found in one query;
  repair after a pull reads only changed lines and lines attached to
  changed shapes, from a new index of live shape strokes (schema 19). The
  selection's menu and text-box semantics follow a settled listenable, not
  every move of a gesture.
- **Shapes**: a handle drag previews the reshaped shape as an even line.
- **Live collaboration**: remote ink outlines are built as points arrive
  (`LiveStrokeBuilder`); the editor chrome follows
  `SharedNotebook.othersHere`, not every presence message; the live push
  goes through cached prepared statements.
- **Mouse ink**: the live outline clones its frozen part and appends the
  tail instead of appending the frozen part verb by verb (pixels
  unchanged).

What remains:

- **History view of a big canvas**: opening still has one 2.2 s frame
  (8 thumbnails built of 50k strokes; RSS +183 MB) and a 622 ms frame
  scrolling; the 100-page notebook scrolls at median 94 ms a frame.
- **Presence join / leave and a name change** still repaint ~500 render
  objects a frame (the chrome's layer); the rebuilds are gone, the paints
  are not.
- **Live ink in one path** is linear by design (a copy of the frozen part
  each frame): 7 → 166 µs from early to 58k samples; pen-up after 20,000
  moves 68–72 ms. Remote ink at 2,400 points (2.1 ms) is twice 600.
- **Connectors**: a moved box's repair has a 39 ms worst case, a full
  reload 35 ms; committing a drag ~50–58 ms.
- A first version of a 1,000-page PDF takes twice as long in total
  (4.4 s; its longest turn 59 ms, as before).

All 20 slow tests of the six files pass.

## Current numbers (debug, harness)

- **Library, 1,000 notebooks:** first frame 400–450 ms (a warm 20-notebook
  library: 220 ms; the difference is the fuller screen); scroll median 16–24 ms,
  98 card builds in 40 frames; search: a key 60–140 ms warm (titles filter in
  memory, content search debounced: 25–40 ms per query over 10,000 pages); a
  sort that keeps the captions 60–80 ms, one that changes them 110–150 ms, by
  name ~250 ms, layout switch ~200 ms; reload 70–80 ms; opening a folder
  100–250 ms. Profiles show framework build
  and layout of visible widgets; the data side (reload) is ~1 %.
- **500-page notebook:** first frame 155 ms (1-page: 66 ms); go to page 500
  102 ms; scroll median 18 ms. Overview: first frame 444 ms, 20 thumbnails
  built, +8 MB after scrolling all 500; one drag at 25,000 px/s: frames median
  67–72 ms on a loaded machine (seven new tiles a frame built and laid out;
  thumbnails wait until it slows), a fling median 4–7 ms.
- **Startup:** database open 16 ms, services 1 ms, library 24 ms; blob GC
  (next day) 37 ms.

## Known costs / next steps

- Anything rebuilt under the editor's `LayoutBuilder` repaints the editor
  layer (see "Paged scroll" above). Per scroll or pan frame nothing does
  now; dragging a PDF selection's handle still rebuilds the selection's
  layer per move (the selection itself changes).
- Web (JavaScript): every ink tile is still a GPU read-back on the main
  thread (CanvasKit has no other way to make an image of a picture; see
  "Web read-backs"); small rasters share atlases, writing and loading
  spare renders. Shader compiles are the other large cost under software
  GL. The restore's final transaction marks every imported row for sync at
  once.

- A first pull (natively) is bound by SQLite inserts in the pull worker
  (~60 µs a stroke with its chunk rows); 2M strokes take about two
  minutes, during which the app is free. The few 25–35 ms UI turns left
  during a pull are there without the worker too (garbage collection of
  the shared heap, serving the pages in the harness).
- Overview: a fast drag still builds and lays out ~7 new tiles a frame
  (all of the remaining 55–70 ms in the harness, framework widget work).
- Opening a folder (100–250 ms) and switching layouts build the new screen in
  full; `BlobReferences.all` still reads every live page and element once a
  day (33 ms for 10,000 pages; see above).
