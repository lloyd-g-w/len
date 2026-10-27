# PDF viewing — performance audit (Oct 2026)

Branch `perf/pdf-audit`. Audit only: no app code changed. Harnesses added:

| File | What it measures |
|---|---|
| `app/test/perf/support/pdf_fixtures.dart` | Generates (once, cached in `$TMP/len_pdf_perf_fixtures_v1/`) a 300-page textbook (embedded TrueType body text, ~4,000 chars a page, a figure every 5th page; 0.9 MB), a 50-page 300-dpi colour scan (2480 × 3508 JPEG a page; 52 MB) and 4 A3 vector map pages (12k polylines, 3k polygons, 600 labels each; 6.9 MB) |
| `app/test/perf/support/pdf_bench.dart` | `CountingRenderer` (the app's `PdfRenderer`, every render recorded: key, queue wait, service time, image life, duplicates, orphans), `paintFrame` (paints pages through `PdfBackgroundCache.paint` like `DocumentPaperPainter`), RSS / event-loop probes |
| `app/test/perf/pdf_render_perf_test.dart` | PDFium as Len drives it: open, whole-page renders at each bucket width, deep-zoom tiles vs one area render, tile sizes, text/links |
| `app/test/perf/pdf_view_perf_test.dart` | The app's `PdfBackgroundCache` (unchanged) over real PDFium in real time at 60 Hz: import, open → page 1 sharp, scrolling 50–100 pages at 1/3/10 pages/s (plus simulated what-ifs), pinch zoom 1→2×/4×, zoom steps, page overview and sidebar thumbnails |

Run: `nix develop -c bash -c 'cd app && flutter test test/perf/pdf_view_perf_test.dart'`
(and `pdf_render_perf_test.dart`). PDFium is the `libpdfium.so` a Linux build
downloads (see `test/pdf_test.dart`'s `pdfium`); the tests skip without it.

**Caveats.** Debug JIT in `flutter_test`; PDFium itself is native code, so the
render times are real x86-64 desktop numbers (expect an ARM tablet ~2–3×
slower). The tester engine rasterises nothing on a GPU, so texture upload and
GPU raster are not measured. The machine (16 cores) was shared with a test-suite
run (load average 7–20): timings vary ±50 % between runs; ranges below are
across runs. Counts (renders, duplicates, bytes) are deterministic.

## 1. The pipeline

**Import** (`features/documents/pdf/pdf_import.dart`): `BlobStore.putFile`
hashes and copies the file into the blob store (52 MB scan: 0.5–1.2 s); a
throwaway `PdfRenderer` opens it and reads every page size (`pageSizes`;
textbook 99–177 ms, vector 133–238 ms) to create one page row per PDF page
(`PageBackground.pdf(blob, pageIndex)`, size in world units = pt × 96/72).
Page sizes live in the database from then on. `search.indexPdfs()` starts the
text indexer (`data/search/pdf_text_indexer.dart`): it reads the **whole blob
into the Dart heap**, opens a second `PdfDocument` (`openData`) and extracts
each page's text (textbook: all 300 pages ≈ 1 s of worker time).

**Open** (`PdfRenderer.open`, one renderer per `SharedNotebook` via its
`PdfBackgroundCache`): lazily on the first render; native platforms
`PdfDocument.openFile(blobs.localPath)`, the web `blobs.read` + `openData`.
pdfrx's open loads **every page** (`FPDF_LoadPage` + size + `FPDF_ClosePage`
for all pages, pdfrx_engine `_loadPagesInLimitedTime`) before it returns.
Documents stay open until the cache is disposed (no re-open per page).

**Raster thread.** pdfrx_engine 0.6.1 / pdfrx 2.6.5. Android, Linux, Windows:
PDFium through FFI (`pdfium_dart`) on pdfrx's single `BackgroundWorker`
isolate (two priority queues; renders are `high`, text/links `normal`). Web:
PDFium WASM in a Web Worker (`pdfium_worker.js`), the pixels transferred as an
ArrayBuffer. In both cases the UI isolate only does `PdfImage.createImage`
(`ImmutableBuffer.fromUint8List` copy, 0.03–1.3 ms for 0.3–24 MB, then a raw
`ImageDescriptor` codec). **No decode or rasterising on the UI isolate.**
PDFium is not thread-safe and is one global instance per process, so a render
*isolate pool* is not possible with it. Every render call does
`FPDF_LoadPage` → `FPDF_RenderPageBitmap` (+ `FPDF_FFLDraw`) → `FPDF_ClosePage`:
nothing survives between calls, so a page's content is re-parsed and its
images re-decoded on **every** render, tile by tile.

**Len's queue.** `PdfRenderer._serial` runs one render at a time (the next
waits for the previous one's `createImage` too). `PdfBackgroundCache`
(`pdf_background_cache.dart`, `pdf_background_queue.dart`, `pdf_tiles.dart`):

- Keys: whole page `(background, width)`; tile `(background, level, col, row)`.
- Whole-page width buckets: 256 × √2ⁿ (256, 362, 512, 724, 1024, 1448, 2048),
  capped at `PdfTiling.wholePageWidth` (2048, or less for tall pages so the
  height ≤ 4096).
- Above the cap: 512-px tiles at power-of-two levels (4096 … 65536) for the
  visible rect only, nearest the centre first; the whole-page image stays
  underneath, coarser and finer cached levels are drawn too.
- Queue: `LinkedHashMap` key → request time; the newest whole page first,
  else the newest tile; requests older than 2 s are dropped. `stillWanted` is
  not passed (the 2 s rule does that job: measured 0–3 wasted renders per 100
  pages).
- Cache: LRU of `ui.Image`, 160 MB budget (pixels × 4), evicted on insert.
  Fallback while missing: the largest cached whole-page image of that page.
- Requests come only from painting: **no prefetch**.

**Display under ink.** `DocumentPaperPainter` (`editor/document/document_painters.dart`)
paints visible pages: sheet, then `backgrounds.paint(... scale × dpr)`
(`drawImageRect`, `FilterQuality.medium`), then the paper pattern; ink is in
other layers. The painter repaints on viewport changes and whenever the cache
notifies (every finished render).

**Thumbnails.** Sidebar, go-to strip and page overview (`PageThumbnail`) ask
the **same cache** for `imageFor(background, width × dpr)` (256 or 362
buckets) — the same queue, budget and PDFium worker as the page view. The ink
part is a separate `ThumbnailCache`. Nothing is kept on disk: every editor
session re-renders every thumbnail.

**Text/links/outline** (`editor/pdf/pdf_page_info*.dart`) use the renderer's
open document on the same worker (`loadText` 1–5 ms, `loadLinks` 1–3 ms a
textbook page).

## 2. Measurements

### PDFium cost per render (worker isolate, best of 3)

| Page | 256 px | 1024 px | 1448 px | 2048 px |
|---|---|---|---|---|
| Textbook text | 1 ms | 4 ms | 6 ms | 10 ms |
| Text + figure | 1 ms | 3 ms | 5 ms | 8 ms |
| 300-dpi scan | 38 ms | 54 ms | 67 ms | 88 ms |
| Vector map (A3) | 79 ms | 138 ms | 175 ms | 232 ms |

A scan's cost is mostly the JPEG decode (38 ms even for a 256-px thumbnail);
a vector page's is content parsing + fill (79 ms at 256 px).

### Open → page 1 sharp (app cache, painting as the editor does)

| Document | Tablet 1600 px (renders 2048) | Desktop 1000 px (1024) | of which PDFium open + measure all pages |
|---|---|---|---|
| Textbook, 300 pages | 112–175 ms | 84–136 ms | 64–114 ms |
| Scan, 50 pages | 137–206 ms | 85–124 ms | 7–25 ms |
| Vector, 4 pages | 373–686 ms | 272–493 ms | 120–226 ms |

`openFile(useProgressiveLoading: true)` takes 1 ms (textbook) / 0 ms (scan) /
30 ms (vector) instead of 64 / 6 / 121 ms. Right after an import, the text
indexer does **not** delay page 1 (148 vs 145 ms: renders are high priority).

### Scrolling (tablet, page fit to width, 60 Hz, real time)

| Run | Renders / pages | Duplicates | Page-frames blank | Entered → sharp p50 | Live images peak | RSS peak (run alone) |
|---|---|---|---|---|---|---|
| Textbook 1 p/s | 188–204 / 102 | 86–102 | 2 % | 36 ms | 2.1–2.5 GB | — (+9.7 GB in a full-file run) |
| Textbook 3 p/s | 199–203 / 101 | 98–101 | 5–7 % | 36–51 ms | 2.4 GB | +3.1–3.9 GB |
| Textbook 10 p/s | 117–201 / 101 | 15–100 | 10–23 % | 17–46 ms | 0.5–2.4 GB | +0.6–1.7 GB |
| Scan 1 p/s | 100 / 50 | 50 | 9–10 % | 153–192 ms | 1.3 GB | +4.0 GB |
| Scan 3 p/s | 91–100 / 50 | 41–50 | 18–41 % | 118–285 ms | 1.1–1.3 GB | +1.2–2.3 GB |

The cache's budget is 160 MB. "Live images" are `ui.Image`s not yet disposed:
at the end of each run 41–102 of them (0.9–2.3 GB) are **orphans** the cache
no longer holds (see F1). "Soft" (a lower-resolution fallback shown) was 0 %
in every run: nothing ever renders a low-res version of the page view.

UI isolate: `paint` p50 0.0–0.1 ms, max 1–15 ms; event-loop turns over 16 ms:
0–23 per run, longest 18–72 ms (one 307 ms turn in a run with 2.3 GB of
orphans; GC). PDF work does not block the UI isolate.

Simulated what-ifs (from outside the cache, `pdf_view_perf_test.dart`):

| Run | Renders | Blank | Entered → sharp p50 | Live peak | RSS peak |
|---|---|---|---|---|---|
| Textbook 3 p/s, as is | 199–203 | 5–7 % | 36–51 ms | 2.4 GB | +3.1–3.9 GB |
| … + dedupe | 101–102 | 6 % | 34 ms | 158 MB | +0.5–1.6 GB |
| Textbook 10 p/s, as is | 201 | 23 % | 46 ms | 2.4 GB | +1.7 GB |
| … + dedupe + prefetch 1 page | 102 | 3 % | 0 ms | 158 MB | +0 MB |
| Scan 3 p/s, as is | 91–99 | 22–41 % | 140–285 ms | 1.1–1.3 GB | +1.2–2.3 GB |
| … + dedupe | 50 | 19–26 % | 122–172 ms | 158 MB | +0.2–1.4 GB |
| … + dedupe + prefetch 1 | 50 | 3 % | 0 ms | 158 MB | +0.3 GB |
| … + dedupe + low-res (256) first | 100 | 24 % | 153 ms | 138 MB | +0.3 GB |
| Scan 1 p/s + dedupe + prefetch 1 | 50 | 2 % | 0 ms | 158 MB | +0.1 GB |

### Zoom (tablet; pinch 1× → target over 600 ms, then hold)

| Page | Target | Tiles rendered | Duplicates | Sharp again after the pinch |
|---|---|---|---|---|
| Textbook | 2× | 94–103 | 18 | 14–17 ms |
| Textbook | 4× | 163–171 (71–74 for levels passed through) | 20 | 1–50 ms |
| Scan | 2× | 68–69 | 36 | **2.2–3.3 s** |
| Scan | 4× | 61–75 | 33 | **2.0–2.4 s** |
| Vector | 2× | 81–82 | 43 | **2.8–5.2 s** |
| Vector | 4× | 58–71 | 30 | **2.0–3.4 s** |

The whole page is capped at 2048 px, so on a 1600-px tablet any zoom above
1.28× switches to tiles. One 512-px tile costs about what the whole page at
256 px does (scan 24–53 ms, vector 31–80 ms, text 1–3 ms): each tile re-loads
the page and re-decodes the scan. A tablet screen of tiles vs one area render
of the same pixels:

| Page | 24 × 512-px tiles | 6–8 × 1024-px tiles | One area render |
|---|---|---|---|
| Text, 2× / 4× | 47 / 36 ms | 42 ms (4×) | 14 / 8 ms |
| Scan, 2× / 4× | 620 / 607 ms | 393 ms (4×, loaded machine; 512: 1406) | 53 / 41 ms |
| Vector, 2× / 4× | 922 / 834 ms | 697 ms (4×, loaded; 512: 1575) | 169 / 104 ms |

Desktop ctrl+wheel 1.0→1.5 in 10 % steps: page re-rendered at 1024, 1024,
1448, 2048, 2048 (bucket changes, plus duplicates). Full-page re-render only
on bucket changes (√2 steps), not per small step.

### Thumbnails

| | 24 thumbnails (362 px) | Renders for the whole grid | One thumbnail |
|---|---|---|---|
| Textbook, 300 pages | 135–257 ms (28–32 renders) | 327–366 for 300 | 1.4–2.8 ms |
| Scan, 50 pages | **1.9–4.1 s** (46 renders) | 75–78 for 50 | 40–84 ms |

Sidebar beside the page view (scan): the page's 2048 render goes first
(page 21 sharp in 306–424 ms), then thumbnails one by one; a 300-page scanned
book's sidebar/overview is ~12–25 s of worker time, every session.

### General hot paths (brief)

`big_notebook_perf_test.dart` (500 pages, half PDF, fake renderer): first
frame 162 ms, go to page 500 92 ms, scroll median 15 ms / max 33 ms; a long
session keeps 25 page models, +179 MB — in line with docs/PERFORMANCE.md
("Current numbers"). Nothing glaring found in the editor frame or library
open outside the PDF cache; the `DocumentPaperPainter` and thumbnail painters
repaint on every finished render (cheap: paint p50 ≤ 0.2 ms).

## 3. Findings (ranked by gain / effort)

### F1. Every page and tile in flight is rendered twice, and the first image leaks — gain **very high**, effort **S**, risk low

- **What.** `_request` re-queues a key that is being rendered (it is in
  neither `_images` nor `_queue` while in flight); any repaint during the
  render (every scroll/zoom frame, or another render finishing → notify →
  repaint) re-requests it, and the worker renders it again right after.
  `_render` then does `_images[key] = image`, overwriting the first image
  **without disposing it**: it stays alive (outside the budget accounting)
  until the GC finalises it.
- **Evidence.** Scroll: 2 renders per page (203 for 101; 100 for 50); overview
  366 for 300; zoom tiles ~50 % duplicates (36/69, 43/81). Orphans: 0.9–2.3 GB
  of live images at the end of a scroll with a 160 MB budget; RSS peak
  +3.1–4.0 GB. Simulated fix: renders halved, live images peak 158 MB, RSS
  +0.5 GB (textbook 3 p/s), entered → sharp p50 51 → 34 ms, scan zoom sharp
  ~45 % sooner.
- **Gain.** Halves PDFium work in every scenario that moves; removes the
  multi-GB memory spikes (on Android/Impeller these are GPU textures: OOM and
  GC-pause risk; one 307 ms UI turn seen with orphans present).
- **Fix.** `pdf_background_queue.dart`: keep an `_inFlight` set; `_request`
  returns early when the key is in `_images` or `_inFlight`; `_work` adds/removes
  it around `_render`. `pdf_background_cache.dart` `_render`: if a previous
  image exists for the key, dispose it (`_images.remove(key)?.dispose()`)
  before inserting. Test: a cache over a counting fake renderer, repaint every
  frame while a render is slow → exactly one render per key, no undisposed
  images (`ui.Image.debugDisposed`).

### F2. No prefetch: pages enter the screen blank — gain **high**, effort **S–M**, risk low

- **What.** Only painted pages are requested, so a page entering the view is
  white paper until its render lands; no low-res stand-in exists.
- **Evidence.** Blank page-frames: scan 9–10 % at 1 p/s, 18–41 % at 3 p/s;
  textbook 10–23 % at 10 p/s; entered → sharp p50 140–285 ms (scan). With
  dedupe + one page of prefetch: 2–3 % blank, entered → sharp p50 0 ms.
- **Fix.** In `DocumentPaperPainter.paint` (or a `PdfBackgroundCache.prefetch(
  background, page, ppu)` it calls) request the page after the last visible
  one and the one before the first, at the visible bucket, after the visible
  pages' requests so they are served first (the queue serves the newest
  whole page first: add a priority flag so a prefetch never jumps a visible
  page). Two prefetched 2048 pages fit the 160 MB budget (2 visible + 2 × 23.7 MB).
  Optionally extend in the scroll direction at high velocity.

