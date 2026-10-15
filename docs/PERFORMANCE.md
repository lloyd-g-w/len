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
| `big_notebook_perf_test.dart` | 500-page notebook (45k strokes, half PDF pages): open, go to page 500, scroll; page overview; a long session writing on 300 pages (memory, undo) |
| `sync_scale_perf_test.dart` | first full pull of 73k records (67k strokes) from a mock server (records encoded ahead, so serving costs the shared thread only a copy), then an incremental and an idle sync |
| `scribble_perf_test.dart` | scribble to erase on very long strokes (writing, and a scribble going on): µs per pen move at 4k and 64k moves must stay flat |
| `restore_scale_perf_test.dart` | restore a 21 MB library backup (200 notebooks, 45k strokes, 12 records parts): total time and the longest UI turn |
| `startup_scale_perf_test.dart` | launch with a 335 MB database (325k strokes, 500 blob rows = 5 GB of PDFs, 200 expired trashed notebooks): what runs before the first frame, then trash purge and blob GC |
| `minimap_perf_test.dart` | canvas of 10,000 strokes over 40,000 × 25,000 (3,762 chunks): a pan frame and a pen move with the minimap on and off (widgets rebuilt, render objects painted), and the map's own work (density read, merge, paint) |
| `zoom_window_perf_test.dart` | three full ruled pages: a frame of the page view scrolling with the zoom window open and closed; 60 words written in the box against 60 on the page |
| `ink_render_perf_test.dart` | (with the Ink Lab cases) 2,000 overlapping shapes outlined and filled: first screen of tiles, pan frames |
| `scan_perf_test.dart` | a synthetic 12-MP photo: detection, preview, page render and JPEG; the longest UI stretch of the web's banded path |

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
  57 ms (seven new tiles a frame, about half of it recording their thumbnails;
  27 ms without).
- **Startup:** database open 16 ms, services 1 ms, library 24 ms; blob GC
  (next day) 37 ms.

## Known costs / next steps

- Anything rebuilt under the editor's `LayoutBuilder` repaints the editor
  layer (see "Paged scroll" above). Per scroll or pan frame nothing does
  now; dragging a PDF selection's handle still rebuilds the selection's
  layer per move (the selection itself changes).
- A corner drag on the scan screen redraws the photo (the display copy,
  ≤ 1,600 px) with the outline on every move; a layer of its own for the
  photo would leave only the outline and loupe.

- Web (JavaScript): ink tiles, thumbnails and LOD rasters become images
  through a GPU read-back on the main thread (CanvasKit), and alternating
  image sizes resize its shared surface each time; batching renders by size
  or keeping tiles as pictures would trade memory or frame time for it.
  The restore's final transaction marks every imported row for sync at once.

- A first pull is bound by SQLite inserts on the UI isolate (~60 µs a stroke
  with its chunk rows, 4 ms slices). Applying in a worker with its own
  connection would free the UI thread entirely, at the price of a second
  writer.
- Overview thumbnails record during a fast drag; deferring them while the
  grid flings (as `Image` does) would halve those frames.
- Opening a folder (100–250 ms) and switching layouts build the new screen in
  full; `BlobReferences.all` still reads every live page and element once a
  day (33 ms for 10,000 pages; see above).
