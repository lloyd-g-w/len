# Len — owner TODO (working list)

The owner's current asks, kept here so every round can check them off.
Status: ⬜ open · 🚧 an agent is on it (branch) · ✅ merged into main.

## Shapes
- ✅ **The Shape tool is very broken**: redo the drag-to-draw for every kind (line, arrow,
  rectangle, ellipse, triangle, diamond, star): predictable, live preview, Shift constraints,
  no jumps.
- ✅ **Pen → shape (hold to snap) is equally broken**: reliable recognition, a clean snap,
  no false snaps, the snapped shape where the hand drew it.
- ✅ **Editable control points on selection** for both drawn and snapped shapes (corners,
  endpoints, ellipse bounds, star/polygon vertices; one undo step per drag; synced).

## Lasso / selection
- ✅ **Selection options**: what to select (ink, highlighter, text, images, shapes),
  **partial vs whole** (touching vs fully enclosed), and **selection shapes** (freehand lasso,
  rectangle). Lasso popover: Shape (Freehand / Rectangle), Select (Touching / Mostly / Whole;
  Mostly, the old rule, stays the default), Items (Ink, Highlighter, Text, Images; shapes are
  ink, links go with images).

## Highlighter
- ✅ **Same engine as the pen**, with the same customisability where it makes sense
  (round vs flat ends, pressure, …). Explain or unify. It always was the pen's engine
  (sampling, smoothing, stabiliser, outline), but forced flat ends and hid pressure; its
  popover now offers pressure sensitivity and flat (default) or round ends too.
- ✅ **Highlighter flickers on pen-up**: fix. A highlight crossing more than two tiles
  vanished for a frame or two at pen-up (its tiles kept their old images until re-rendered);
  they now draw it beneath their images meanwhile, as the live stroke was drawn. The pen was
  fine (checked by the same frame-by-frame test).

## Eraser
- ✅ **Scribble to erase takes too many scribbles**: trigger after fewer zig-zags (1–2
  back-and-forths), without false positives in normal writing. Two quick back-and-forths
  (4 passes in 0.8 s) now erase; the passes must keep to a narrower band, and printed
  zigzag letters (z, N, M, w, vvv), joined-up m/w/z and zigzag hatching (spaced a tenth of
  its length or more) joined the no-false-positive corpus.

## Notebooks
- ✅ **Default notebook style**: set the default template, paper, size and cover for new
  notebooks.
- ✅ **Own presets / styles**: save and reuse notebook styles (template + paper + size +
  cover). Pen presets left out on purpose: favourite pens were removed (SIMPLIFY #10) as a
  duplicate of the quick colour and width slots.

## Laser pointer
- ✅ **Keep-while-writing option**: the trail stays until about 2 s after pen-up; writing
  again within that time keeps everything showing (nothing fades between strokes). Laser
  popover: Fade (Each stroke / When I stop), "Fades after" 0.5–5 s (default 2 s).

## Infinite canvas
- ✅ **Minimap, polished** (feat/minimap): shows roughly where content is, the current view,
  tap / drag to move, pinch / scroll to zoom; ⋯ → View → Minimap (Shift+M); steps aside while
  writing and in focus mode.

## Input
- ✅ **Mouse strokes zoomed out are squiggly (web and Linux)**: mouse ink at low zoom must be
  as smooth as at 100 %. Mouse positions are whole pixels; the outline's smoothing is bounded
  by the pen's width, so zoomed out it could not level the steps. Mouse paths of a pen under
  2.5 px on screen are now smoothed on the screen first (`MouseSmoother`, as much as the
  outline lacks): as smooth at 10 % as at 100 %; at 100 % mouse ink is unchanged, no lag.

## Done earlier this round
- ✅ Shape fill, zoom window (and round 2), document scan (and round 2), keyboard
  accessibility, camera photos recovered after a kill, round 10–12 audits, design polish
  round 11, performance rounds (pan, paged scroll, web long tasks), bug hunts 1–5.

## Owner reports (after the first list)
- ✅ **Smoother ink, mouse first** (owner): default stabiliser 30 %; mouse
  ink is only acceptable at 30 % and still a little bumpy — steady width, light smoothing at
  every width, less bumpiness at 0 % too. The pen's default stabiliser is
  30 % (saved settings still at the old default, off, upgraded). Every mouse stroke is smoothed
  on the screen with the stroke's stabiliser (`MouseSmoother`, cusps kept), not again by the
  outline; at 0 % a provisional tip keeps the ink at the mouse. Measured on synthetic mouse
  handwriting (1000 / 125 Hz, coalesced, slow and fast, widths 0.4–10 px on screen), worst
  case before → after: at 0 % kinks 60° → 9°, edge bumps 0.35 → 0.04 px, width spread on
  straight lines 32 % → 3 %, lag 6 → 0 px; at 30 % kinks 12° → 9° (mean 2.8° → 1.3°), width
  spread 8 % → 1 %, lag 13–33 → 11 px. Stylus ink unchanged (specimen goldens identical).
- 🚧 (merged; to verify on the tablet, flicker log in Ink Lab) **The pen still flickers sometimes** on the Android tablet (S Pen),
  no clear pattern: find every handover / prediction / tile cause, test, fix, and add an
  on-device flicker log to catch the rest.
- ✅ **Dotted paper's dots change size on zoom** (they kept a constant
  on-screen size): dots get a fixed world size and scale with the page everywhere.