### F3. Deep-zoom tiles re-load and re-decode the page per 512-px tile — gain **high** for scans/maps, effort **S** (tile size) to **M** (area render), risk low–medium

- **What.** `PdfTiling.tileSize = 512` and one PDFium call per tile; each
  call re-parses the page and re-decodes its images.
- **Evidence.** A screen at 2×: 24 tiles 600–920 ms (scan/vector) vs one area
  render 41–169 ms; in the app, scans/maps are sharp again 2.0–5.2 s after a
  pinch. Above 1.28× on a 1600-px tablet everything is tiles.
- **Fix, quick.** `tileSize` 512 → 1024 (`pdf_tiles.dart`; tiles become 4 MB):
  2.3–3.6× less time per screen on scans/maps in the bench, same sharpness.
  Check `pdf_tiles_test.dart`'s expectations of tile counts.
- **Fix, better (progressive zoom).** When the zoom settles (no scale change
  for ~100 ms), render the visible rect (+ a margin) at the target level as
  one `renderArea` and draw it as an extra layer above the base page while the
  tiles fill in (scan 2×: ~50 ms instead of 0.6–1.6 s to sharp). Files:
  `pdf_background_cache.dart` (a `viewport` key `(background, level, rect)`,
  one entry, replaced on pan), `pdf_background_queue.dart`.
