# Len — owner TODO (working list)

The owner's current asks, kept here so every round can check them off.
Status: ⬜ open · 🚧 an agent is on it (branch) · ✅ merged into main.

## Shapes
- ⬜ **The Shape tool is very broken**: redo the drag-to-draw for every kind (line, arrow,
  rectangle, ellipse, triangle, diamond, star): predictable, live preview, Shift constraints,
  no jumps.
- ⬜ **Pen → shape (hold to snap) is equally broken**: reliable recognition, a clean snap,
  no false snaps, the snapped shape where the hand drew it.
- ⬜ **Editable control points on selection** for both drawn and snapped shapes (corners,
  endpoints, ellipse bounds, star/polygon vertices; one undo step per drag; synced).

## Lasso / selection
- ✅ **Selection options**: what to select (ink, highlighter, text, images, shapes),
  **partial vs whole** (touching vs fully enclosed), and **selection shapes** (freehand lasso,
  rectangle). Lasso popover: Shape (Freehand / Rectangle), Select (Touching / Mostly / Whole;
  Mostly, the old rule, stays the default), Items (Ink, Highlighter, Text, Images; shapes are
  ink, links go with images).

## Highlighter
- ⬜ **Same engine as the pen**, with the same customisability where it makes sense
  (round vs flat ends, pressure, …). Explain or unify.
- ⬜ **Highlighter flickers on pen-up**: fix.

## Eraser
- ⬜ **Scribble to erase takes too many scribbles**: trigger after fewer zig-zags (1–2
  back-and-forths), without false positives in normal writing.

## Notebooks
- ⬜ **Default notebook style**: set the default template, paper, size and cover for new
  notebooks.
- ⬜ **Own presets / styles**: save and reuse notebook styles (template + paper + size +
  cover), and pen presets.

## Laser pointer
- ✅ **Keep-while-writing option**: the trail stays until about 2 s after pen-up; writing
  again within that time keeps everything showing (nothing fades between strokes). Laser
  popover: Fade (Each stroke / When I stop), "Fades after" 0.5–5 s (default 2 s).

## Infinite canvas
- ⬜ **Minimap, polished**: shows roughly where content is, the current view, tap / drag to
  move; minimal, toggleable.

## Input
- ⬜ **Mouse strokes zoomed out are squiggly (web and Linux)**: mouse ink at low zoom must be
  as smooth as at 100 %.

## Done earlier this round
- ✅ Shape fill, zoom window, document scan, keyboard accessibility, round 10 audit,
  bug hunts (17 + 8 bugs).