- ✅ **Ruled and grid lines** had the same flaw (one screen pixel at
  every zoom): a fixed page width matching PDF export, at least about a pixel.

## Owner asks (round 13)
- ✅ **Highlighter and laser customisation like the pen's**: the highlighter already had every
  pen option (now tested); the laser gets editable, persisted quick colour and size slots (1–5
  each, shared slot rows and editors, 1–5 and [ / ] too) and the pen's popover layout.
- ✅ **The laser's ends can't be changed** (owner, again): the laser has the
  pen's slots but not its feel: ends (round / flat / tapered), pressure, stabiliser; the trail
  drawn with the pen's outline engine. Done: the laser popover has the pen's Pressure
  sensitivity, Stabiliser and Ends controls (round / tapered with start / end / both and
  length / flat; under Feel, as the pen's, hidden for the dot since round 25); persisted (old settings load as before: flat, off,
  off), Reset restores them. Each trail stroke is shaped by the pen's `StrokeShaper`
  (sampling, smoothing, stabiliser, pressure radii, tapers) incrementally, then drawn as the
  laser's glow and core with the fade (round ends add a soft half disc); the preview shows a
  finished stroke. Defaults look as before; frame cost about as before
  (`test/perf/laser_perf_test.dart`).
- ✅ **Better shape control points**: handles by meaning for drawn and snapped shapes (circle
  centre + radius, ellipse centre + two radii, rectangle / diamond corners + sides, a line's
  bend, star centre + point + inner radius and its points in Style) with snaps and Shift
  constraints, one undo step per drag, synced in the shape geometry (circle kind, bends, `n`).
- ✅ **Arbitrary curves**: a Curve kind (cubic Bézier spline, open or closed, filled when
  closed) drawn anchor by anchor with the Shape tool or snapped from a held smooth stroke
  (Schneider fit); anchors and tangents are editable, a tap on the line adds an anchor and a
  double tap removes one.
- ✅ **Shape follow-ups** (from the shape-handles review): undo while a curve is being drawn
  takes back its last anchor (today it undoes earlier strokes); a circle can be squashed into
  an ellipse from a handle; with Curve picked a tap on a shape selects it rather than placing an
  anchor (or the hint says how). Done: undo/redo step through a curve's anchors while it is
  drawn; a tap on a shape selects it with Curve picked (a drag from it starts a curve); a circle
  has handles at its axes' ends that squash it into an ellipse. Handle UX review: a tiny shape's
  primary handles spread apart (others hidden) so each can be grabbed, handles drawn larger on
  touch-first devices, desktop cursors over handles / frame / body, a curve's anchors and
  tangents shown while it is drawn.