- **Fix, best (bigger).** Render several tiles in one worker call with the
  page loaded once (PDFium keeps a loaded page's decoded images): needs a
  pdfrx patch (a `renderRects` API) or Len's own call through `pdfium_dart`
  on pdfrx's worker (`PdfrxEntryFunctions.instance.compute`). Expected to make
  scan tiles ~1–3 ms after the first; unmeasured.

### F4. Opening measures every page with `FPDF_LoadPage` — gain **medium** (large for long or vector PDFs), effort **S–M**, risk medium

- **What.** `PdfDocument.openFile` (default) loads every page to read its size;
  Len already has the sizes in its page rows.
- **Evidence.** 64–114 ms of the textbook's 112–175 ms to page 1 (linear in
  page count: a 1,000-page book ~0.3 s); 120–226 ms of the vector file's
  373–686 ms. Progressive open: 1 ms / 30 ms.
- **Fix.** `PdfRenderer.open`: `useProgressiveLoading: true`; in `render` /
  `renderArea` / `links` call `await page.ensureLoaded()` (or compute the
  height from the page size the cache passes in) so unloaded pages' placeholder
  sizes are never used. `pageSizes` (import) keeps a full load
  (`loadPagesProgressively`). Risk: any code reading `doc.pages[i].width` on an
  unloaded page — audit `pdf_page_info.dart`, `pdf_text_source.dart`,
  `export/pdf_page_sources.dart`.

