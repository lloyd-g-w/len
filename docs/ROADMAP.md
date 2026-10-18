# Len — Roadmap to GoodNotes / Notewise parity

Status: ✅ done · 🚧 in progress · ⬜ planned

## Ink & pens
- ✅ Pressure-sensitive pen, highlighter, stroke eraser, undo/redo
- ✅ Pressure curve fitted to real S Pen handwriting (light hands draw the pen's width and the
  ink follows their pressure; INK_LAB F11)
- ✅ Pixel eraser: fragments keep the original's resampling phase, so nothing else moves (F12)
- ✅ Flat ends (highlighter, flat pen ends) stay square over curls tighter than the ink; one
  highlighter stroke is one even layer where it crosses itself
- ✅ Focused line-up: Pen (ballpoint) + Highlighter + Eraser (older pen types still render)
- ✅ Smooth ink at any zoom: arc-length filtering, Bézier envelope outlines, tangent round caps
- ✅ Independent quick colours and quick widths per ink (1–5 slots each, GoodNotes-style editing)
- ✅ Pen settings: pressure sensitivity, stabiliser (stored per stroke);
  highlighter opacity
- ✅ Full colour picker (HSV + hex), saved favourite colours
- ✅ Highlighter renders behind ink; hold to snap a clean line; on PDF text a highlight snaps to
  the words it covers (highlighter settings → Snap to text, on by default)
- ✅ Committed ink from a tile raster cache (frame cost independent of the ink on screen, pen-up
  drawn over tiles, writes after the frame, outlines of loaded strokes on worker isolates; pans and
  scrolls keep tiles, large edits swap in together, pages render ahead, rasterised page
  thumbnails); no pen-up flicker (a highlight over many tiles drawn beneath them until they
  re-render)
- ⬜ Tablet numbers for the later tile and LOD rounds and the background recogniser (INK_LAB:
  measured headless only); writing while a 15 000-stroke canvas loads (pen-up p90 47 ms, GC)
- ⬜ Visual check of the low-latency overlay's front buffer and pen-up handover on a real tablet
- ✅ Highlighter on the pen's engine (sampling, smoothing, stabiliser, outline) with the pen's
  feel options: pressure sensitivity (off by default) and flat (default) or round ends
- ✅ Smooth mouse ink at any zoom: whole-pixel mouse steps levelled on screen first for pens
  under 2.5 px on screen (`MouseSmoother`); at 100 % mouse ink is unchanged, no lag
- ✅ Pixel (partial) eraser, eraser size, "erase highlighter only"
- ✅ Scribble to erase: two quick back-and-forths of the pen over ink erase it where it zigzags
  (Settings → Writing, taught once by a tip); what will go dims while scribbling; zigzag letters,
  joined-up writing and hatching don't trigger it
- ⬜ Real tablet recordings for hold to snap and scribble to erase (scribble-outs, held shapes,
  double ascenders; tuned on simulated and reshaped input so far, INK_LAB *Gestures on real ink*)

## Editing tools
- ✅ Lasso: select, move, resize, rotate, recolour, delete, cut/copy/paste (across pages & notebooks), duplicate;
  copy also puts a picture of the selection on the system clipboard for other apps (text boxes
  also as text), while pasting back in Len gives ink
- ✅ Lasso options: freehand or rectangle; select what it touches, what is mostly inside or only
  what is wholly inside; which items (ink, highlighter, text, images); remembered with the tools;
  the side-button lasso and taps follow them, a rectangle from PDF text selects the text
- ✅ Selection across pages (continuous scrolling): a lasso drawn across pages selects on each; the
  selection moves, resizes, recolours, restyles, deletes, copies and duplicates as one; items dropped
  so their centre lands on another page move to that page (ink re-added, elements re-parented) — one
  undo step. Single-page flow keeps per-page selections