- 🚧 (rounds 3–4 merged; to verify on the tablet) **The pen still flickers sometimes** (owner, again): keep hunting every cause on every
  platform (Linux, web, Android), with frame-by-frame tests. Causes found and fixed: a pen-up
  over a text box's or image's chunk (no append) left tiles on their old images or, zoomed far
  out, on vectors (the stroke vanished for frames); a stroke written while a zoom's tiles
  rendered, or a zoom within the web's 1.2 s merge, released the old zoom's stand-ins; a sync
  reload dropped the surface and read it again (blank page for frames, mid-stroke too: it now
  keeps what is shown and swaps in what differs); dropping a selection over many tiles hid its
  ink for a frame or two; on Android a quick next stroke's armed contact was never confirmed by
  `begin` and dropped after 1 s; zooming across the level of detail showed nothing where
  the new images were not made yet (old rasters / stale tiles now stand in); after a pan, the
  pen-up shifted the stroke by a fraction of a device pixel (tiles now aligned to their pixels,
  views pan in whole device pixels). Round 4: at pen-up with the stabiliser on, the committed
  outline refitted the shown tail's last stretch (edge pixels changed shade; now it reuses the
  last frame's outline, cut and joined where it ended, the live line a sample short so its end's
  tangent is known); live ink filled as two overlapping paths had darker edge pixels at their
  seam that lightened at pen-up (now one path); a mouse with its stabiliser on showed a tip
  that settled at pen-up (now only the final line); the Android overlay was then a sample
  ahead of Flutter's stabilised line (a pop when it retracted; it follows now). Frame-by-frame tests cover the live stroke (stabiliser,
  ends, zooms, pixel ratios), the composited editor, erasing, undo / redo, selections, mid-stroke
  syncs and the web's merged atlases.
- ✅ **Live sync, actually live**: edits show on other devices within a fraction of a second
  (push on pen-up, server fans the records out over one long-lived connection, no pull
  round trip), built as the foundation for real-time collaboration: a WebSocket channel with
  rooms per notebook, ephemeral messages (in-progress strokes, presence / cursors) next to
  records; documented in SYNC_PROTOCOL.md; falls back to today's pull when the channel is down.
  `GET /v1/live` (pushes and fan-out on one WebSocket,
  rooms per notebook with presence and relayed ephemeral messages, tickets for browsers,
  bounded outboxes); edits pushed a frame after they are committed (~25 ms to another device
  over loopback); the stroke being written drawn live on the others (replaced by its record),
  presence plates in the editor bar; the event stream and the cycle as fallbacks. Cursors
  are not sent yet (the room data has room for them).
- ✅ **Hide the name tags of other devices' pointers** (owner): a toggle for
  the device initial plate drawn beside another device's pen / laser while it writes (⋯ → View
  and Settings), persisted; the pointer itself and presence in the bar stay. Done on the
  branch: `pointerTags` preference (`pointer_tags`, default on), ⋯ → View → *Name tags*
  (paged notebooks and canvases, while another device is in the notebook) and a *Name tags* switch in Settings → Sync
  while connected; `RemotePointersPainter.tags` skips the plates, repainting at once. Remote
  live ink draws no tag, so nothing to hide there.
- ✅ **Live sync follow-ups**: cursors / pointers of other devices (the laser
  too); no gap between another device's live stroke and its record when the page reloads fully
  (500+ changes, a selection in the way) or for a highlight snapped to text (it ends without a
  stroke id); an e2e run with two real app instances over the live channel. Done: other
  devices' hovering pen or mouse (a dot) and laser (dot and trail, replayed as they show it)
  drawn live on the right page or the canvas, labelled with their presence plate, sent at most
  25 times a second and only while someone else is in the room (`PointerRelay` hooks in only
  then), hidden after 3 s at rest or when they leave (`"k": "pointer"` messages); a live
  stroke's end names every stroke it became (`strokes`: a snapped highlight's lines too), and
  its ink stays on a surface reloading whole until the reload brings the stroke in;
  `integration_test/live_test.dart` runs two app instances at once (`LEN_E2E_PHASES=live
  tool/e2e.sh`): B sees A's pointer, live stroke and record with no pull.
- ✅ **`flutter run --release -d linux` fails to link** (owner): it builds and runs inside
  `nix develop`; a Flutter from outside the dev shell lacks its toolchain and libraries. The
  repo has an `.envrc` (direnv: `use flake`) and the README says so.