### F5. The tablet's page view renders 1.64× the pixels it shows — gain **medium**, effort **S**, risk low

- **What.** √2 buckets: a 1600-px page rounds up to 2048 (2048 × 2896 = 23.7 MB).
- **Evidence.** 1448 vs 2048 px: text 6 vs 10 ms, scan 67 vs 88 ms, vector
  175 vs 232 ms; the 160 MB budget holds 6.7 pages at 2048.
- **Fix.** `PdfBackgroundCache.bucketFor`: quarter-octave buckets (2^¼ steps:
  …1448, 1722, 2048) or snap to the device's fit-to-width size, so fit-width
  renders at ≤ 1.19× the shown pixels (1722 px → 16.8 MB, ~30 % less memory and
  20–30 % less render time a page). Slightly more re-renders while zooming.

### F6. Thumbnails of scans cost a full-resolution decode, every session — gain **high** for scanned PDFs, effort **M**, risk low

- **Evidence.** 40–84 ms a scan thumbnail; 24 in 1.9–4.1 s; nothing persists.
- **Fix.** A disk cache of small renders (`(sha, page, width)` → PNG/raw
  RGBA in the app cache dir; LRU by total size, e.g. 64 MB), consulted by
  `PdfBackgroundCache` for widths ≤ 362 before queueing; filled when rendered
  and in idle time after import (the indexer's pass could render 256-px
  thumbnails while it reads text). Web: IndexedDB/Cache Storage or skip.
  These thumbnails also become the low-res stand-in for F2/F7 on reopen.