- ✅ Shapes: draw-and-hold to snap, in place (line, arrow, rectangle, ellipse, triangle, diamond,
  polygon; handwriting and small letters never snap); Shape tool (line, arrow, rectangle, ellipse,
  triangle, diamond, star) with a live preview from the press to the pointer (Shift: regular shapes / 15° lines)
- ✅ Editable shapes: a selected shape (drawn or snapped) shows its control points — ends, corners,
  vertices, ellipse bounds, star points and inner radius — to drag; one undo step, fill kept,
  synced (`style.sh`)
- ✅ Shape fill: closed shapes (drawn or snapped) filled with none, a light / medium / strong tint
  of their ink or a solid colour — picked in the Shapes options, changed on a selection's Style;
  live, tiles, thumbnails, replay, PDF / PNG export, synced (`style.f`), undoable
- ✅ Text boxes (synced `elements`): rich text within a box — bold, italic, underline,
  strikethrough, colour, highlight, size and font per character; headings; bulleted, numbered
  and checklist items (tap to tick, Tab to indent) with hanging indents when they wrap (canvas,
  editing field and PDF alike); bundled open-licence fonts (Inter, Lora, JetBrains Mono,
  Caveat) with a font picker and default text style; auto-width boxes that wrap
  once resized; Ctrl+B / I / U and list shortcuts; copy / cut / paste keep formatting between
  boxes; Ctrl+V of plain text adds a text box; exported to PDF as selectable text in embedded
  fonts
- ✅ Text: rich paste from other apps — HTML (browsers, Google Docs, Word, LibreOffice) keeps bold,
  italic, underline, strikethrough, colours, headings and nested lists / checklists, in a box being
  edited or as a new box on the canvas (Windows, Linux, Android, web); Ctrl+Shift+V pastes plain
  text
- ✅ Text: RTF-only paste (WordPad, TextEdit-style RTF, LibreOffice / AbiWord on Linux) — formatting,
  colours, mono fonts, relative font sizes, headings and lists from a pure-Dart RTF reader (Windows,
  Linux; web where the browser passes RTF in its paste event)
- ✅ Lasso *Style*: font and size of selected text boxes, pen type and width of selected ink
- ✅ Text: paragraph spacing (None / Small / Medium / Large below each paragraph, per box: format
  bar, on phones its ⋯; default in the Text tool's options), synced, flowing across pages, in PDF
  export, rich copy / paste (`margin-bottom`) and search highlights
- ⬜ Text: font import, tables
- ✅ Images: insert from files (top bar), the system clipboard (Ctrl+V), drag and drop (desktop) and
  the camera (Android); downscaled to 4096 px on import; beneath the ink by default with bring to
  front / send to back; move, resize, rotate, crop, duplicate, copy/paste (across notebooks), undo;
  synced as blobs; in thumbnails and PNG/PDF export
- ✅ Laser pointer
- ✅ Laser "Fade: When I stop": everything written stays until ~2 s (adjustable) after the last
  pen-up; writing again within that time keeps it all (mouse, pen or finger; presenting too)
- ✅ Zoom window (⋯ → View, `M`): a frame on the page magnified in a box docked above the bottom
  toolbar; writing in the box writes small into the frame, which moves on along the line as you
  reach the box's right end, wraps to the next ruled line (↵ too) and on to the next page (adding
  one after the last); drag the frame to move it, its corner handle to size it, pinch or pan the
  box; works on pages and the infinite canvas
- ✅ Zoom window, round 2: frame and box height remembered per notebook, box height dragged at
  its edge (⋯ → Automatic height undoes it), Left-handed (box docked at the top), the frame moved
  by its tab so the pen writes inside it on the page, the advance announced as the zone deepens
- ✅ Zoom window: right-to-left advance (box ⋯ → *Right to left*; at first as the device's
  language runs): the frame advances leftwards from the right margin, a new line returns to the
  right
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
  export / share a recording's audio (AAC) through the save / share path
- ✅ Upload while recording: recordings are stored in 5-minute parts (raw AAC natively), each a
  blob synced as soon as it is finished; played and exported as one