- ✅ **Version history** (owner): a notebook's (and canvas's) history to
  browse and restore: versions kept automatically (after a stretch of editing goes quiet, and at
  most every few minutes while editing; thinned over time: all of today, hourly for a week,
  daily for a month, …) and named ones saved by hand ("Save version…"); a timeline with
  thumbnails, who / which device and what changed (pages added / removed / edited); preview a
  version read-only, then restore the whole notebook, restore one page, or copy it as a new
  notebook; restoring is itself undoable (a new version, nothing lost). Cheap: unchanged
  content shared between versions (records and blobs by reference, not copies); synced, so
  every device sees the same history; storage budget and "Delete older versions"; works on the
  web and offline. Designed with live collaboration in mind (who changed what).
  **Done** (design: ARCHITECTURE "Version history", SYNC_PROTOCOL "Version history"): a
  version is a synced `versions` record (old clients skip the unknown collection) naming
  content-addressed *packs* (blobs of a surface's stroke / element record data, cut where ids
  hash to a boundary, so unchanged runs are shared between versions; re-packed only for
  surfaces whose change mark moved). Row references were not enough: elements, pages and the
  notebook are edited in place and tombstones sync without payload. Every blob a version needs
  is named in its record, so server and device blob GC keep it (no server change), and its push
  waits for the packs' upload. `VersionRecorder`: 2 min after editing goes quiet, at most every
  10 min, on editor close / app background; skipped when equal to the newest. `VersionPolicy`:
  all of the last day, newest per hour for a week, per day for a month, per week after
  (epoch-aligned nested buckets: every device thins the same, later clocks keep a subset),
  budget 200 automatic versions / 64 MB per notebook; named kept; thinning on record and with
  GC; versions of notebooks deleted forever go after 30 days. `VersionRestorer`: whole notebook
  (settings, pages by id in order, strokes / elements by id), one page (back after its
  predecessor), copy as new notebook (new ids, own links / flows / connectors follow); a
  `restore` version is saved first and the snack bar's Undo restores it; open editors reload
  (`SyncController.announce`). UI: editor ⋯ "Version history…" (Save version… in its header, R25-33), library
  notebook menu "Version history…"; history sheet (day groups, thumbnail of the first changed
  page, time, device, summary; ⋯ Restore…, Copy as new notebook, Rename…, Delete version,
  Delete older versions…), preview route (page grid, page view with Restore this page; canvas
  view). Tests: `version_history_test` (packs, snapshots / dedupe, thinning with fake clock,
  restore whole / page / copy / undo, offline refusal, GC), `version_history_sync_test` (two
  devices, lazy pack fetch, restore and delete across devices, malformed record skipped),
  `version_history_ui_test`.
  **Left:** recordings and the outline are not versioned; packs are not compressed and only
  dedupe across devices of one platform family (doubles print differently on the web);
  version records grow with page count (a 1000-page PDF notebook: ~100 KB a version) — a
  reference-blob scheme the server GC follows would shrink them; device names are platform
  names (per user once there are users); no golden / screenshot of the history yet.

- ✅ **Len import keeps text flow links**: import gave text boxes new ids but
  left `TextFlow.from` at the file's ids, so imported chains broke apart. Now `LenRemap` maps
  text boxes' ids and their flows, and the commit drops flows from boxes not imported; a
  duplicated page's continuation (it still named the original's box before) and a version
  copy's flow from a box not in it stand alone too (`TextFlowRelinks`, shared with the notebook
  duplicator). Checked with a 3-page chain (`text_flow_copies_test`): page / notebook
  duplicate, pages sent (all, the last two), Len import and restore, version copy; lasso
  copy / paste takes the whole text already, restoring a page keeps ids. Other references in
  element data were fine (link targets remapped when the file holds the page; images are
  blob hashes; recordings follow ink by time, not id).

