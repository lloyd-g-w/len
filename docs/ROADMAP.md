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
- ⬜ Lasso: select, move, resize, rotate, recolour, delete, cut/copy/paste, duplicate
- ⬜ Shapes: draw-and-hold to snap (line, arrow, rectangle, ellipse, triangle, polygon)
- ⬜ Text boxes (font, size, colour)
- ⬜ Images (insert, move, resize, crop later)
- ⬜ Laser pointer
- 🚧 Gestures: two-finger tap undo, three-finger tap redo; S Pen button action setting
  (settings stored + exposed via `AppPreferences`; editor wiring pending)

## Pages & documents
- ✅ Templates: blank, narrow/college/wide ruled, small/large grid, dotted, isometric, Cornell,
  music staff; template picker with live previews (new notebooks, new pages, change one/all pages)
- ✅ Paper colours (white, cream, grey, dark)
- ✅ Page sizes (A4, A5, Letter, square) and orientation
- ✅ Page overview: live thumbnails, drag to reorder, duplicate, delete (undo), insert before/after,
  go to page
- ✅ Bookmarks (synced) with a bookmarks filter in the overview
- ✅ Continuous vertical scrolling of pages (default) or one page at a time (swipe / arrows)
- ✅ PDF import & annotate (new notebook or insert pages); export notebook / page to PDF (vector
  ink) and page to PNG; save dialog on desktop, share sheet on Android
- ⬜ Planner / custom (image) templates; paper colour for infinite canvases
- ⬜ Tiled PDF rendering for extreme zoom; PDF text selection / links / outline
- ⬜ Export keeps imported PDF pages as vectors (currently embedded at 150 dpi)

## Library
- ✅ Folders (nested, synced), move to folder (menu + drag and drop), breadcrumbs, folder tree
- ✅ Search (across folders), sort (edited / created / name), favourites, grid/list views
- ✅ Live cover thumbnails, more cover colours + patterns
- ✅ Trash with restore / delete forever / empty, duplicate notebook

## App
- ✅ Theme mode (system/light/dark), accent colour
- ✅ App shell: sidebar (tablet/desktop), bottom navigation (phone), context menus,
  keyboard shortcuts, redesigned settings
- 🚧 Redesigned editor chrome: tool-descriptor toolbar with contextual quick controls (✅);
  focus mode, customisable / dockable toolbar, favourite tools (⬜)
- ⬜ Open-notebook tabs

## Sync
- ✅ Self-hosted LWW record sync
- ✅ Blob sync (content-addressed PDFs; images later)
- ⬜ Blob garbage collection (unreferenced blobs on device and server)