- ✅ Recovering a recording cut off by a killed app (native: journal + spool files, "Recover
  recording?" on the next start; browsers keep the parts finished before)
- ✅ Trimming (GoodNotes-style handles on the player's waveform, preview, Cancel / Save, "Reset
  trim"): non-destructive, synced (`trimStartMs` / `trimEndMs`); playback, list durations, ink
  replay, markers and export (raw AAC cut at frame boundaries) keep to the kept audio
- ✅ Playback in the background: Android media notification and lock screen (recording,
  notebook; play / pause, ±10 s, seek, stop; `mediaPlayback` foreground service), headset and
  Bluetooth buttons, audio focus (pauses for calls and other apps, resumes after a call, ducks),
  pauses when headphones are unplugged; MPRIS on Linux (GNOME / KDE controls, media keys);
  the browser's Media Session; media keys on Windows while Len is in front
- ⬜ Windows system media controls (SMTC) for playback
- ✅ Trimming that frees storage: "Free up 12 MB…" in a recording's menu drops the 5-minute
  parts wholly outside the trim on every device (confirmed, Undo in the message; blob GC frees
  them after its grace). Trimmed browser recordings export only the parts the trim touches
  (the message says they may start earlier or end later)
- ⬜ Exact trimmed export of browser recordings (cut WebM clusters / fragmented-MP4 fragments
  in Dart instead of whole parts)

## Pages & documents
- ✅ Templates: blank, narrow/college/wide ruled, small/large grid, dotted, isometric, Cornell,
  music staff; template picker with live previews (new notebooks, new pages, change one/all pages)
- ✅ Paper colours (white, cream, grey, dark)
- ✅ Page sizes (A4, A5, Letter, square) and orientation
- ✅ Page overview: live thumbnails, drag to reorder (drop indicator), duplicate, delete (undo),
  insert before/after, go to page, "Add page" tile, selection mode (bookmark / duplicate / delete
  several pages, one Undo)
- ✅ Page sidebar (tablets held sideways, desktops; per split pane with room): a slim column of
  live thumbnails beside the page — the page on screen marked and kept in view, tap to go, drag
  to reorder (one undo step), hold or right-click for the page menu, bookmarks and slide
  numbers, Add page at the end; from the overview's "Show beside the page" or F4, remembered
  per notebook, hidden in focus mode; keyboard: one Tab stop, ↑ ↓ Home End, Ctrl+arrows
- ✅ Move or copy pages to another notebook (overview selection and page menu): ink, elements,
  links among them, outline entries and the recordings they were written during go along; links
  to moved pages follow them; or into a new notebook with the source's paper and cover; one Undo
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
- ✅ Document scanning ("Scan document…" in the library's ⊕▾ / new-notebook sheet → a new
  notebook; Insert ⊕ in paged notebooks → pages after the current one, one Undo): photos from
  files (every platform) or the camera (Android); the page's edges are found (pure Dart, on an
  isolate) to a fraction of a pixel, four corners and four sides to drag with a loupe, a large
  Preview of the cleaned-up page, rotate, whole photo, retake, remove, more pages, reorder (drag in
  the strip, Ctrl+← / →); Colour / Greyscale / B&W clean-up (white paper, even light, crisp ink),
  remembered for the next scan; big photos kept at 3200 px so long scans stay light; pages are
  flattened JPEG backgrounds (A4 / Letter when they're that shape), synced as blobs, exported
- ✅ Camera photos survive a kill: a photo taken while Android killed Len is recovered on the next
  start and goes where it was meant to (the scan carries on, or Insert → Take photo places it)
- ✅ Progress for import / export: stage, file name, "Page x of n" bar
- ✅ Export options sheet: PDF / PNG, current / all pages / page range, page templates and PDF
  backgrounds on or off, PNGs at 288 dpi; several PNGs shared or saved at once
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
- ✅ Notebook styles (synced): save the new-notebook sheet's choice (notebook or canvas,
  template and look, paper colour, size, orientation, cover) as a named style, apply it with one
  tap, mark one the default for new notebooks, rename / delete; without a default the sheet
  starts as the last notebook was made
- ✅ Template picker: categories (Basic, Writing, Planners, Paper, My templates), search, live
  previews; a dialog with gallery and options side by side on tablets / desktops, a sheet with
  full-width columns on phones
- ✅ Planner options: week starting on Monday or Sunday (US week numbers for Sunday weeks),
  month and day names and dates in 19 languages (intl; the device locale's), week start
  defaulting to the locale's (last choice remembered), year overview (twelve mini calendars linking to months and days; optional
  first page of a monthly planner; month pages link back up from their year label, weeks and
  days to their month); exported PDF labels in the embedded Inter
- ✅ Cancel long imports / exports (partial imports clean up after themselves)
- ✅ Print (⋯ → Print…, Ctrl+P, the library's notebook menu): the export sheet as a PDF (pages,
  templates, backgrounds) handed to Android's print dialog, the Windows PDF reader's print, the
  Linux default viewer or the browser's print dialog; no printing package
- ✅ Tiled PDF rendering for deep zoom (visible tiles, LRU, smooth while zooming)
- ✅ PDF text selection (long press / right click, then drag the handles): copy, highlight the selection
  with highlighter strokes snapped to the lines; links (jump to page, web links after a prompt);
  outline (bookmarks) panel
- ✅ Export keeps imported PDF pages as vectors (pure-Dart page copier; PDFium rewrite for
  encrypted files; image fallback per page)
- ✅ PDF text on rotated pages (`/Rotate` 90 / 180 / 270 and text set at an angle): selection along
  the line's direction, copy, highlights, search highlights and links
- ✅ Exported PDFs keep links: link elements, planner links, and the links of imported PDF pages
  (web links as is, page links remapped to the exported page or dropped)
- ✅ PDF text selection across pages (drag a handle onto another page; copy joins pages
  with a blank line; highlight marks every page)

## Infinite canvas & navigation
- ✅ Level-of-detail chunk rasters when zoomed out (cost bounded by visible chunks)
- ✅ Chunk loading in a background isolate; strokes indexed only along their path
- ✅ Kinetic (inertial) panning — canvases and continuous pages
- ✅ Animated zoom: keyboard `+` `-` `0`, Shift+1 fit; zoom indicator with 50/100/200 %/fit
- ✅ Fit content, back to start
- ✅ Minimap (⋯ → View, Shift+M): content as soft blocks, the view's frame; tap to glide, drag to
  pan live, pinch / scroll to zoom; hides while writing and in focus mode
- ✅ Canvas background: template + paper colour
- ✅ Double-tap zoom (finger, when fingers navigate): page fit / 100 % ⇄ 2× or the last zoom, about
  the tap; palm-safe, never confused with two-finger undo
- ✅ Native-feeling gestures: touch and pinch slop (taps never nudge the page, two-finger pans
  never drift in zoom), rubber-band zoom limits with spring back, pinches snap to the page fit /
  100 %, palms between pen strokes ignored; single-page flow turns by flick, long drag, trackpad
  swipe or wheel notch and settles back otherwise; arrow keys scroll / move, `+` `-` zoom pages
- ✅ Single-page flow: the page follows a sideways finger, glides back or carries on into the
  next page (`SinglePageTurns.follow`)
- ✅ LOD for paged documents (per-page chunk rasters when zoomed out far)
- ✅ Persistent LOD rasters: canvases reopened far out (chunks ≤ 128 px) draw stored rasters,
  named by chunk content digests, and load only chunks without one (native; not the web, not
  paged documents)
- ✅ Stored LOD rasters: reads capped and nearest-first (dropped when panned away), writes
  deferred until the view is idle, chunks with images stored once decoded

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
- ✅ Recognised handwriting syncs (`recognised_text`): Linux, Windows and web search handwriting
  Android devices read (word highlights too); edited or erased ink loses its text everywhere at
  once; Android devices reuse each other's readings
- ⬜ Handwriting recognition on Windows (WinRT ink analysis) / Linux / web
- ✅ Live cover thumbnails, ten cover colours
- ✅ Trash with restore / delete forever / empty, duplicate notebook
- ✅ Create sheet with a live cover + first-page preview, Paper gallery and Cover colours, size and paper
  colour (dialog on wide screens, tall sheet on phones); grouped template gallery
- ✅ Selection mode: favourite, move, export, trash (undo), restore, delete forever for many notebooks
- ✅ Recent row at the library root (the 8 notebooks opened lately, wherever they are filed); in
  short windows the first item of the folder strip, a menu
- ✅ Export from the library (notebook menu and selection: one file per notebook)
- ✅ Recordings seen from the library: a mic on cards, "2 recordings" in the list, search finds
  recording titles
- ✅ Cards show page count and short dates; consistent dialogs; empty states with actions
- ✅ "New…" tile in the grid

## App
- ✅ Web target (PWA): SQLite wasm + IndexedDB, blobs in IndexedDB, PDF import/render (PDFium wasm),
  export downloads, sync via CORS, one tab at a time; `--wasm` build works
- ✅ Web: persistent storage requested (Settings → Storage: status, usage / quota), own offline
  service worker (precached app shell, CanvasKit, SQLite / PDFium wasm, fonts; verified offline in
  headless Chromium), canvas reads in time-budgeted slices (a Web Worker cannot share the
  IndexedDB-backed database; see ARCHITECTURE)
- ✅ Storage overview on every platform (Settings → Storage): space by kind, the largest
  notebooks, free up copies of files the sync server holds, clear cached previews
- ⬜ Web: database in a worker (OPFS VFS, asynchronous data layer) to take all reads off the UI thread
- ✅ Scale: 1,000-notebook libraries, 500-page notebooks, a first sync of a large library and a
  years-old database stay responsive (no library-sized work before the first frame or in one
  event-loop turn; bounded memory in long sessions); benchmarks and numbers in `PERFORMANCE.md`
- ✅ Scale: decode first-sync pages off the UI thread; lighter page-overview tiles
- ✅ Smooth frames: no widget rebuilds per pan or scroll frame (canvases and paged notebooks,
  PDF layer, selection handles, zoom frame), minimap and zoom window behind repaint boundaries;
  web restores unpacked by the browser and written in 8 ms slices (the walk-through fails any
  task over 500 ms in WebAssembly builds)
- ⬜ Web (JavaScript build): CanvasKit's main-thread GL work still makes long tasks (shader
  compiles, a pixel read-back per ink tile, thumbnail and LOD raster; PERFORMANCE *Known costs*);
  the WebAssembly build has none over 200 ms once started