### F7. Low-res-then-sharp for slow pages — gain **medium for vector pages only**, effort **S**, risk low

- **Evidence.** Vector first pixels would come at 79 ms (256 px) instead of
  232 ms; for scans it does not help (256 px = 38 ms of decode, then 88 ms
  again: simulated scroll 24 % blank vs 19–26 %), text is already 10 ms.
- **Fix.** In `_imageFor`, when no image of the page is cached and the
  document's last render at this width took > ~60 ms, also queue the 256-px
  bucket ahead of it. Prefer F2 + F6 first.

### F8. Smaller items — effort S each, gain small

- Queue order: the newest whole page = the last painted (bottom) page, not
  the most central one (vector open: p0, p2, p1). Order by distance to the
  viewport centre, as tiles already are (`pdf_background_queue.dart` `_next`).
- `PdfRenderer._serial` waits for `createImage` before starting the next
  PDFium call; release the queue after `page.render` and convert outside it
  (the worker idles 0.03–1.3 ms per render in the harness; more with a GPU
  upload on device).
- The search indexer reads the whole PDF into the Dart heap (`readBlob`, 52 MB
  for the scan) and opens a second document; on native use
  `PdfDocument.openFile(blobs.localPath(sha))` (`pdf_text_indexer.dart`,
  `pdf_text_source.dart`).
