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
- ✅ Text boxes (synced `elements`): rich text within a box — bold, italic, underline,
  strikethrough, colour, highlight, size and font per character; headings; bulleted, numbered
  and checklist items (tap to tick, Tab to indent); bundled open-licence fonts (Inter, Lora,
  JetBrains Mono, Caveat) with a font picker and default text style; auto-width boxes that wrap
  once resized; Ctrl+B / I / U and list shortcuts; copy / cut / paste keep formatting between
  boxes; Ctrl+V of plain text adds a text box; exported to PDF as selectable text in embedded
  fonts
- ✅ Lasso *Style*: font and size of selected text boxes, pen type and width of selected ink
- ⬜ Text: hanging indents for wrapped list items, rich paste from other apps, more fonts / font
  import, paragraph spacing, tables
- ✅ Images: insert from files (top bar), the system clipboard (Ctrl+V), drag and drop (desktop) and
  the camera (Android); downscaled to 4096 px on import; beneath the ink by default with bring to
  front / send to back; move, resize, rotate, crop, duplicate, copy/paste (across notebooks), undo;
  synced as blobs; in thumbnails and PNG/PDF export
- ✅ Laser pointer
- ✅ Gestures: two-finger tap undo, three-finger tap redo (with a HUD; palm-safe), S Pen side
  button action (eraser / hold to lasso / none), finger long press or right click → canvas menu
  (paste here, select all on page, add text here, page commands)

## Audio
- ✅ Record audio while writing (pause / resume, level meter; top bar on tablets/desktops, menu +
  floating controls on phones), recordings list (play, rename, delete), synced as blobs
- ✅ Ink replay: ink, text boxes and images made later than the playback position are faded; ink
  appears from when it was begun (strokes are stamped at pen-down); tap ink, a text box or an
  image to play from when it was made
- ✅ Background recording on Android: foreground service (type microphone) with a notification
  (time, pause / resume, stop), keeps recording with the screen off or another app in front;
  notification permission asked once (Android 13+)
- ✅ Player: waveform scrubber (captured while recording, synced as a small blob) with ink density
  and a marker per burst of writing (tap to play from it), skip ±10 s, speed 0.75–2×, keys (Space,
  ← / →, Shift+← / → between bursts of writing)
- ✅ Recordings list: date, duration and size of each, total; select several to export or delete;
  export / share a recording's audio (m4a) through the save / share path
- ⬜ Trimming, upload while recording (chunked blobs), recovering a recording cut off by a killed
  process, playback in the background (media notification)

## Pages & documents
- ✅ Templates: blank, narrow/college/wide ruled, small/large grid, dotted, isometric, Cornell,
  music staff; template picker with live previews (new notebooks, new pages, change one/all pages)
- ✅ Paper colours (white, cream, grey, dark)
- ✅ Page sizes (A4, A5, Letter, square) and orientation
- ✅ Page overview: live thumbnails, drag to reorder (drop indicator), duplicate, delete (undo),
  insert before/after, go to page, "Add page" tile, selection mode (bookmark / duplicate / delete
  several pages, one Undo)
- ✅ Bookmarks (synced) with a bookmarks filter in the overview
- ✅ Continuous vertical scrolling of pages (default) or one page at a time (swipe / arrows)
- ✅ Page navigation: smooth scroll-to-page, whole-page fit + slide in single-page flow, "Add page"
  after the last page, arrow / PageUp / Home / End keys, jump to page, compact indicator on phones
  (peeks in while pages move, never covers the page)
- ✅ Page zoom: automatic (fit width, but most of a page stays visible on landscape) / fit width /
  fit page, per notebook; notebooks and canvases reopen where you left off (canvases otherwise
  centred on their content)
- ✅ PDF import & annotate (new notebook or insert pages); export notebook / page to PDF (vector
  ink) and page to PNG; save dialog on desktop, share sheet on Android
- ✅ Progress for import / export: stage, file name, "Page x of n" bar
- ✅ Export options sheet: PDF / PNG, current / all pages / page range, page templates and PDF
  backgrounds on or off, PNG resolution (192 / 384 dpi); several PNGs shared or saved at once
- ✅ Planner templates: daily planner, weekly planner (week grid), monthly calendar — date-aware
  (pick the first month and 1–12 months; correct days, leap years, ISO weeks), optionally a linked
  planner (each month followed by its weeks and days) with month → week → day links (finger tap
  in stylus mode, Ctrl/⌘-click, long-press menu; "Add page" when a target is missing); adding a
  page after a planner page continues the dates
- ✅ More templates: to-do list, meeting notes, storyboard, graph paper (mm, detail appears when
  zooming in), engineering paper — all procedural (vector lines and text, crisp at any zoom, also
  in PDF export)
- ✅ Custom templates ("My templates", synced): import an image or a PDF page, "Save page as
  template"; rename / delete; usable for new notebooks and pages
- ✅ Template picker: categories (Basic, Writing, Planners, Paper, My templates), search, live
  previews