- ✅ **Version history follow-ups**: compress packs (and the same bytes on web and native, so
  they dedupe across platforms); version recordings, the outline and recognised handwriting
  too; smaller version records for very long notebooks (pages' entries in shared blobs, with
  the blob clean-up following them); a golden of the history view.
  **Done** (design: ARCHITECTURE "Version history", SYNC_PROTOCOL "Version history" and
  "Reference blobs"): packs are format 2 — `LP`, 2, canonical JSON (`CanonicalJson`: sorted
  keys, integral numbers as integers, fixed escapes) deflated by the archive package's pure-Dart
  encoder on every platform; the same SHA-256 on the VM, dart2js and dart2wasm (checked under
  Node, pinned in a test); format 1 packs still read; the pack cache is emptied once
  (migration 17) so surfaces re-pack. A version record now names *table blobs* (`LR`, 1:
  *reference blobs*) holding its rows — canvas or pages (fields, packs, images, recognised
  text), recordings and outline entries — cut by row id like packs, so a 1000-page notebook's
  record is ~2.5 KB (was ~100 KB) and an edit of one page writes one or two new table blobs. Blob GC follows
  reference blobs: the server inflates and scans those reached from live records
  (`BlobGc.referencedAmong`); the device notes what a table blob names in `blob_links` when it
  writes or reads one (`BlobLinks`), which `BlobReferences` (GC, uploads) and the push's
  hold-back (`ofRecord`) join. Restore brings back recordings (trims, titles; newer ones
  tombstoned, audio by blob reference), the outline and recognised text; one page its text and
  its outline entries; a copy gets its own recordings and outline (pages remapped). Format 1
  records still read and restore (leaving recordings, outline and text alone). Version builds
  and table reads yield every 8 ms (`WorkSlices`); blobs ≤ 64 KB are hashed without an
  isolate. Tests: `version_history_records_test` (canonical bytes, pinned pack, table
  blobs, recordings / outline / text restore, page restore, copy, format 1, 1000 pages, uploads
  and GC through tables), server `blob_gc_test` (reference blobs, nested, broken),
  `version_history_golden_test` (history and preview, light / dark, tablet / phone).
  **Left:** audio freed after a trim stays while a version names it; a device that never read
  another device's table blob doesn't know what it names (it holds none of those packs
  unless shared, which then may be collected locally and fetched again); the golden test reads
  thumbnail readiness from a private painter field; the phone preview's title is cut by its
  two buttons; device names are still platform names.

- ✅ **Version history on phones**: below `Breakpoints.medium` the preview's
  app bar holds only the date (one line, as tall as the text size needs), the version's name
  and device head the pages in full, and Copy as new notebook / Restore (a page: Restore this
  page) sit in a docked bottom bar (`DialogActions`: a row, stacked at large text); wide
  screens keep the bar with a tooltip for the full title. The history's Save version… turns
  into an icon where its label would squeeze the title; names take two lines. The thumbnail's
  public `VersionSurfaceViewState.loaded` replaces the painter peek; goldens add a long name
  at text scale 1.3 and 2.0.
  Merged with round 25 (R25-7): the bar's date is the short "Today, 14:02", and the page
  view's Restore this page docks in the same bottom bar.

## Next (open follow-ups, not yet asked for)
From the reports; the owner picks. Status as above.

