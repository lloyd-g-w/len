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
| `startup_scale_perf_test.dart` | launch with a 335 MB database (325k strokes, 500 blob rows = 5 GB of PDFs, 200 expired trashed notebooks): what runs before the first frame, then trash purge and blob GC |

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

- A first pull is bound by SQLite inserts on the UI isolate (~60 µs a stroke
  with its chunk rows, 4 ms slices). Applying in a worker with its own
  connection would free the UI thread entirely, at the price of a second
  writer.
- Overview thumbnails record during a fast drag; deferring them while the
  grid flings (as `Image` does) would halve those frames.
- Opening a folder (100–250 ms) and switching layouts build the new screen in
  full; `BlobReferences.all` still reads every live page and element once a
  day (33 ms for 10,000 pages; see above).