- ✅ Theme mode (system/light/dark)
- ✅ App shell: sidebar (tablet/desktop), drawer (phone), context menus,
  keyboard shortcuts (a grouped reference: Ctrl/⌘+/ or Settings → General), redesigned settings
- ✅ Keyboard access: roving focus (arrow keys) in every choice group (toolbar, swatches,
  segmented controls, templates, settings), context menus from the keyboard (Menu key /
  Shift+F10) on cards, folders, tabs, overview pages, styles and the page, a sane library Tab
  order, menus and popovers give focus back to their opener
- ✅ Keyboard: reorder pages with Ctrl+arrows in the overview and the page sidebar
- ✅ Settings: theme previews, a Writing section (stylus, gestures, toolbar position) with
  descriptions; everything checked at 1.3× text (see `docs/UX_AUDIT.md`)
- ✅ Redesigned editor chrome (GoodNotes-style top bar: back, pages, bookmark, title, undo/redo,
  export, focus, more menu), tool-descriptor toolbar with contextual quick controls, toolbar
  position (docked / floating, draggable), focus mode (F11 / Ctrl+.) with
  immersive system bars
- ✅ Open-notebook tabs (up to 8, each keeps its page and zoom; tab strip on tablets/desktops,
  switcher on phones; Ctrl+Tab, Ctrl+W); the workspace (tabs, split view) reopens after the app
  was killed or closed from the editor
