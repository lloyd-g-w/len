# Len — Roadmap to GoodNotes / Notewise parity

Status: ✅ done · 🚧 in progress · ⬜ planned

## Ink & pens
- ✅ Pressure-sensitive pen, highlighter, stroke eraser, undo/redo
- ✅ Pen types: ballpoint, fountain (direction-aware nib), brush, pencil (textured), marker
- ✅ Pen customisation: width, opacity, pressure sensitivity, stabiliser, tip taper (stored per stroke)
- ✅ Full colour picker (HSV + hex + opacity), saved favourite colours, 3 presets per pen
- ✅ Highlighter renders behind ink; hold to straighten
- ✅ Pixel (partial) eraser, eraser size, "erase highlighter only"

## Editing tools
- ✅ Lasso: select, move, resize, rotate, recolour, delete, cut/copy/paste (across pages & notebooks), duplicate
- ✅ Shapes: draw-and-hold to snap (line, arrow, rectangle, ellipse, triangle, polygon); Shape tool (line, arrow, rectangle, ellipse, triangle, diamond, star)
- ✅ Text boxes (size, colour, bold/italic, alignment, width; synced `elements`)
- ⬜ Text: font families, rich text within a box, change width/pen type of selected ink
- ✅ Images: insert from files (toolbar), the system clipboard (Ctrl+V), drag and drop (desktop) and
  the camera (Android); downscaled to 4096 px on import; beneath the ink by default with bring to
  front / send to back; move, resize, rotate, crop, duplicate, copy/paste (across notebooks), undo;
  synced as blobs; in thumbnails and PNG/PDF export
- ✅ Laser pointer
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
- ⬜ Redesigned editor chrome, focus mode, customisable toolbar
- ⬜ Open-notebook tabs

## Sync
- ✅ Self-hosted LWW record sync
- ✅ Blob sync (content-addressed PDFs and images)
- ⬜ Blob garbage collection (unreferenced blobs on device and server)