- Every finished render repaints every listening painter (page view, all
  sidebar thumbnails); cheap today (paint ≤ 0.2 ms), worth a per-page
  notification if the sidebar grows.

### Checked, not a problem

- No PDF work on the UI isolate apart from the pixel copy into
  `ImmutableBuffer` (0.03–1.3 ms); paint p50 ≤ 0.1 ms.
- Documents are opened once per cache and kept; no re-parse/re-open per page.
- Pages scrolled past are rarely rendered (0–3 per 100 pages; the 2 s rule).
- Small zoom steps re-render only on √2 bucket changes.
- The indexer after import does not delay page 1 (render priority).
- A render isolate pool is not possible with PDFium (one non-thread-safe
  global instance; pdfrx runs one worker) — speed comes from fewer and
  cheaper calls (F1, F3, F4, F5) and from not repeating them (F6).

## 4. Fix lists

**Quick wins** (each S, in order):

1. F1 — in-flight dedupe + dispose a replaced image (halves renders, fixes the
   GB-scale memory spikes).
2. F2 — prefetch one page each side (blank page-frames 22–41 % → 3 % on scans).
3. F3 quick — `PdfTiling.tileSize` 1024 (zoom on scans/maps 2–3.5× faster).
4. F4 — progressive open + `ensureLoaded` (textbook page 1: −64–114 ms;
   vector −120–226 ms).
5. F5 — finer buckets (fit-width renders ~30 % cheaper and smaller).
6. F8 — centre-first queue order; un-serialise `createImage`.

**Bigger changes:**

1. F3 — progressive zoom: one viewport-area render at the target level on
   settle, tiles behind it (scan/vector zoom sharp in ~50–170 ms instead of
   2–5 s).
2. F6 — disk cache of thumbnails / small renders, filled after import
   (scanned overview instant on reopen; low-res stand-ins for free).
3. F3 best — batched tile renders on one loaded page (pdfrx patch or direct
   `pdfium_dart` calls on pdfrx's worker).
4. F7 — adaptive low-res-then-sharp for slow (vector) pages.
5. A device-aware budget (e.g. from Android's memory class) once F1 makes the
   160 MB budget real; downscale off-screen cached pages instead of keeping
   them at 2048.