- 🚧 (fix/r25-followups) **Undo after a version restore** (UX_AUDIT R25-6): the editor's undo steps from before a
  restore survive it, so Ctrl+Z does nothing visible and Ctrl+Shift+Z writes an old stroke back
  onto the restored page. Decide: drop the undo steps of the surfaces a restore rewrote (its Undo
  is the snack bar's), or make the restore one `UndoHistory` step.
- ✅ **Remote pointers on other pages and in the zoom window** (UX_AUDIT R25-15–R25-18): done
  on the branch: a hover (or a mouse laser's dot) goes as the page under it, through the layout
  (`DocumentController.pagePointOf`), while a laser trail stays on the page it began on, in its
  coordinates even beyond its edge; the zoom window draws other devices' live ink and pointers
  (the same layers over its view); the hover dot takes its colours from the paper
  (`Palette.pointerOn`, ringed with the paper), not the theme; a device joining mid-stroke gets
  the stroke again from its start (SYNC_PROTOCOL updated).
- 🚧 (fix/r25-followups) **Text boxes read twice** (UX_AUDIT R25-23): a page's screen-reader value holds its text
  boxes, and the active page's boxes are nodes of their own too. Keep the overview, or leave the
  active surface's boxes out of the value?
- 🚧 (fix/r25-followups) **A curve in progress and a finger pan on another page** (UX_AUDIT R25-29, suspected): the
  pan's first touch activates that page, which finishes (or, with one anchor, drops) the curve.
  Check on the tablet; keep the page while a curve is drawn, without letting a stylus add
  off-page anchors.
- 🚧 (fix/r25-followups) **Teach curve editing and attaching ends** (UX_AUDIT R25-30): no hint says a tap on a
  selected curve's line adds an anchor and a double tap removes one, or that line and arrow
  ends attach to shapes.

- ✅ **Pages to screen readers** (UX_AUDIT R23-10): `PageSemantics`, one node per page in view
  ("Page 3 of 12, bookmarked") valued with its text boxes, recognised handwriting and PDF text
  (cached until the next commit); scroll forward / back and Next / Previous page turn and
  announce it, continuous and single-page; a canvas is one "Canvas" node; nothing built while
  semantics are off.
- ✅ **Arrows that stay attached** (UX_AUDIT R21-6): a line's or arrow's
  end (bent too) dropped on a closed shape's outline, or inside it (where it faces the other
  end), attaches — by handle drag or drawn so with the Shape tool; the target's outline and
  a snap dot show meanwhile. `ShapeGeometry.tail` / `tip` (synced `sh.a`, optional) keep the
  shape's id (its identity across edits, `sh.o`) and a point on its outline in the shape's own terms. Moving, resizing,
  rotating or reshaping the shape moves the ends live and in the same undo step (the
  selection's `_replace` rebuilds the lines); remote devices get both. Moved
  together they move rigidly; a line moved alone lets go (Excalidraw); copies attach to
  copied targets; a deleted target leaves the line where it is; never across pages.
- ✅ **Connector follow-ups**: shapes keep an identity across edits
  (`sh.o`, the id of the stroke first drawn; `Stroke.shapeId`) and attachments name it, so an
  edit no longer re-points arrows. Duplicated pages and notebooks, pages sent to another
  notebook and imported Len files map origins and attachment ids with the stroke ids
  (`ShapeIds`), so copied arrows attach to the copied boxes. Concurrent edits (box moved on one
  device, arrow recoloured or drawn on another) are repaired by every device applying the
  other's changes (`ConnectorRepair`, `SyncEngine.afterApply`): the line is replaced by one on
  the shape, with a deterministic id (UUID v5 of line and target ids) so devices repairing at
  once write one record; synced, no undo step, no loop. Tests: `connector_copies_test`,
  `connector_sync_test`. Still open: the duplicate arrows any two concurrent edits of one
  stroke leave (both edits survive), and a stale end restored by undo waits for the next sync
  touching its page.
- ✅ **Eyedropper** (UX_AUDIT R21-7): "Pick from page" next to Custom in every editor colour
  block (quick slots, tool options, shape fill, Style, text colour): the picker steps aside,
  "Tap a colour on the page" shows, and the next press on the page (a loupe while it rests
  or hovers) takes the content's own colour there — stroke, fill, text, image pixel — else
  the page as shown; it becomes a recent colour. Escape or chrome cancels; palms are ignored.
- ✅ **Print** (UX_AUDIT R22-8, feat/print): Print… beside Export… (⋯, Ctrl+P, and the
  library's notebook menu) opens the export sheet as a print sheet (PDF only: pages,
  templates, backgrounds; Print button) and hands the PDF over without a printing package:
  Android's print framework (`PrintPlugin.kt` streaming the file, page count from the PDF,
  cancellable writes), the Windows PDF reader's "print" verb (else opened in it), the Linux
  default viewer (the sheet says so; `lp` would print with no choices, GTK's dialog needs
  printers that take PDF) and the browser's print of a hidden frame (else a tab or a download).
- ✅ **Slide numbers** (UX_AUDIT R18-5): page numbers stay the notebook's; overview tiles and
  Go to page's strip show a PDF page's own number quietly where it differs ("26 · Slide 23",
  "PDF p. 23" for portrait PDFs), and Go to page takes "s23" / "slide 23" (several PDFs: the
  current page's wins, else it asks which).
- ✅ **Typed notes that flow across pages** (UX_AUDIT round 19, feat/text-flow): on a paged
  notebook a box reaching the bottom margin continues in a linked box at the top margin of
  the next page (a page like the last is added when needed); each page holds its part
  (`data.flow`: the box it continues, a paragraph split mid-way, list numbers running on), so
  pages draw, search and export alone. In continuous flow the whole chain is edited as one
  text in one field (page-break rooms the caret steps over: typing, deleting, selecting,
  formatting and the IME cross pages); one page at a time the box is edited alone and the
  chain flows when it ends. One undo step per edit; the lasso carries a chain by its first
  box (move, resize, restyle, delete, copy the whole text); deleted or reordered pages leave
  the rest standing alone; canvases keep growing boxes. A keystroke lays the box out once
  (plus the field's own layout). See ARCHITECTURE "Text boxes", SYNC_PROTOCOL "Text flowing
  across pages".
- ✅ **Rich copy to other apps** (UX_AUDIT round 19): Copy / Cut in a box and lasso Copy of
  text boxes put HTML on the clipboard besides the plain text (`htmlFromTexts`, the inverse
  of `textFromHtml`, round-trip property-tested: b / i / u / s, colours, highlights, fonts,
  h1 / h2, nested ul / ol, checklists with a ☐ / ☑), through the vendored `pasteboard`'s
  `write` (Linux `text/html`, Windows CF_HTML, Android `ClipData` HTML text, web
  `ClipboardItem`). Pasting back into Len still uses Len's own copy, now with its
  paragraph styles too (lists and headings were lost before).

- ✅ **Right-to-left text boxes** (UX_AUDIT round 19): each paragraph runs in the direction of
  its first strong character (bidi P2 / P3) and aligns to its own start / centre / end (`align`
  is `start` / `center` / `end` now, migration 14, strict `TextRecord` parsing); the box lays out
  in its first paragraph's direction and paragraphs against it are isolated and padded into place
  (`TextPlan`), so canvas, editing field and PDF agree. Markers, number labels (".1") and hanging
  indents sit on the start side, the alignment icon mirrors, arrows move visually, right-to-left
  auto-width boxes grow to the left. Noto Sans Arabic / Hebrew subsets bundled as fallbacks of the
  box fonts (web and PDF included); PDF export places RTL glyphs where the layout puts them and
  writes Arabic in contextual presentation forms (marks approximately placed: no GPOS).
- ✅ **Storage overview** (UX_AUDIT R16-7): Settings → Storage on every platform: the space
  Len uses here by kind (handwriting and text, PDFs, images, recordings, cached previews),
  the largest notebooks (tap to open, or Recordings to open at its recordings), "Free up
  N…" for copies of files the sync server holds (asked of the server first; never files
  not yet uploaded or of notebooks open in the editor; they download again when shown),
  "Clear" for cached previews; the web keeps its persistence and quota rows. Also: Recent
  tiles and grid cards keep a cut title's last word ("Electronics… 12").

- ✅ **Play a recording while it downloads** (UX_AUDIT R17-3): done (fix/r17-leftovers):
  playback starts once the first part needed is here and goes on part by part as the rest
  arrive (a short gap per 5-minute joint on this first listen); seeking past what is here
  fetches that part first and waits ("Downloading… 40%"). A growing joined source was not
  possible with the players (see ARCHITECTURE "Playback").
- ✅ **Reading on a phone without a stylus** (UX_AUDIT R20-6, feat/phone-reading): while
  fingers draw (no stylus ever seen), pages with content open in reading (one finger scrolls,
  zooms, follows links, long-presses for the menu); any tool or quick slot chosen writes, two
  minutes without writing reads again; the active tool's plate turns to an outline meanwhile;
  a one-time tip. No setting.

- ⬜ **Tablet check (fix/r17-leftovers)**: with the recording service failing at start, does
  it start when retried as Len leaves the front (`onPause`)? And the gap between parts
  while a recording plays part by part (ExoPlayer).

- ⬜ **Stylus edge swipes** (UX_AUDIT R15-6): with gesture navigation, a pen stroke starting
  at the screen's left or right edge may become Back (the stroke is now kept when cancelled,
  R15-5). Check on the tablet whether One UI routes stylus edge swipes at all; if it does,
  set system gesture exclusion rects over the canvas while a stylus is near (Android caps
  them at 200 dp per edge).
- ⬜ **Tablet checks for round 15**: the hover preview beside Samsung's own hover pointer (does
  the system draw one over Len? Flutter asks for a crosshair, `SystemMouseCursors.precise`);
  whether the S Pen streams hover events while held still (the cursors expire after 500 ms
  without one); a palm on the toolbar while writing.

