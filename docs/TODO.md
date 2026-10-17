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
- 🚧 (fix/mouse-ink-2) **Smoother ink, mouse first** (owner): default stabiliser 30 %; mouse
  ink is only acceptable at 30 % and still a little bumpy — steady width, light smoothing at
  every width, less bumpiness at 0 % too.
- 🚧 (merged; to verify on the tablet, flicker log in Ink Lab) **The pen still flickers sometimes** on the Android tablet (S Pen),
  no clear pattern: find every handover / prediction / tile cause, test, fix, and add an
  on-device flicker log to catch the rest.
- ✅ **Dotted paper's dots change size on zoom** (they kept a constant
  on-screen size): dots get a fixed world size and scale with the page everywhere.
- ✅ **Ruled and grid lines** had the same flaw (one screen pixel at
  every zoom): a fixed page width matching PDF export, at least about a pixel.

## Owner asks (round 13)
- ⬜ **Highlighter and laser customisation like the pen's**: every option the pen has that
  makes sense (editable quick colour slots and their count, quick sizes, pressure, stabiliser,
  ends, preview, Reset) on the highlighter and the laser pointer too; the laser's three fixed
  colours become editable slots, with quick sizes.
- ⬜ **Better shape control points** (pen → shape and the Shape tool): handles by meaning,
  not bounding-box corners: a circle / ellipse by centre (move) and radius (or two radii and a
  rotation), rectangle corners + edge midpoints + rotation, line / arrow endpoints (and a bend),
  polygon / triangle / diamond vertices, star centre + outer / inner radius + points; snapping
  and Shift constraints while dragging; one undo step per drag; synced.
- ⬜ **Arbitrary curves**: a Curve kind (cubic Bézier spline, open or closed) in the Shape
  tool (tap / drag to place anchors and pull tangents) and from pen → shape (a held smooth
  stroke that is no other shape snaps to a fitted spline); anchors and tangent handles
  editable on selection, add / remove anchors; fill when closed.
- ⬜ **The pen still flickers sometimes** (owner, again): keep hunting every cause on every
  platform (Linux, web, Android), with frame-by-frame tests.
- ⬜ **Live sync, actually live**: edits show on other devices within a fraction of a second
  (push on pen-up, server fans the records out over one long-lived connection, no pull
  round trip), built as the foundation for real-time collaboration: a WebSocket channel with
  rooms per notebook, ephemeral messages (in-progress strokes, presence / cursors) next to
  records; documented in SYNC_PROTOCOL.md; falls back to today's pull when the channel is down.

## Next (open follow-ups, not yet asked for)
From the reports; the owner picks. Status as above.

- ⬜ **Pages to screen readers** (UX_AUDIT R23-10): one semantics node per laid-out page
  ("Page 3 of 12, bookmarked") whose value is its text boxes' text and the recognised
  handwriting (`HandwritingIndex`), with scroll actions that go to the next / previous page and
  announce it. Paged and continuous views, PDFs' own text; keep the tree cheap while scrolling.
- ⬜ **Arrows that stay attached** (UX_AUDIT R21-6): an arrow or line end dropped on a
  shape's outline remembers the shape (a synced reference in `ShapeGeometry`); moving,
  resizing or reshaping the shape moves the end (one undo step with it). None of GoodNotes,
  Notability or Samsung Notes has connectors; whiteboard apps do. Large: geometry format,
  `TransformItems`, selection plans across pages, sync, undo.
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
