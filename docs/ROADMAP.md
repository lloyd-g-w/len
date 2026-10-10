# Len — Roadmap to GoodNotes / Notewise parity

Status: ✅ done · 🚧 in progress · ⬜ planned

## Ink & pens
- ✅ Pressure-sensitive pen, highlighter, stroke eraser, undo/redo
- ✅ Focused line-up: Pen (ballpoint) + Highlighter + Eraser (older pen types still render)
- ✅ Smooth ink at any zoom: arc-length filtering, Bézier envelope outlines, tangent round caps
- ✅ Independent quick colours and quick widths per ink (1–6 slots each, GoodNotes-style editing)
- ✅ Pen settings: pressure sensitivity, stabiliser, tapered ends (stored per stroke);
  highlighter opacity
- ✅ Full colour picker (HSV + hex), saved favourite colours
- ✅ Highlighter renders behind ink; hold to straighten
- ✅ Pixel (partial) eraser, eraser size, "erase highlighter only"

## Editing tools
- ✅ Lasso: select, move, resize, rotate, recolour, delete, cut/copy/paste (across pages & notebooks), duplicate
- ✅ Shapes: draw-and-hold to snap (line, arrow, rectangle, ellipse, triangle, polygon); Shape tool (line, arrow, rectangle, ellipse, triangle, diamond, star)
- ✅ Text boxes (size, colour, bold/italic, alignment, width; synced `elements`)
- ⬜ Text: font families, rich text within a box, change width/pen type of selected ink
- ⬜ Images (insert, move, resize, crop later) — element model ready (`type: "image"` + blob hash)
- ✅ Laser pointer
- ✅ Gestures: two-finger tap undo, three-finger tap redo (with a HUD; palm-safe), S Pen side
  button action (eraser / hold to lasso / none), finger long press or right click → canvas menu
  (paste here, select all on page, add text here, page commands)

## Pages & documents
- ✅ Templates: blank, narrow/college/wide ruled, small/large grid, dotted, isometric, Cornell,
  music staff; template picker with live previews (new notebooks, new pages, change one/all pages)
- ✅ Paper colours (white, cream, grey, dark)
- ✅ Page sizes (A4, A5, Letter, square) and orientation
- ✅ Page overview: live thumbnails, drag to reorder, duplicate, delete (undo), insert before/after,
  go to page
- ✅ Bookmarks (synced) with a bookmarks filter in the overview
- ✅ Continuous vertical scrolling of pages (default) or one page at a time (swipe / arrows)
- ✅ Page navigation: smooth scroll-to-page, whole-page fit + slide in single-page flow, "Add page"
  after the last page, arrow / PageUp / Home / End keys, jump to page, compact indicator on phones
- ✅ PDF import & annotate (new notebook or insert pages); export notebook / page to PDF (vector
  ink) and page to PNG; save dialog on desktop, share sheet on Android
- ⬜ Planner / custom (image) templates
- ⬜ Tiled PDF rendering for extreme zoom; PDF text selection / links / outline
- ⬜ Export keeps imported PDF pages as vectors (currently embedded at 150 dpi)

## Infinite canvas & navigation
- ✅ Level-of-detail chunk rasters when zoomed out (cost bounded by visible chunks)
- ✅ Chunk loading in a background isolate; strokes indexed only along their path
- ✅ Kinetic (inertial) panning — canvases and continuous pages
- ✅ Animated zoom: keyboard `+` `-` `0`, Shift+1 fit; zoom indicator with 50/100/200 %/fit
- ✅ Minimap (populated chunks + viewport, tap/drag to move), fit content, back to start
- ✅ Canvas background: template + paper colour
- ⬜ Double-tap zoom gesture; persistent LOD tiles; LOD for paged documents

## Library
- ✅ Folders (nested, synced), move to folder (menu + drag and drop), breadcrumbs, folder tree
- ✅ Search (across folders), sort (edited / created / name), favourites, grid/list views
- ✅ Live cover thumbnails, more cover colours + patterns
- ✅ Trash with restore / delete forever / empty, duplicate notebook

## App
- ✅ Theme mode (system/light/dark), accent colour
- ✅ App shell: sidebar (tablet/desktop), bottom navigation (phone), context menus,
  keyboard shortcuts, redesigned settings
- ✅ Redesigned editor chrome (GoodNotes-style top bar: back, pages, bookmark, title, undo/redo,
  export, focus, more menu), tool-descriptor toolbar with contextual quick controls, toolbar
  position (automatic / top / bottom / floating, draggable), focus mode (F11 / Ctrl+.) with
  immersive system bars
- ✅ Open-notebook tabs (up to 8, each keeps its page and zoom; tab strip on tablets/desktops,
  switcher on phones; Ctrl+Tab, Ctrl+W)
- ⬜ Customisable toolbar contents, favourite tools; search in the editor (handwriting recognition)

## Sync
- ✅ Self-hosted LWW record sync
- ✅ Blob sync (content-addressed PDFs; images later)
- ⬜ Blob garbage collection (unreferenced blobs on device and server)