- ✅ Planner options: week starting on Monday or Sunday (US week numbers for Sunday weeks),
  month and day names and dates in 19 languages (intl; default from the device locale, last
  choice remembered), year overview (twelve mini calendars linking to months and days; optional
  first page of a monthly planner); exported PDF labels in the embedded Inter
- ✅ Cancel long imports / exports (partial imports clean up after themselves)
- ✅ Tiled PDF rendering for deep zoom (visible tiles, LRU, smooth while zooming)
- ✅ PDF text selection (Select text tool, long press / right click): copy, highlight the selection
  with highlighter strokes snapped to the lines; links (jump to page, web links after a prompt);
  outline (bookmarks) panel
- ✅ Export keeps imported PDF pages as vectors (pure-Dart page copier; PDFium rewrite for
  encrypted files; image fallback per page)
- ⬜ Selection across pages, PDF text on rotated pages, carry links into exported PDFs

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
- ✅ Full-text search (local FTS5 index, kept current by triggers incl. sync): titles, folders,
  text boxes and imported PDF text; library results grouped by notebook with page numbers and
  highlighted snippets (tap opens the page and highlights the match)
- ✅ In-notebook search (Ctrl+F): match list, next/previous, highlights on text boxes and exact
  PDF glyphs
- ✅ Handwriting search on Android (ML Kit Digital Ink, on-device, per-language models from the
  device locale or settings): background indexing in quiet moments, incremental per line, kept
  current through undo and sync; results in the library and the editor with word highlights
- ✅ Lasso "Convert to text": recognised text with alternatives, editable; replace the ink with a
  text box (same place, colour, size; one undo) or copy
- ⬜ Handwriting recognition on Windows (WinRT ink analysis) / Linux / web; sync recognised text
- ✅ Live cover thumbnails, more cover colours + patterns
- ✅ Trash with restore / delete forever / empty, duplicate notebook
- ✅ Create sheet with a live cover + first-page preview, Paper / Cover galleries, size and paper
  colour (dialog on wide screens, tall sheet on phones); grouped template gallery
- ✅ Selection mode: favourite, move, trash (undo), restore, delete forever for many notebooks
- ✅ Cards show page count and short dates; consistent dialogs; empty states with actions
- ✅ "New…" tile in the grid; folder icons (synced, picked in the folder dialog)

## App
- ✅ Web target (PWA): SQLite wasm + IndexedDB, blobs in IndexedDB, PDF import/render (PDFium wasm),
  export downloads, sync via CORS, one tab at a time; `--wasm` build works
- ⬜ Web: request persistent storage, offline service-worker caching review, background reads in a web worker
- ✅ Theme mode (system/light/dark), accent colour
- ✅ App shell: sidebar (tablet/desktop), bottom navigation (phone), context menus,
  keyboard shortcuts, redesigned settings
- ✅ Settings: theme previews, Stylus / Gestures / Editor (toolbar position) sections with
  descriptions; everything checked at 1.3× text (see `docs/UX_AUDIT.md`)
- ✅ Two-pane settings on wide screens
- ✅ Redesigned editor chrome (GoodNotes-style top bar: back, pages, bookmark, title, undo/redo,
  export, focus, more menu), tool-descriptor toolbar with contextual quick controls, toolbar
  position (automatic / top / bottom / floating, draggable), focus mode (F11 / Ctrl+.) with
  immersive system bars
- ✅ Open-notebook tabs (up to 8, each keeps its page and zoom; tab strip on tablets/desktops,
  switcher on phones; Ctrl+Tab, Ctrl+W)
- ✅ Editor UX round 2: toolbar in groups (≥ 40 px targets, optional tool names), one-row phone
  toolbar with a tool switcher, title left-aligned with the folder on every size, open-notebook
  transition from the cover, export options, one-time tips (pen side button, multi-finger taps),
  empty-canvas hint, Escape closes chrome menus
- ⬜ Customisable toolbar contents, favourite tools (in-editor search: ✅ text and PDF, see Library)
- ✅ App identity: one icon design for all platforms (Android adaptive + themed icon), splash
  screen, edge-to-edge system bars, Linux desktop entry, Windows window placement
- ✅ CI (analyze, tests, Linux/Android/Web/Windows builds, server image) and tagged releases
  (APK, Linux tarball, Windows zip, web zip, GHCR server image)
- ✅ "Open with Len" / "Share to Len": PDFs → new notebook (or pages of the open notebook),
  images → new canvas (or onto the open page / canvas), asked when an editor is open; Android
  intents (cold + warm start), Linux command line + desktop-entry MIME types + single instance,
  Windows command line, PWA file handlers, drag and drop onto the library (desktop + web)
- ⬜ Windows file associations (installer) and single-instance forwarding; store listings
  (Play / F-Droid / Flathub / winget)

## Sync
- ✅ Self-hosted LWW record sync
- ✅ Blob sync (content-addressed PDFs, images and audio)
- ✅ Blob garbage collection (unreferenced blobs on device and server); oversized blobs no longer block sync
