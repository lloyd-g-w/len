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

## Next (open follow-ups, not yet asked for)
From the reports; the owner picks. Status as above.

- ⬜ **Tablet recordings** (INK_LAB *Gestures on real ink*, Ink Lab, clear before each):
  words with double ascenders at note size ("all", "little", "hello", "Hill", "tt") in
  cursive and print; scribble-outs of words at note size, quick and slow; held shapes
  (line, arrow, rectangle, triangle, ellipse, ring around a word) held until the snap.
- ⬜ **Tablet checks** (INK_LAB): the low-latency overlay's front buffer and pen-up
  handover by eye; perf-probe numbers for the later tile / LOD rounds and the background
  recogniser; writing while a 15 000-stroke canvas loads (pen-up p90 47 ms, GC pauses).
- ✅ **Scan corner drag** redraws the photo with the outline per move; a layer of its own
  for the photo would leave only the outline and loupe (PERFORMANCE). Done (perf/leftovers-2).
- ⬜ **First pull** bound by SQLite inserts on the UI isolate; apply in a worker with its
  own connection (PERFORMANCE).
- ✅ **Overview thumbnails** record during a fast drag; defer them while the grid flings
  (PERFORMANCE). Done (perf/leftovers-2): not recorded over two screens a second, filled in
  when it slows.
- ⬜ **Web (JavaScript)**: tiles, thumbnails and LOD rasters read back on the main thread;
  batch renders by size or keep tiles as pictures (PERFORMANCE).
- ⬜ **Keyboard**: reorder overview pages (drag only today; UX_AUDIT).
- ⬜ **⋯ → View is at 9 rows**: merge before adding the next toggle, e.g. the two toolbar
  radios into one "Floating toolbar" switch (UX_AUDIT R12-7).