- ⬜ **Tablet recordings** (INK_LAB *Gestures on real ink*, Ink Lab, clear before each):
  words with double ascenders at note size ("all", "little", "hello", "Hill", "tt") in
  cursive and print; scribble-outs of words at note size, quick and slow; held shapes
  (line, arrow, rectangle, triangle, ellipse, ring around a word) held until the snap.
- ⬜ **Tablet checks** (INK_LAB): the low-latency overlay's front buffer and pen-up
  handover by eye; perf-probe numbers for the later tile / LOD rounds and the background
  recogniser; writing while a 15 000-stroke canvas loads (pen-up p90 47 ms, GC pauses).
- ✅ **Scan corner drag** redraws the photo with the outline per move; a layer of its own
  for the photo would leave only the outline and loupe (PERFORMANCE). Done (perf/leftovers-2).
- ✅ **First pull** bound by SQLite inserts on the UI isolate; apply in a worker with its
  own connection (PERFORMANCE). Done (perf/leftovers-2): natively a large pull is applied in
  a worker isolate yielding to the app's writes; UI busy 4.1 s → 0.7 s for 73k records.
- ✅ **Overview thumbnails** record during a fast drag; defer them while the grid flings
  (PERFORMANCE). Done (perf/leftovers-2): not recorded over two screens a second, filled in
  when it slows.