- ✅ Editor UX round 2: toolbar in groups (≥ 40 px targets, optional tool names), one-row phone
  toolbar with a tool switcher, title left-aligned with the folder on every size, open-notebook
  transition from the cover, export options, a one-time pen side-button tip,
  empty-canvas hint, Escape closes chrome menus
- ✅ Fixed toolbar order (customising and favourite pens removed, SIMPLIFY #9, #10); quick colour
  and width slots per ink instead (in-editor search: ✅ text and PDF, see Library)
- ✅ Split view (tablets in landscape, desktops): two notebooks — or two places in one — side by
  side, resizable, each pane a full editor (tools linked); drag a lasso selection across
  to copy it; from a tab's menu or the top bar
- ✅ Presenting: F5 is focus mode (no chrome, full screen on web, Linux and Windows,
  immersive on Android) with the laser pointer; Space / ← / → turn pages
- ⬜ Presentation on a second display as a separate audience view (Android Presentation API,
  desktop multi-window once Flutter supports it)
- ✅ App identity: one icon design for all platforms (Android adaptive + themed icon), splash
  screen, edge-to-edge system bars, Linux desktop entry, Windows window placement
- ✅ CI (analyze, tests, Linux/Android/Web/Windows builds, server image) and tagged releases
  (APK, Linux tarball, Windows zip, web zip, GHCR server image)
- ✅ "Open with Len" / "Share to Len": PDFs → new notebook (or pages of the open notebook),
  images → new canvas (or onto the open page / canvas), asked when an editor is open; Android
  intents (cold + warm start), Linux command line + desktop-entry MIME types + single instance,
  Windows command line, PWA file handlers, drag and drop onto the library (desktop + web)
- ✅ Windows: Inno Setup installer (per user, file associations, uninstaller; CI + releases),
  single-instance forwarding over a named pipe, remembered window placement
- ✅ Linux: Flatpak manifest from the release tarball (release job), AppStream metadata, remembered
  window size / position / maximised state
- ✅ AppImage (release job, `--install-desktop-entry`, zsync updates); audio recording inside the
  Flatpak (the GNOME runtime's `parecord` + `ffmpeg`, checked by a script); store metadata ready:
  Flathub AppStream (screenshots, release notes, OARS), fastlane texts + phone / tablet
  screenshots for Play and F-Droid, winget manifests filled per release (docs/PACKAGING.md)
- ➖ Publishing to stores (Flathub, F-Droid, Play, winget): not planned (owner decision); releases stay on GitHub

## Sync
- ✅ Self-hosted LWW record sync
- ✅ Len files (`.len`): export / import a notebook, folder or the whole library as editable
  copies; Settings → Backup (back up library, restore into a dated folder, last backup shown);
  "Open with" on Android, Linux, Windows and the PWA; Android Auto Backup keeps the database
  only and a restored database takes a new device id
- ✅ Blob sync (content-addressed PDFs, images and audio)
- ✅ A failing sync is seen outside Settings: after 15 min a mark in the phone library's header
  and the editor's bar; after a day "Not synced since …" once
- ✅ Blob garbage collection (unreferenced blobs on device and server); oversized blobs no longer block sync
- ✅ Recovery from servers that lost history (restored backup, replaced server: `serverId`, 409,
  `server new-id`); durable server commits; errors that say what to fix (token, address, server
  too old / new, unreachable)
- ✅ Deletions racing edits on another device lose nothing: a deleted page written on elsewhere
  comes back into its notebook, a notebook deleted forever comes back into the trash with all
  its content (and blobs)
