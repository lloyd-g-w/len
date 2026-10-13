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
| `sync_scale_perf_test.dart` | first full pull of 73k records (67k strokes) from a mock server, then an incremental and an idle sync |
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

## Current numbers (debug, harness)

- **Library, 1,000 notebooks:** first frame 550 ms (a warm 20-notebook library:
  220 ms; the difference is the fuller screen); scroll median 24 ms, 92 card
  builds in 40 frames; search: a key 120–150 ms warm (titles filter in memory,
  content search debounced: 25–40 ms per query over 10,000 pages); sort / layout
  switch 150–270 ms; opening a folder 100–250 ms. Profiles show framework build
  and layout of visible widgets; the data side (reload) is ~1 %.
- **500-page notebook:** first frame 155 ms (1-page: 66 ms); go to page 500
  102 ms; scroll median 18 ms. Overview: first frame 444 ms, 20 thumbnails
  built, +8 MB after scrolling all 500; scroll frames ≈ 85 ms at 25,000 px/s
  (building ten new tiles a frame; thumbnails record within a 6 ms budget).
- **Startup:** database open 16 ms, services 1 ms, library 24 ms; blob GC
  (next day) 37 ms.

## Known costs / next steps

- Each first-pull page is decoded (`jsonDecode` + `SyncRecord.fromJson`) in one
  turn (part of the p99 ≈ 40 ms); a 2M-stroke first sync takes ~4–5 minutes.
- Library sort / folder switches rebuild every visible card; overview tiles
  are moderately heavy widgets (drag target, menu button, tooltip).
- `BlobReferences.all` still reads every live page and element once a day
  (33 ms for 10,000 pages).