- ✅ **Web (JavaScript)**: tiles, thumbnails and LOD rasters read back on the main thread;
  batch renders by size or keep tiles as pictures (PERFORMANCE). Done (perf/web-readback):
  CanvasKit can't make an image without a read-back and pictures would replay the ink every
  frame, so LOD rasters and page thumbnails share 512² atlases (one read-back each, the surface
  never resized: 16 small rasters 1.1–1.5 s → 0.1 s under software GL), strokes merge into
  tiles once the pen rests (no read-back between strokes), a loading page renders each tile
  once. The walk counts read-backs, resizes and shader compiles per step.
- ✅ **Web (JavaScript) big notebook**: measure `open_big` again with tiles made at once (the
  last perf/web-readback change, not rebuilt); the remaining cost there is ~70 tiles of ink
  drawn by software GL and shader compiles (PERFORMANCE "Web read-backs"). Re-measured: 72 read-backs, count back in the old range (PERFORMANCE).
- ✅ **Keyboard**: reorder overview pages: Ctrl+← / → a place, Ctrl+↑ / ↓ a row, one undo
  step each, announced ("Page 3 moved to 4"), focus follows; screen readers get Move earlier /
  later (UX_AUDIT).
- ✅ **⋯ → View is at 9 rows**: now 7; the page flow and toolbar radio pairs are one switch
  each, "One page at a time" and "Floating toolbar" (UX_AUDIT R12-7).
- ✅ **Lasso Copy reaches other apps** (UX_AUDIT R13-4): put an image of the selection on the
  system clipboard as well (GoodNotes / Notability parity: paste a diagram into a chat or an
  e-mail). Done (feat/copy-to-apps): Copy / Cut also write a transparent PNG (≈ 290 dpi, ≤ 4096
  px) and, for text boxes alone, their plain text; Len's own paste still gives ink.
- ✅ **No clipboard read on Copy**: `EditorImages` read the system clipboard on every lasso
  copy (to know what is older than the ink), which Android 12+ announces as a paste. Done
  (fix/leftovers-r7): Copy replaces the clipboard, so it is read only when `ClipboardMirror`'s
  write fails.
- ✅ **Paste here only when there is something to paste** (UX_AUDIT R13-2): the canvas menu
  always offered it, as the system clipboard can't be asked for an image without reading it
  (Android announces every read). Done (feat/clipboard-peek): `Pasteboard.peek` in the vendored
  `pasteboard` tells the kinds on the clipboard without reading it (Android `ClipDescription`,
  GTK targets, Windows formats, the web only where reads are silent); the row shows when Len
  copied ink or the peek finds an image, text or files, and when the platform can't tell.
- ✅ **What a "Len server" is** (UX_AUDIT R14-9): a "How to run a server" link beside
  Connect (while sync is not set up) opens `server/README.md` on GitHub.
