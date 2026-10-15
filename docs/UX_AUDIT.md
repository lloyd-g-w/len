# Len — UX/UI audit

## Round 17 audit — recording a lecture (`review/round17`)

Lens: a student who records every lecture on an S Pen tablet (sometimes a
phone or the laptop) while writing, then reviews by tapping ink to hear
what was said; Notability is the reference for this flow, GoodNotes 6 the
other. Read in the code: `features/audio/` (`RecordingController` and its
start / storage parts, `RecordingParts`, the journal and recovery, the
keep-alive, `NotebookAudio`, `PlaybackController`, the audioplayers
backend, `PlaybackSession`, ink replay, the scrubber, trim and release,
the recordings list), where editors share and release a notebook
(`SharedNotebooks`, `EditorWorkspace`, focus mode in `EditorChrome`) and
the library's mic marker and recording-title search. Rendered the audio
screenshots (`editor_surfaces_screenshot_test.dart`, `e_audio_*`: phone,
tablet, large text). Nothing was run on a device. ⬜ open, ✅ fixed on
this branch.

Summary: capture is the strong part. One tap starts (tablet top bar), the
audio is written in 5-minute parts that sync while the lecture goes on, a
foreground service keeps an Android recording alive with the screen off,
a killed app offers to recover what it had, and review is Notability's
loop: ink later than the moment heard is veiled, a tap on ink plays from
just before it, bursts of writing are markers on the waveform, 0.75–2×,
lock-screen and headset controls. What breaks the lecture is moving
around: a glance at last week's notebook in another tab, or Back to the
library, ends the recording without a word (GoodNotes keeps recording
while another document is viewed), and focus mode on a tablet hides that
anything is recording. Reviewing on the laptop waits for every part of a
90-minute lecture to download, one after the other, before a sound.

| Moment | Len | Notability · GoodNotes 6 | Verdict |
|---|---|---|---|
| Start | tablet / desktop: 🎙 in the top bar (1 tap); phone: ⋯ → Record audio (2) | Notability: mic in the toolbar (1); GoodNotes: overflow menu (2) | Keep |
| First time | microphone prompt, then (Android 13+) the notification prompt; refused: "Allow microphone access…" with Settings | same prompts | Keep |
| While writing | top bar: red dot, time, level, pause, stop; phone: the same docked above the toolbar | Notability: red mic and time in the toolbar | Keep |
| … in focus mode (tablet) | the top bar fades out with it: no sign of the recording | n/a | R17-2 ✅ |
| Pause / resume | in the bar and the notification; ink while paused belongs to the resume | same | Keep |
| 5-minute parts | invisible; each synced as the lecture goes on; at most ~0.3 s gap on Linux / browsers | Notability: one file; suggests a new recording each hour | Keep (better) |
| Screen off, other app (Android) | keeps recording (foreground service, notification with Pause / Stop) | Notability (iPad) keeps; GoodNotes Android stops | Keep (better) |
| Another tab, or Back to the library | the recording stops and is saved, silently; a new one must be started | GoodNotes keeps recording while another document is viewed | R17-1 |
| Stop and name | "Saved “Recording 09:30”"; renaming is ⋯ → Rename… in the list | Notability: dated, renamed in the list | R17-4 |
| The list during a lecture | the recording being made is missing; "Record" does nothing | n/a | R17-5 |
| 90 minutes | ≈ 44 MB (AAC 64 kbit/s), streamed to files; browsers hold at most one part in memory | similar sizes | Keep |
| Review: tap ink | plays from 1.5 s before it; later ink veiled at 82 %; bursts as dots; Shift+← / → between them | Notability: hand tool, tap a word; Note Replay | Keep |
| Writing with the player open | with "tap ink to play" on, a pen stroke pans the page | Notability: writing during playback links to it | R17-6 |
| Speed, skip | 0.75–2×, ±10 s; no skip-silence | Notability: speeds, no skip-silence | Keep |
| Background playback | Android media session and lock screen, MPRIS, Media Session in browsers, headset buttons | same on iPad | Keep |
| Finding it later | mic glyph on cards, "2 recordings" in list rows, the title filter matches recording titles | Notability: audio badge | Keep |
| Share / export | ⋯ → Share… (and Save to device… on Android): one `.aac` | Notability: m4a | Keep |
| Trim, free space | non-destructive trim, Reset trim; "Free up 12 MB…" | Notability: none; GoodNotes: delete only | Keep (better) |
| On another device | plays once *every* part is downloaded, one at a time, with no word of it | iCloud: downloads first too | R17-3 |
| Delete | ⋯ → Delete… (confirm; on all devices) | same | Keep |

### Prioritised items

**R17-1 P1 · Another tab, or Back, ends the lecture's recording without a word.** ⬜
- *What:* a notebook's recorder lives as long as an editor shows it
  (`SharedNotebooks.release` disposes it, which stops and saves). Tabs show
  one editor at a time, so tapping the tab of last week's lecture to check a
  formula — or Back to the library to open it — stops the recording; no
  message says so (the editor that would show it is gone). Back in the
  lecture the mic is idle and the rest of the lecture is not recorded.
- *Fix:* a notebook that is recording stays open until the recording is
  stopped, wherever the student goes; meanwhile a small panel ("● 12:34
  Recording in “Calculus — Lecture 12”", Show, Stop) sits in the other
  editors and the library. Ink written elsewhere is not linked (as in
  GoodNotes). Effort M.

**R17-2 P1 · Focus mode hides the recording.** ✅
- *What:* on tablets and desktops the recording controls live in the top
  bar, which focus mode fades out; a 90-minute lecture written in focus mode
  shows no sign it is being recorded (or paused). Phones dock them at the
  bottom and keep them.
- *Fix:* in focus mode the controls dock at the bottom as on phones (the
  player already stays there). Effort S.
- *Done:* `AudioLayer` docks them whenever the top bar is hidden.

**R17-3 P1 · A recording from another device is silent until all of it has downloaded.** ⬜
- *What:* opening a recording fetches each missing part in turn
  (`AudioplayersPlayback.open`), then plays; for a 90-minute lecture made
  on the tablet that is 18 downloads, one after another, while the laptop's
  player sits at 0:00 with disabled buttons and nothing says why.
- *Fix:* fetch up to three parts at once and say so in the player
  ("Downloading… 40%"). Playing the first parts while the rest arrive needs
  the player to grow its source: TODO "Next". Effort S–M.

**R17-4 P2 · The name is settled after the lecture, in a menu.** ⬜
- *What:* a recording is titled "Recording 09:30" — and the list's second
  line already says "Today, 09:30" — so naming it is what makes it findable
  (the library's filter matches recording titles), but the "Saved" message
  offers nothing; it takes the list → ⋯ → Rename….
- *Fix:* the "Saved “Recording 09:30”" message has Rename. Effort S.

**R17-5 P2 · The recordings list doesn't know a lecture is being recorded.** ⬜
- *What:* opened mid-lecture (to check the last session's length), the list
  leaves the running recording out (on purpose: it is listed once finished)
  and offers "Record", which then does nothing.
- *Fix:* a first row "Recording now" with its running time (or "Paused"),
  and no Record button while recording. Effort S.

**R17-6 P2 · With the player open, the pen pans instead of writing.** ⬜
- *What:* "tap ink to play" (on by default) lays a layer over the page that
  takes every pointer: a tap seeks, a drag pans — the S Pen included, so a
  note added while listening moves the page and leaves no ink.
- *Fix:* the pen never pans there (as with "stylus only"); a pen drag says
  once "Tap ink to play is on" with Turn off. Effort S.

## Round 16 audit — a year of notes (`review/round16`)

Lens: a student a year in, with ~300 notebooks in nested folders
(Year 1 › Spring › Calculus › "Calculus — Lecture 12"), PDFs and lecture
recordings, syncing an S Pen tablet, a phone and a Linux laptop. Read in
the code: the library (`features/library/`: `LibraryController`,
`LibraryQuery`, `RecentRow`, the move dialog, trash purge), search
(`data/search/`, `features/search/`), names (`data/name_order.dart`),
backup (`features/backup/`, Settings → Backup), sync (`sync/`:
`SyncEngine`, `sync_engine_pull.dart`, `DeletionConflicts`,
`SyncController`, `SyncStatusButton`, the setup link) and where the editor
reopens (`EditorLifecycle`, `EditorViewState`). Rendered a new suite with
a year's library (`test/screenshots/year_screenshot_test.dart`: 3 top
folders, 3 terms, 9 courses, ~200 lectures, a journal a month; phone,
tablet, desktop). Nothing was run on a device or against a live server.
Paths are under `app/lib/` unless noted. ⬜ open, ✅ fixed on this branch.

Summary: the plumbing is ready for a year of notes: 300 notebooks build
only the cards on screen, search reaches titles, typed text, PDF text and
synced handwriting across every folder with the folder path on each hit,
backups stream a library of any size, and sync never silently loses a
stroke (strokes are records of their own, so a page written on two
devices offline simply holds both; a deletion racing an edit is undone).
What a year exposes is the ordering and finding of many similar things,
and how quiet the multi-device moments are: lectures sort 1, 10, 11 … 2;
"lecture 3" finds Lecture 13 and 23 first; the Recent row cuts off the
course; the laptop reopens a notebook where *it* last was, not where the
tablet just wrote; a new device sits on "Syncing…" in an empty library
until the last record lands; and a deletion another device undid is
undone without a word.

| Moment | Len | GoodNotes 6 · Notability | Verdict |
|---|---|---|---|
| A notebook from last March | 🔍 + a word or two of its title (1 tap, results across folders with their path); or ☰ → Year 1 → Spring → Calculus → scroll (4 taps) | GoodNotes: search or the folder path; Notability: subjects (one level) | Keep, after R16-2 and R16-8 |
| Sorting a course's lectures by name | A→Z by characters: Lecture 1, 10, 11 … 19, 2, 20 | both sort numbers by value (Finder order) | R16-1 |
| Title search | each term anywhere in the title: "lecture 3" → Lecture 13, 23, 3 (by date) | GoodNotes: word starts | R16-2 |
| Recent | 8 notebooks opened lately, with "Year 1 › Spring › …" under each | GoodNotes: Recents tab; Notability: none | R16-3 (caption) |
| Favourites | ★ section with a count | same | Keep |
| Move many | Select → Move… → folder tree; Undo | same | Keep |
| Nested folders, rename, colours | any depth; sidebar tree with drop targets; colour per folder | GoodNotes: same; Notability: dividers › subjects | Keep |
| Trash | 30 days, then purged on every device; Empty trash…; Undo | same (GoodNotes 30 days) | Keep |
| Space used | web only (Settings → Storage); native: per recording "N MB on this device" and Free up trimmed audio; nothing for the library | the system's per-app total (neither app breaks it down well) | R16-7 ✅ |
| Backup / restore of a big library | streamed `.len` file, "Last backup …", restore beside what's there or skip what's here, Undo | GoodNotes: zip of PDFs/.goodnotes; Notability: auto-backup to a cloud drive | Keep |
| Sync status day to day | sidebar caption "Synced 2m" / "Syncing…" / red "Sync failed"; never a dialog | an icon in GoodNotes' settings; Notability: banner on failure | Keep |
| Same page written on two devices offline | both sets of ink kept (stroke records merge); a text box edited on both: the later edit wins | GoodNotes: conflict copy of the document | Keep |
| Page or notebook deleted on one, written on another | the deletion is undone (a notebook back into the trash) — silently | GoodNotes: conflict copy | R16-6 |
| Switching devices mid-notebook | opens where this device last was (page index, zoom), or page 1 | GoodNotes: where that device was; Notability: where it was | R16-4 |
| A new device joining | QR / `len://sync` link; first sync "Syncing…" with no progress, library empty until done; files fetched as pages are shown | GoodNotes (iCloud): notebooks appear as they download | R16-5 |

### Prioritised items

**R16-1 P1 · A→Z sorts lectures 1, 10, 11 … 2.** ✅
- *What:* `NameOrder` compares folded names character by character, so
  "Calculus — Lecture 10" sorts before "Lecture 2", and folders "Week
  10" before "Week 2". A year of numbered lectures, weeks and chapters is
  out of order in every A→Z list (grid, list, sidebar, move picker).
- *Fix:* runs of digits compare by value (natural order), still
  locale-free so every device agrees; equal values by the digits' length
  ("02" after "2"). Effort S.

**R16-2 P1 · Title search matches inside words and numbers.** ✅
- *What:* `LibraryQuery.matcher` keeps a title when each term occurs
  *anywhere* in it: "lecture 3" lists Lecture 13, 23, 30 and Lecture 3,
  ordered by date, so the one meant is anywhere in the list; "cal"
  finds "Medical". Full-text search (contents) already requires word
  starts, so titles and contents disagree.
- *Fix:* each term must begin a word of the title (or recording title,
  folder name), as `SearchQuery` does for contents. Effort S.

**R16-3 P2 · The Recent row cuts off the course.** ✅
- *What:* a Recent tile's caption is the whole path, "Year 1 › Spring ›
  Calculus", ellipsised at the end on every width: the part that tells
  two "… — Lecture" tiles apart is what goes.
- *Fix:* the caption names the folder the notebook is in (the innermost);
  the whole path stays in search results and becomes the tile's tooltip.
  Effort S.

**R16-4 P1 · The laptop opens a notebook where the laptop last was.** ✅
- *What:* the page, zoom and pan are kept per notebook in this device's
  settings (`EditorLifecycle.saveView`). Write pages 14–16 of a lecture
  on the tablet, open the notebook on the laptop at home: it opens on
  page 3, where the laptop last looked a week ago (or on page 1 if it
  never opened it), and the student scrolls to find today's notes.
- *Fix:* no new sync data: when the notebook's newest ink or text was
  written on another device after this device last left the notebook
  (or it never opened it here), a paged notebook opens framed on that
  page; otherwise as kept. Effort M.

**R16-5 P1 · A new device’s first sync is a silent wait in an empty library.** ✅
- *What:* the first pull of a year (tens of thousands of records) runs
  for a minute or more with "Syncing…" and no measure of it; the
  library hears about the new notebooks only when the whole sync ends
  (`SyncController` announces `RemoteChanges` once per cycle), so the
  new tablet shows "No notebooks yet" with its create buttons meanwhile.
- *Fix:* the server's pull reply says its newest seq (`lastSeq`), so a
  pull longer than a page shows how far it is ("Syncing… 40%" in the
  sidebar and Settings → Sync); and the library and search hear about
  notebooks and folders as pages land (at most every 2 s), so the
  library fills in while the rest arrives. Effort M.

**R16-6 P2 · A deletion undone by another device says nothing.** ✅
- *What:* deleting a page on the phone while the tablet (offline) wrote
  on it brings the page back at the next sync; a notebook deleted
  forever comes back into the trash (`DeletionConflicts`). Nothing tells
  the person who deleted it, so a page "comes back from the dead" or the
  trash count rises for no reason they know.
- *Fix:* on the device that made the deletion, a calm notice once:
  "“Calculus — Lecture 4” is back in the trash: another device wrote in
  it" / "2 deleted pages of “Lab book” are back: another device wrote on
  them". Devices that didn't delete anything say nothing. Effort S–M.

**R16-8 P3 · A search from inside a folder buries that folder's notebooks.** ✅
- *What:* in Year 1 › Spring › Calculus, typing "lecture 3" searches the
  whole library (rightly: the caption says so) but lists the matches by
  date, so "Calculus — Lecture 3" sits sixth, under Project, Electronics
  and Statistics.
- *Fix:* still across every folder, but what is in the open folder (or
  below it) comes first, each part in the chosen order. Effort S.

**R16-7 P2 · Nothing says what takes the space.** ✅
- *What:* natively there is no storage view: a year of lectures recorded
  is gigabytes, and the only sizes shown are per recording in its panel.
  Synced files fetched once stay on every device for good.
- *Fix:* Settings → Storage on every platform: space by kind (notes,
  PDFs and images, recordings), the largest notebooks, and "Remove
  downloaded copies" for files the server holds (fetched again when
  shown). Effort L: TODO "Next".
- *Done:* Settings → Storage everywhere: "Space used" by kind, the
  largest notebooks (open, or at their recordings), "Free up N…" (one
  confirmation that says it can't be undone; the server is asked for
  each file first), "Clear" for cached previews. Leftover of R16-3: a
  cut title in Recent tiles and grid cards keeps its last word
  ("Electronics… 12").

Checked and sound: 300 notebooks build only the cards on screen and
reloads keep unchanged cards; the folder tree, move picker and sidebar
handle any depth and parent cycles from concurrent moves; every library
edit has Undo; the trash purges after 30 days on every device; a backup
streams a library of any size, says when it was last made, and a
restore can skip what is already here; the sync status lives in one
quiet caption and only a token the server refuses interrupts; a page
written on two devices offline keeps both sets of ink (a text box edited
on both keeps the later edit); a notebook deleted or trashed elsewhere
closes its editor with a message; the setup link and QR code carry the
server and token (Android opens `len://sync` links); files arrive lazily
as pages are shown, so a new device is usable as soon as the records are
in. Left as is: a Recent tile's title is still cut on narrow tiles when
titles share a long start ("Electronics — Lec…"; the caption now names
the course); the server and the app change together (pull pages must
carry `lastSeq`). No new settings on this branch.

## Round 15 audit — stylus craft (`review/round15`)

Lens: a demanding S Pen user on a Galaxy Tab writing for hours, who
knows GoodNotes 6 (Apple Pencil hover), Notability and Samsung Notes.
Read in the code and tests: input routing and palm rejection
(`ink/input/ink_input_controller.dart`, `ink_drawing.dart`,
`stylus_proximity.dart`, `canvas_gestures.dart`), the side button
(`stylus_buttons.dart`), hover (`handleHover`, `LiveInk`,
`render/ink_painters.dart`), the low-latency path (`WetInk*`, ARCHITECTURE
*Low-latency ink*), pen defaults (`ink/pen/pen_defaults.dart`), the paged
document's page picking (`editor/document/paged_document_view.dart`), the
zoom window, split view and hold to snap. Nothing was run on a device.
Paths are under `app/lib/` unless noted. ⬜ open, ✅ fixed on this branch.

Summary: the writing itself is at Samsung Notes' level and ahead of
GoodNotes on Android: ink is under the nib in ~5.5 ms (front-buffer
overlay armed while the pen hovers), every 240 Hz sample is kept, a pen
landing catches a glide, palms are ignored while the pen touches, hovers
or lifted < 300 ms ago, and hold to snap and scribble to erase are held
to zero false positives on real recordings. The gaps are around the
writing, where the hand and the pen meet the rest of the app: a hovering
pen says nothing about the stroke it is about to make, cursors stay on
the page after the pen leaves, a cancelled contact throws the stroke
away, and a palm is only a palm on the canvas it rests on.

| Moment | Len | GoodNotes 6 · Notability · Samsung Notes | Verdict |
|---|---|---|---|
| Pen hovering, pen tool | nothing (wet ink armed, invisible) | GoodNotes (Pencil hover): a preview of the nib, its colour and size; Samsung Notes: a hover pointer | R15-1 |
| Pen hovering, eraser | a grey ring of the eraser's size | GoodNotes: the eraser's footprint | Keep; invisible on dark paper (R15-2) |
| Pen leaves range | the eraser ring stays (Android sends no hover exit) | gone | R15-3 |
| Pen-down latency | ~5.5 ms overlay, 30 ms Flutter (INK_LAB) | similar (Samsung Notes front buffer) | Keep |
| Ink feel defaults | pen: thinning 0.25, stabiliser 0, round ends; 3 colours, 3 widths | GoodNotes ballpoint: light pressure, no stabiliser | Keep |
| Side button | held: erase (default), lasso or nothing, with every tool | Samsung Notes: same idea | Keep |
| Tool switching | one tap; quick slots; two-finger tap undo (≥ 600 ms after the pen) | same | Keep |
| Palm before the pen | the pen hovering 1–2 cm above counts; a stylus down stops a palm's pan or stroke | same | Keep |
| Palm on chrome / another pane | a palm resting on a toolbar button, the Add page footer or the other split pane taps or pans it | system palm rejection (iPadOS); Samsung Notes ignores touches while writing | R15-4 |
| Contact cancelled mid-stroke (rotation, notification shade, a system gesture, a dialog) | the stroke is thrown away | the ink written stays | R15-5 |
| Stylus edge swipe (gesture navigation) | a stroke from the screen's edge may become Back | apps exclude the writing area | R15-6 |
| Near page edges / between pages | a pen in the gap writes on the nearest page; ink is clipped to the page it began on | GoodNotes: same | Keep |
| Writing at the bottom of the screen | no auto-scroll; a finger pans | none of the three auto-scroll in continuous view | Keep (moving paper under the nib is worse) |
| Page gliding when the pen lands | the glide stops, the stroke goes to the page under the nib | same | Keep |
| Straight lines | hold 600 ms to snap; no false snaps in real writing | GoodNotes / Samsung Notes: hold | Keep |
| Small writing | zoom window (box, frame, auto-advance) | GoodNotes zoom window | Keep |
| Split view | each pane its own overlay and palm logic | n/a | R15-4 |

### Prioritised items

**R15-1 P1 · A hovering pen shows nothing.** ✅
- *What:* hovering the S Pen with the pen or highlighter gives no sign
  of what will land: which of three colours and widths is on, how big
  the nib is at this zoom. The eraser already shows its ring
  (`LiveInk.eraserCenter`). GoodNotes on a hover-capable iPad previews
  the nib; Samsung's hover pointer is a fixed dot.
- *Fix:* while a stylus hovers with an ink tool (the side button not
  routing elsewhere), a dot of the ink's colour and its medium-pressure
  width at the current zoom, at half opacity so it never reads as ink
  (the highlighter at its own lower opacity); gone at pen-down, on a
  finger, on exit. No setting. Effort S.

**R15-2 P2 · The eraser ring vanishes on dark paper.** ✅
- *What:* the ring is a 1-px `0x99000000` line on a `0x22000000` fill
  (`LiveInkPainter`); on the Dark paper preset (`0xFF202226`) neither
  shows.
- *Fix:* a two-tone ring (a dark line inside a light one) that shows on
  any paper and ink. Effort S.

**R15-3 P2 · Hover cursors stay on the page after the pen leaves.** ✅
- *What:* Android reports no hover exit when the S Pen leaves range
  (noted in `_touchDown`), so the eraser ring stays where the pen was
  until a finger touches; a pen preview (R15-1) would sit there like a
  blot of ink.
- *Fix:* a stylus's hover cursors expire 400 ms after its last event (a
  hovering S Pen streams events, so they never blink while it is near);
  500 ms in the end (`LiveInk.stylusHoverTimeout`).
  Effort S.

**R15-4 P2 · A palm is a palm only on the canvas it rests on.** ✅
- *What:* the palm rules live in each `InkInputController`. A palm
  resting on a toolbar button, the page indicator or the Add page footer
  while the pen writes taps it when it lifts (taps have no time limit);
  in split view a palm on the other pane pans it (that pane never saw
  the pen).
- *Fix:* an app-wide `PalmGuard` (a global pointer route, as
  `PointerActivity`): touches already down when a stylus touches, and
  touches landing while it touches, are cancelled wherever they are
  (`GestureBinding.cancelPointer`); and every canvas treats a touch as
  a palm while the pen is near *any* canvas. A finger tapping chrome
  while the pen only hovers still works (the other hand on Undo).
  Effort M.

**R15-5 P2 · A cancelled pen stroke is lost.** ✅
- *What:* `handleCancel` drops the drawing contact (`InkDrawing.cancel`).
  Android cancels the stream when the window loses focus mid-stroke (a
  notification, a dialog, rotation, a system gesture): the line just
  written disappears.
- *Fix:* a stylus's ink contact that is cancelled is committed as
  written (no bounce check: there was no lift) but erases nothing: a
  scribble cancelled while dimming ink is dropped, nothing goes without
  a lift. Erasing and tools still cancel, fingers still drop their
  stroke (a pinch or palm). Effort S.

**R15-6 P3 · A stroke from the screen's edge can become Back.** ⬜
- *What:* with gesture navigation, Android may take a stylus swipe from
  the left or right edge as Back (and cancel the stroke, now kept by
  R15-5). Writing zoomed in to the page's edge starts there.
- *Fix:* system gesture exclusion rects for the canvas while a stylus
  is near (Android caps them at 200 dp per edge); needs the tablet to
  see whether One UI routes stylus edge swipes at all. Effort M with
  device checks: TODO "Next".

Checked and sound: the side button with every tool (erase or lasso win
over the tool; "nothing" writes); the eraser end; the overlay armed on
hover, skipped for any non-ink down; palms while hovering (300 ms) and
for gestures (600 ms); a stylus down cancelling a palm's stroke and pan;
the glide stopping under the nib; the gap between pages; hold to snap and
scribble's zero-false-positive corpora; the zoom window's palm handover
(`stylusElsewhere`). No new settings on this branch.

## Round 14 audit — first run and empty states (`review/round14`)

Lens: a brand-new user on an Android phone (finger), an Android tablet
with an S Pen, a Linux desktop with a mouse, and the web (a PWA on its
first visit, offline later). Every first-run path was read in the code
(`main.dart`, `web/index.html`, `web/sw.js`, the Android launch theme,
`library/` and its notices, `new_notebook_sheet.dart`, the editor's
tips, stylus detection and add-page footer, `search/`, `settings/`,
`documents/overview/`, `editor/outline/`, `audio/ui/recordings_sheet.dart`,
`documents/templates/`), and a new screenshot suite,
`test/screenshots/first_run_screenshot_test.dart`, walks a fresh
database on a phone, a tablet and a desktop: the empty library, the
new-notebook form, the first page, the overview's empty Bookmarked and
Outline, ⋯, a search with no matches, empty Favourites and Trash. The
settings, sync-form, empty-search, empty-folder and empty-canvas shots of
the other suites were rendered too; all viewed downscaled. Paths are
under `app/lib/` unless noted. ⬜ open, ✅ fixed on this branch.

Summary: day one is calm. The library opens on three covers, "No
notebooks yet", one Ink button (New notebook) and two quiet links
(Import PDF…, Set up sync…); a first notebook is one tap on Create
(today's date as title, college ruled, A4, Ink blue), and the page opens
with the pen up. The finger / stylus switch is automatic and said once.
The gaps are small: the web greets a first visit with a warning about
data it doesn't have yet, two empty states explain but offer nothing to
do, a search that can't see handwriting says only "No matches", and a
few strings are touch words under a mouse.

### Day-one notices (count)

| Platform | Before the first notebook | First strokes | Verdict |
|---|---|---|---|
| Android phone, finger | 0 (sidebar status "Only on this device", in the drawer) | 0; "Hold for a template" under Add page | Keep |
| Android tablet, S Pen | 0 | 1 snack: "Stylus detected: fingers now pan and zoom" (Keep finger drawing); the side-button tip waits for a later opening, ≥ 10 min apart, ≥ 60 s after a snack | Keep |
| Linux, mouse | 0 | 0; "Hold for a template" (a touch word, R14-6) | R14-6 |
| Web, first visit | **1 notice strip**: "This browser may clear your notebooks" over the empty library | 0 | R14-1 |
| Web, private window | 1: "Files you add won't be kept…" | 0 | Keep (true and costly) |

### Walk-through

| Step | What the user meets | Verdict |
|---|---|---|
| Splash | Android 12+ system splash (surface + icon) until the first frame; web: the logo pulsing on the surface colour | Keep; the web pulse ignores reduced motion (R14-8) |
| Empty library | covers, title, one line, New notebook, Import PDF… · Set up sync… | Keep |
| First notebook | the form starts on what it makes; "Styles" appears only after one is saved; "Save as style…" at the end | Keep |
| First page / canvas | pen selected; canvas: "Draw anywhere" in words for the input | Keep |
| Finger vs stylus | the finger draws until a stylus touches; then one snack with its way back; ⋯ → Draw with finger | Keep |
| First PDF import | from the empty state; the imported notebook opens | Keep |
| First search, nothing found | library: "No results" + Clear search; editor: "No matches", silent about handwriting it can't search here | R14-2 |
| First sync setup | Server URL, Access token, Connect; URL errors on the field, token errors loose under the fields | R14-7; what a "Len server" is: R14-9 |
| First export | Export… works on a blank page; an empty canvas says "Nothing to export yet" | Keep |
| Settings at first glance | five sections, each Writing switch explained in one line, "Nothing to back up yet" | Keep |
| Empty Trash, folder, search | glyph, title, one line; a folder offers New notebook, a search Clear search | Keep |
| Empty Favourites | says what, not how | R14-4 |
| Empty Bookmarked | explains, nothing to tap (the Outline beside it offers "Add page 1 to outline"); smaller type than the other empty views | R14-3 |
| Empty Outline | two sentences; "Add pages" reads as making new pages | R14-5 |
| Empty Recordings | reachable only by deleting the last one | Keep |
| My templates, Styles | need no empty state: My templates ends in Import…, Styles hide until the first | Keep |

### Prioritised items

**R14-1 P2 · The web warns about losing notebooks before there are any.** ✅
- *What:* on a first visit (sync off, storage not yet persistent, which
  is most browsers until Len is installed or used a while)
  `LibraryNotices` puts "This browser may clear your notebooks" with
  Keep data above "No notebooks yet". It is the only notice on day one,
  and it is about nothing: there is no data, `main.dart` already asks
  the browser to keep it, and the empty state offers Set up sync….
- *Fix:* the notice waits for the first notebook (as "Your notes are
  only on this device" waits a day). Effort S.

**R14-2 P2 · "No matches" when handwriting isn't searched here.** ✅
- *What:* on Linux and the web nothing recognises handwriting (only
  what Android synced is found); on Android, Search handwriting may be
  off. A new user writes "hello", searches for it and gets "No matches"
  (the editor) or "No results" (the library): a dead end that reads as
  a bug.
- *Fix:* with no matches only, one quiet line saying why: "Handwriting is
  searched once read on Android" (no recogniser here) or "Handwriting
  search is off in Settings" (`features/search/handwriting_note.dart`,
  under the editor's "No matches" and the library's "No results"). Effort S.

**R14-3 P2 · Empty Bookmarked offers nothing to do.** ✅
- *What:* `NoBookmarks` says "Bookmark pages from their ··· menu"; the
  Outline filter beside it offers "Add page 1 to outline". Its title is
  `titleMedium` with tighter gaps, unlike every other empty view.
- *Fix:* a quiet "Bookmark page N" (the page on screen), as the
  Outline's; one shared `EmptyState` layout for the library's and the
  overview's empty views. Effort S.

**R14-4 P3 · Empty Favourites says what, not how.** ✅ "Add notebooks
you use often to favourites, and find them here" → "Add notebooks to
favourites from their ··· menu to find them here" (the bookmarks'
phrasing). Effort S.

**R14-5 P3 · Empty Outline's copy.** ✅ "Add pages to build a table of
contents. Entries can be nested." reads as "make new pages", in two
sentences over a button that says it all. → "Add the pages that start a
topic to build a table of contents" (nesting is in each entry's menu).
Effort S.

**R14-6 P3 · "Hold for a template" under a mouse.** ✅ The add-page
footer's caption is a touch word; with a pointer the gesture is a right
click (the empty canvas already words its hint by input). Effort S.

**R14-7 P3 · Token errors sit apart from the token field.** ✅ "Enter
the access token" and "The server didn't accept the access token" are a
red line under both fields, and stay while the user retypes. Token
errors go on the token field, as URL errors go on the URL field; typing
clears them. Connection errors stay under the fields. Effort S.

**R14-8 P3 · The web splash pulses under reduced motion.** ✅
`web/index.html` animates the logo always; `prefers-reduced-motion`
stills it. Effort S.

**R14-9 P3 · "Your own Len server", with no way to learn what that is.**
✅ (lead: link to the server README) A "How to run a server" link beside Connect, while
sync is not set up, opens `server/README.md` on GitHub.
 A first-time user who taps Set up sync… meets two fields and no
pointer to the server or how to run it. Needs a public page (a project
site or README) to link to: an owner decision, listed in TODO "Next".
Effort M.

Checked and sound: the Android launch theme and system splash; the
default notebook (today's date, college ruled, white, A4 portrait, Ink
blue) and canvas; the stylus switch and its one snack; the tips budget
(one per opening, ten minutes apart, never near a snack bar, never while
writing); the "Draw anywhere" words by input; the phone's empty library
without a floating button (the button is in the middle); the empty
folder's New notebook; Clear search; "Nothing to back up yet"; the sync
URL's validation; an imported PDF opening at once; the service worker's
offline shell. No new settings on this branch.

## Round 13 audit — the daily loop (`review/round13`)

Lens: a stylus note-taker who knows GoodNotes 6 and Notability, on an
Android tablet and a phone, doing today's lecture: open the app, find
yesterday's notebook, write a page with pen and highlighter, erase, fix
with the lasso, draw a shape, paste a slide screenshot, add a text box,
search for a word, export the page. Each step's code was read
(`library/`, `editor/editor_gestures.dart`, `editor/images/`,
`ink/tools/`, `ink/input/`, `documents/export/`) and the library,
editor, editor surfaces, flows, toolbar and export screenshot suites were
rendered (all passed) and viewed downscaled. Paths are under `app/lib/`
unless noted. ⬜ open, ✅ fixed on this branch.

Summary: the loop is quick and calm. The app reopens where it was left
(tabs and the page, R7-7), yesterday's notebook is first in Recent and
its card says "Yesterday", tools are one tap on tablets and the phone's
second slot is the last tool used, the highlighter sits under the ink,
search highlights in place, and exporting the current page is ⋯ →
Export… → Current page → Share, as GoodNotes' four. The friction is all
in one place: **getting something onto the page that wasn't written
there** (a pasted screenshot, a pasted text, a text box from a long
press). Each of those quietly swaps the user's pen for another tool, so
the next stroke draws a lasso or opens a text box; and a long press can
only paste what was copied *inside* Len, so a tablet with no keyboard
can't paste a screenshot at all. GoodNotes and Notability keep the pen
and paste from the system clipboard.

| Step | Taps (tablet / phone) | vs GoodNotes 6 · Notability | Verdict |
|---|---|---|---|
| Open, find yesterday's notebook | 1 (Recent) / 1 | same; Len reopens the last notebook itself | Keep |
| Pen ↔ highlighter ↔ eraser | 1 / 1 (second slot) or 2 (▾) | same; Len's side button erases | Keep |
| Lasso, move, back to the pen | 2 / 2 | same | Keep |
| Shape (tool or hold to snap) | 1 / 2 | same | Keep |
| Paste a screenshot (no keyboard) | **impossible** (long press offers only Len's clipboard) | long press → Paste | R13-2 |
| …then write on | **3** (tap away, the stroke lassoes: pick the pen) | 1 (tap away) | R13-1 |
| Text box from a long press, then write | **3** (the text tool stays: the stroke opens a box) | 1 | R13-3 |
| Search a word | 2 + typing / 2 + typing | same | Keep |
| Export the current page | 4 / 4 | 3–4 | Keep |

### Prioritised items

**R13-1 P1 · Inserting or pasting swaps the pen for the lasso.** ✅
- *What:* an image from Insert ⊕, the camera, a drop or Ctrl+V, pasted
  text and pasted ink all set `tools.tool = EditorTool.lasso`
  (`editor/images/editor_images.dart` `insertBytes`,
  `ink/tools/content_tools.dart` `pasteText` / `pasteAtCentre`,
  `editor/editor_gestures.dart` Paste here). After placing the slide the
  user taps away and writes: the stroke draws a lasso. They must notice
  and pick the pen again (the phone's bar shows the lasso, screenshot
  `e_image_selected_phone`).
- *Why:* GoodNotes and Notability select what was inserted and keep the
  tool. Len already has the mechanism: a selection made with the side
  button stays live under the pen (`ContentTools.toolAt`: pressing on it
  moves it, pressing elsewhere drops it and writes).
- *Fix:* inserting and pasting keep the tool and select what arrived
  (a live selection, as the side button's); the tap that drops a live
  selection leaves no dot (`ink/input/ink_drawing.dart`), which also
  fixes tapping away from a side-button selection. The lasso's own
  Paste keeps the lasso.
- Effort S.

**R13-2 P1 · Long press → Paste here only knows Len's own clipboard.** ✅
- *What:* `canvasActions` offers "Paste here" only when the in-app ink
  clipboard has something; the system clipboard (a screenshot, an image
  copied in the browser, a paragraph from an email) is reached only by
  Ctrl+V (`EditorImages.paste`). On a tablet without a keyboard there
  is no way to paste an image from another app.
- *Fix:* "Paste here" is always offered and pastes what Ctrl+V would
  (a newer system image, then system text, then Len's clipboard) at the
  press; "Nothing to paste" when empty. Reading the clipboard only on the
  tap keeps Android's "pasted from your clipboard" notice to real pastes.
  The row hides when both clipboards are empty: the vendored
  `pasteboard`'s `peek` asks Android's clip description (no read, no
  notice), GTK's targets and Windows' formats (✅ feat/clipboard-peek).
- Effort S.

**R13-3 P2 · "Add text here" leaves the text tool on.** ✅
- *What:* the long-press row switches to the text tool and starts a
  box; when the box is done the text tool stays, so the next pen stroke
  starts another box. "Edit text" from the lasso menu already gives the
  previous tool back (`ContentTools.editText`, `_returnTo`).
- *Fix:* the long-press box returns to the tool used before when its
  edit ends, as Edit text does (`ContentTools.addTextAt`).
- Effort S.

**R13-4 P3 · Lasso Copy doesn't reach other apps.** ✅ Copying a
selection fills Len's own clipboard only; GoodNotes and Notability put
an image of it on the system clipboard, so a diagram can be pasted into
a chat or an e-mail. Needs a selection render to PNG and a clipboard
image write on every platform (Linux and the web differ). Effort M–L:
listed in TODO "Next". Done: Copy and Cut also put a transparent PNG of
the selection (and the text of text boxes alone) on the system clipboard;
pasting back in Len still gives ink (ARCHITECTURE, Lasso).

Checked and sound: the Recent row and "Yesterday" captions; the
reopened workspace and page; the phone's second slot (last tool used);
eraser defaults (whole strokes, 12); the text tool's tap outside ends a
box before starting another; the search slip's "1 of 3" and result list;
the export sheet's Current page / All pages / Page range (no range for a
single page). No new settings, rows or buttons on this branch.

## Round 12 audit — after the owner's list (`review/round12`)

Lens: round 9's question again, "is Len still minimal?", after a day that
added shape fill, the zoom window, document scan, keyboard roving focus and
context-menu keys, notebook styles, the canvas minimap, lasso options, the
laser's "When I stop", the highlighter's Feel options, smoother mouse ink
and scribble tuning (`git log 687a5097..main`). Every setting, menu row,
popover row and shortcut those added was listed from the code and judged
for need, discoverability, naming, one home and consistency (round 9's
copy rules and glossary). The toolbar, editor surfaces 3 (zoom window,
minimap), notebook styles, app surfaces 3 and flows screenshot suites were
rendered and viewed. Paths are under `app/lib/` unless noted. ⬜ open,
✅ fixed on this branch.

Summary: the day added a lot of capability and almost no chrome. Settings
gained **no** rows; the toolbar gained no buttons; every new option lives
in the popover or menu of the thing it changes. The drift is small and in
four places: a preference nobody will find (the minimap's "Keep in focus
mode"), a tip that lies once the lasso is a rectangle, the new-notebook
sheet greeting first-timers with "Styles" before anything else, and a few
names that collide with older ones (the lasso's "Shape" heading, the
style menu's bookmark glyph). ⋯ → View is now 9 rows in a paged notebook,
past round 9's 8: kept, each row is a real view choice.

### Inventory (added today)

Counts for a tablet, paged notebook unless noted.

| # | Item | Home(s) | Needed · discoverable · named · one home | Verdict | Effort |
|---|---|---|---|---|---|
| **Editor menus and shortcuts** | | | | | |
| 1 | ⋯ → View → Zoom window (switch), M | View, keys | yes (GoodNotes parity) · yes · yes · yes | Keep | – |
| 2 | ⋯ → View → Minimap (switch, canvases), Shift+M | View, keys | owner's ask · yes · yes · yes (not also in the zoom pill: View holds every overlay toggle) | Keep | – |
| 3 | M and Shift+M: two overlays on one letter | keys, shortcut sheet | both listed in the sheet | Keep | – |
| 4 | ⋯ → View length: 2 flows + 3 fits + 2 toolbar + zoom window + focus = 9 | View | each a real choice, radio groups read well | Keep (no more rows: the next toggle needs a merge) | – |
| 5 | Menu key / Shift+F10 open the focused item's menu | everywhere a long press opens one | yes · **not in the shortcut sheet** | Keep; list it (R12-3) | S |
| **Zoom window** | | | | | |
| 6 | Box rail: ✕, ⋯, ↵ Next line; grip to resize; frame tab | the box | yes · yes · yes | Keep | – |
| 7 | Box ⋯: Left-handed ("Box at the top"), Automatic height (once dragged) | the box | yes · yes · a check where ⋯'s on/off rows are switches; popup menus (`MenuRow`) mark with checks everywhere (library View, text menus) | Keep | – |
| **Minimap** | | | | | |
| 8 | Map: tap to glide, drag, pinch / scroll to zoom; fades while writing | canvas corner | yes · yes · – | Keep | – |
| 9 | Map menu: **Keep in focus mode** (switch), Hide minimap | long press / right-click on the map | rarely · hidden in a long-press menu · a switch hand-built in a `MenuItemButton`; focus mode is "no chrome" and the map is chrome | Remove the pin (R12-1) | S |
| **Tool popovers** | | | | | |
| 10 | Lasso: **Shape** (Freehand / Rectangle) | lasso popover | owner's ask · yes · the heading reads as the Shapes tool; the laser's Dot / Trail has none | Rename: drop the heading (R12-4) | S |
| 11 | Lasso: Select (Touching / Mostly / Whole) + caption | lasso popover | owner's ask · yes · yes ("Whole" as the eraser's "Whole stroke") | Keep | – |
| 12 | Lasso: Items (Ink, Highlighter, Text, Images) | lasso popover | owner's ask · yes · yes (shapes are ink, links go with images: said in code, not needed in UI) | Keep | – |
| 13 | Lasso tip "Circle ink, text or images…" | first lasso pick | **wrong with the Rectangle lasso** | Rename by shape (R12-2) | S |
| 14 | Laser: Fade (Each stroke / When I stop), "Trail lasts" or "Fades after" | laser popover (Trail only) | owner's ask · yes · "When I stop" is first person, as "My templates" | Keep (two stored durations, one slider shown) | – |
| 15 | Highlighter "Opacity and feel": + Pressure sensitivity (default Off), Ends (Flat / Round) | highlighter popover, collapsed | owner's ask (the pen's engine, explained by the same controls) · collapsed · yes | Keep | – |
| 16 | Shape fill (None, three tints, solid), dimmed for lines / arrows | Shapes popover, lasso Style | yes · yes · yes | Keep; the Shapes popover's missing Reset is R12-9 (fixed) | – |
| 17 | Smoother mouse ink, scribble tuning | – | no knobs: good | Keep | – |
| 18 | Roving focus in every choice group | – | no visible cost | Keep | – |
| **Insert and library** | | | | | |
| 19 | Insert ⊕: Scan document… (paged) | Insert ⊕ | yes · yes · the same name as the library's; mirrors Import PDF… / Pages from PDF… | Keep | – |
| 20 | Library ⊕▾ Scan document…; phone sheet link | library | yes · yes · yes | Keep | – |
| 21 | Scan screen: Take photo / Choose photos…, Rotate, Whole photo, Retake (Replace… without a camera), Remove, Colour / Greyscale / B&W, Add page, Create notebook / Insert, Discard… | scan screen | yes · yes · yes | Keep | – |
| **New-notebook sheet** | | | | | |
| 22 | **Styles** row (chips) + "Save as style…" chip, right under Title | sheet | yes · yes · **shown to a first-timer with no styles: a "Styles" heading over a lone "Save as style…" before Notebook / Canvas** | Merge: Styles row only once a style exists; "Save as style…" under the form, its one home (R12-5) | S |
| 23 | Style menu: Default for new notebooks (✓), Rename…, Delete… | chip: tap again, long press, right-click, Menu key | yes · yes · its glyph is the page **bookmark** | Rename the glyph (R12-6) | S |
| 24 | The sheet starts from the default style, else the last notebook made | sheet | yes · invisible (good) · – | Keep | – |
| 25 | Phone sheet foot: Import PDF…, Import Len file…, Scan document… (two lines) | phone sheet | yes on phones · yes · – | Keep (quiet links, below Create) | – |

Remembered, not settings: zoom box at top, its height and frame per
notebook, minimap on / off, lasso / laser / highlighter options, the last
notebook choice. Settings itself: unchanged (8 preferences, as round 9).

### Prioritised items

**R12-1 P2 · The minimap's "Keep in focus mode" is a preference nobody
will find.** ✅
- *What:* a switch inside the map's long-press menu
  (`editor/canvas/minimap_menu.dart`), stored as `minimap_in_focus`.
- *Why:* focus mode means "no chrome"; the map is chrome and already
  fades while writing. One more remembered state, and the switch is a
  hand-built `AppSwitch` in a `MenuItemButton` (CONVENTIONS: `MenuRow`).
- *Fix:* remove it: the map hides in focus mode, its menu keeps "Hide
  minimap". Paths: `editor/canvas/minimap_menu.dart`,
  `canvas_minimap.dart`, `editor/editor_layers.dart`,
  `data/app_preferences.dart`, `data/settings_repository.dart`.
- Effort S.

**R12-2 P2 · The lasso tip says "Circle…" when the lasso draws
rectangles.** ✅
- *What:* `tipMessage` (`editor/chrome/tip_message.dart`) predates the
  lasso's Shape option; its enum doc still says "it has no options".
- *Fix:* phrase it by `LassoConfig.shape`: "Drag a box around ink, text
  or images to select them" for the rectangle.
- Effort S.

**R12-3 P3 · The Menu key and Shift+F10 are missing from the shortcut
sheet.** ✅ They work on cards, folders, tabs, overview pages, styles and
the page (`ui/context_menu_keys.dart`), but Ctrl+/ doesn't say so. *Fix:*
"Context menu: Menu key or Shift+F10" in General
(`settings/keyboard_shortcuts.dart`). Effort S.

**R12-4 P3 · The lasso popover's "Shape" heading.** ✅ It reads as the
Shapes tool (the next tool in the bar), and the laser's Dot / Trail, the
same kind of mode switch with glyphs, has no heading. *Fix:* drop it
(`editor/tools/lasso_options_panel.dart`; golden `lasso_options.png`).
Effort S.

**R12-5 P2 · The new-notebook sheet opens with "Styles" for a user who
has none.** ✅
- *What:* `_styleSection` (`library/new_notebook_sheet.dart`) shows the
  heading and a lone "+ Save as style…" chip whenever the form can be
  saved, i.e. always for a new user, between Title and Notebook / Canvas.
- *Why:* the second thing a first-time user reads is about saving
  presets, before choosing what to make.
- *Fix:* the Styles row shows only once a style exists and lists only
  styles; "Save as style…" moves under the form (after Page size), a
  quiet link as the sheet's import links, its one home: pick a style at
  the top, save one at the end.
- Effort S.

**R12-6 P3 · The style menu's "Default for new notebooks" wears the
page bookmark glyph.** ✅ `Symbols.bookmark_sharp` means "Bookmark page"
in the page menu. *Fix:* a push pin (`library/new_notebook/style_actions.dart`).
Effort S.

**✅ R12-7 P3 · ⋯ → View is at 9 rows.** Keep; note for the next toggle:
merge before adding (e.g. the two toolbar radios into one "Floating
toolbar" switch). *Done:* 7 rows (paged): the zoom radios (Fit page,
Fit width, Automatic zoom), then switches only: "One page at a time"
(was Scroll pages / One page at a time), "Floating toolbar" (was
Toolbar docked / Toolbar floating), Zoom window, (Minimap on a canvas),
and Focus mode (`chrome/editor_more_menu.dart`).

**R12-8 P3 · On/off rows in menus: switches in ⋯, checks in popup
menus.** Keep: `MenuRow` marks state with a check everywhere (library
View, text menus, playback speed, the zoom box's Left-handed); ⋯ uses
`AppSwitch` rows. Consistent per menu kind.

**R12-9 P2 · The Shapes popover has no Reset** (every other tool
popover has one) **and its caption runs to two lines.** ✅ The header
has the shared Reset (rectangle, no fill; Undo after), and the caption
is two short lines that fit the 320-dp popover: "Drag to draw, tap a
shape to edit it" and "Hold the pen still to snap (Settings → Writing)"
(Shift's line only with a keyboard). The pen's colour and size need no
line: the bar's dots and sizes sit beside the tool. Paths:
`editor/tools/shape_options_panel.dart`, `ink/tool_settings.dart`
(`defaultShape`, `defaultShapeFill`); `pen_panels_test` checks Reset and
that no caption line wraps.

Checked and sound: no new Settings rows; no new toolbar buttons; every
new option sits in the popover or menu of the thing it changes; new
strings follow the copy rules (`copy_rules_test`); "Scan document…" is
one name in all three homes; the zoom window and minimap toggles share
View with the other overlays.


## Design polish round 11 (`design/polish-r11`)

Screenshot review against DESIGN.md (library, app surfaces, editor
surfaces 1–4, toolbar, overview, flows, notebook styles, minimap, lasso and
laser options); fixes are token and consistency work, no new features.

- Page orientation in the template picker is a pair of chips like the
  formats above it (one kind of control for the page size).
- Library notices sit on the covers' margins with the ✕ on the title line
  and actions on its edge; the canvas ∞ badge shows on plain covers too;
  Recent tiles always take two lines, so their titles share a baseline
  (top-level notebooks keep an empty caption line, not "Library": R8-10).
- The library header's caption wraps (large text on a phone cut the
  Trash's "deleted after 30 days").
- One weight for the current row's label (`AppTheme.currentWeight`): Move,
  the notebook picker and the tab switcher were semibold, the sidebar,
  outline and overview bold.
- The tab switcher's ✕ glyphs sit on the content edge, mirroring the
  notebook icons (they were 20 dp further in).
- The focus ring's gap and width come from tokens (`Gaps.xxs`,
  `Hairline.rule`).
- Menu and bar glyph sizes from `Glyphs` (sidebar chevron, overview
  filters, search hit icons, link picker, text heading menu).
- The unused `BarDivider` is gone; the text format bar's divider uses
  tokens.
- Notebook style chips are as high as the page-size chips and segmented
  buttons beside them (`EvenChoices.height`, 40; they were 48 on touch).
- "Other readings" in Convert to text is a `SectionLabel` like every other
  group heading (it was caption text).
- One preview height for ink and laser option panels
  (`PreviewCard.defaultHeight`).
- `Palette.cropShade` shades what image crop and scan corners cut away
  (was one literal in each); the crop frame and guides use `Hairline`.
- Screenshots of keyboard focus and a golden for the template picker were
  added.

Looked at and left, then fixed on `fix/r12-leftovers`:

- ✅ The minimap's menu opened at the press point (a context menu, so on a
  phone it could cover the bottom bar). It still opens where you press but
  keeps above and left of the map's far corner (`MinimapMenu.clearOf`, as
  `MenuEdgeMargin.keepClear` strips), so it moves above the map rather
  than over the chrome below it.
- ✅ The recordings list's ⋯ sat at the ListTile's padding, 22 dp in.
  Its glyph now mirrors the leading play glyph (8 dp in, as the tab
  switcher's ✕ mirrors the notebook icons), the button's padding hanging
  into the popover's margin (`HitOverhang`).
- ✅ A sheet header's ✕ centred on title plus subtitle. The title's first
  line and the ✕ now share one band (`SheetHeader`), so the ✕ sits on the
  title line and neither moves when a subtitle is added or the title
  wraps (`sheet_header_test`; goldens `template_picker*.png`).
- ✅ The document scan screens had no screenshot review
  (`scan_screenshot_test`, `s_scan_*`, viewed light and dark, phone and
  tablet). Against DESIGN.md: the strip's + was a bare glyph where Add
  page is a page-sized Pencil outline with an Ink + everywhere else (the
  overview, the library's New tile), now one on the thumbnails' line;
  Remove (no undo) is in the error colour like every destructive command;
  the thumbnails were 68 dp, not `thumbHeight` 72 (their ring's width was
  counted twice), so they now match the + beside them. The rest is on
  design: Desk around the photo, Board foot with a hairline, ruling-blue
  handles as image crop's, Ink primary, segmented look.

## Round 10 audit — a real week of notes (`review/round10`)

Lens: a first-time stylus user on an Android tablet and on a phone, and a
keyboard + mouse user on desktop, doing a real week of notes. Walked: the
first five minutes (first launch, empty library, New notebook, first
strokes, tools), daily flows (find a notebook, continue writing, add pages,
lasso, text, images, PDF annotation, export, sync setup) and failure paths
(offline, bad server, wrong token, cancel mid-import, damaged files). The
library, flows and editor screenshot suites were rendered (all passed) and
a sample of ~40 images was viewed; every flow's code was read.

Summary: the screens are calm and consistent; the round found almost no
visual problems. The bugs are in **keyboard routing** (the editor's
shortcuts eat editing keys in the in-notebook search field, and Ctrl+Z
there undoes ink), **state that goes stale** (library search text after
opening a folder, the device-only notice after a backup, the Back up tile
after a restore), **races in sync setup** (Cancel during a test still saves)
and **failure copy** (every PDF failure blamed on the file). Paths are under
`app/lib/` unless noted. ⬜ open, ✅ fixed on this branch.

### Prioritised items

**R10-1 P0 (desktop) · Editing keys don't work in the editor's search
field; Ctrl+Z there undoes ink.** ✅
- *What:* the editor's `CallbackShortcuts` sit above the search bar
  (`editor_layers.dart`). A matching binding consumes the key even when
  `unlessTyping` skips the action, so Backspace, Delete, arrows, Home / End
  and Ctrl+A / C / X / V never reach the field; Ctrl+Z / Ctrl+Y aren't
  wrapped at all and undo page ink out of sight. Text boxes escape it with
  `DefaultTextEditingShortcuts` (`tools/text_box_editor.dart:153`); the
  search field doesn't.
- *Fix:* wrap the search slip in `DefaultTextEditingShortcuts`; widget test
  sending real key events (Backspace, ←, Ctrl+Z).
- Paths: `search/editor/editor_search_bar.dart`. Effort S.

**R10-2 P1 · Cancelling sync setup during the connection test still saves
it, with the old token.** ✅
- *What:* `_testAndSave` reads `_token.text` again after `await test(…)`;
  Cancel stays enabled during the test (up to 30 s on an unreachable host)
  and puts the old token back, so a successful test then saves the new URL
  with the old token. Typing during the test saves an untested token.
- *Fix:* read URL and token into locals before the await; Cancel during
  the test abandons it (no save).
- Paths: `settings/sync_settings.dart:144-182`. Effort S.

**R10-3 P1 · Opening a folder clears the search but leaves the old text in
the field.** ✅
- *What:* `LibraryController.openFolder` sets the query to '' but the
  screen's search controller keeps "maths"; the next letter searches
  "mathsx".
- *Fix:* the screen clears its field when the controller's query empties.
- Paths: `library/library_controller.dart:186`, `library/library_screen.dart`.
  Effort S.

**R10-4 P1 · Ctrl+F does nothing in the library when the search field
isn't on screen** (desktop windows under ~900 px, empty views). ✅
- *Fix:* Ctrl+F opens the search (`_openSearch`) and then focuses it.
- Paths: `library/library_screen_keys.dart`, `library/library_header.dart`.
  Effort S.

**R10-5 P1 · New notebook raises the soft keyboard on an Android tablet,
and the default title shows on tablets only.** ✅
- *What:* `autofocus: wide` focuses the title in the dialog form (landscape
  tablets included): the keyboard covers half the dialog for a stylus user
  who wants to pick paper and write. The field's hint (the default title,
  "October 14") only shows while focused, so phones never see which title
  an empty field gives, and on desktop it reads like typed text.
- *Fix:* autofocus only with a keyboard (`!Targets.touchFirst`); always
  float the label so the hint (default title) shows on every form factor.
- Paths: `library/new_notebook_sheet.dart:178-184`. Effort S.

**R10-6 P1 · "Set up sync…" in the empty library opens Settings at the
top.** ✅ A first-time user lands on Theme and must scroll four sections.
Pass `showSync: true`. Paths: `library/library_content.dart:159`. Effort S.

**R10-7 P1 · With the token rejected, Settings → Sync leads with "Sync
now".** ✅
- *What:* the paused-for-auth state (screenshot `f_sync_rejected_*`)
  offers Sync now (fails again), Change…, Set up another device… (shares
  the rejected token) and Turn off sync…. The one useful action is Change….
- *Fix:* while `waitsForSettings`, Change… becomes the outlined lead
  action and Sync now / Set up another device… are hidden.
- Paths: `settings/sync_settings_views.dart:39-58`. Effort S.

**R10-8 P1 · Every PDF import failure says the file "may be damaged, or
not a PDF".** ✅
- *What:* errors from storing the file (disk full, lost content-URI
  permission, browser quota) go through `pdfOpenFailure` too; the user
  retries a good file. No Details action, unlike Len import.
- *Fix:* tell storage failures apart ("Couldn’t copy “x”: …") and offer
  Details.
- Paths: `documents/pdf/pdf_import_flow.dart:42-97`,
  `documents/pdf/pdf_open_failure.dart`. Effort S.

**R10-9 P1 · Overview "Select all" under the Bookmarked filter selects
hidden pages.** ✅ Duplicate / Delete / Export then act on pages the user
can't see. *Fix:* select the shown pages; trim the selection when the
filter changes. Paths: `documents/overview/page_overview.dart:107,184-197`.
Effort S.

**R10-10 P1 · "Edit text" from the lasso menu leaves the Text tool on.** ✅
- *What:* `_editText` switches to `EditorTool.text` and never back; the
  next stylus stroke does nothing (a drag is ignored by the text tool),
  which reads as a dead pen.
- *Fix:* restore the previous tool when that edit session ends (unless the
  user picked another tool meanwhile).
- Paths: `editor/tools/content_layer.dart:136`. Effort S.
- *Done:* `ContentTools.editText` (lasso menu and double tap) brings the
  tool used before back when the edit ends; a tool picked meanwhile stays.

**R10-11 P2 · Android back during a library search leaves the app.** ✅
`canPop` ignores `isSearching`. *Fix:* back clears the search first.
Paths: `library/library_screen.dart:190`. Effort S.

**R10-12 P2 · Undo of Duplicate puts the copy in the trash.** ✅ The trash
count grows and the copy resurfaces on restore. *Fix:* Undo deletes the
fresh copy for good. Paths: `library/library_notebook_actions.dart:59-66`.
Effort S.

**R10-13 P2 · Stale state after Settings actions.** ✅
- The "Your notes are only on this device" notice is computed once per
  library state, so it stays after Settings → Back up library…
  (`library/library_notice.dart:144`).
- After Restore from backup… into an empty library, "Back up library…"
  stays disabled ("Nothing to back up yet") until Settings is reopened
  (`settings/backup_settings.dart:59-79`).
- *Fix:* recompute the notice in `build`; rebuild the backup tiles after
  a restore. Effort S.

**R10-14 P2 · "Keep data" (web) does nothing visible when the browser
refuses.** ✅ `if (granted) _dismiss();` has no else and no `mounted`
check. *Fix:* say so and point at installing Len or sync. Paths:
`library/library_notice.dart:175`. Effort S.

**R10-15 P2 · Sync form: an empty token goes to the server.** ✅ It comes
back as "The server didn’t accept the access token". *Fix:* "Enter the
access token" locally. Paths: `settings/sync_settings.dart:127-149`. Effort S.

**R10-16 P2 · Restore from a damaged file says "Couldn’t import".** ✅
The restore intent is only known after the manifest is read. *Fix:* the
Settings tile passes the intent, so failures say "Couldn’t restore".
Paths: `backup/len_import_flow.dart:190-250`. Effort S.

**R10-17 P2 · Opening a big backup shows nothing, and the tile can be
tapped again.** ✅ `lenFiles.open` (which reads the contents) runs before
the progress dialog. *Fix:* open inside the progress dialog; guard the
flow against running twice. Paths: `backup/len_import_flow.dart:190-208`.
Effort M.
*Done:* the file is read behind an "Opening" progress dialog (modal, so
nothing behind takes a second tap; Cancel abandons it and closes the file);
the Settings tile waits while a restore runs.

**R10-18 P2 · A huge PDF can't be cancelled while its pages are measured;
a batch of PDFs can't be cancelled as a whole.** ✅ `pageSizes` and the
blob write take no cancel token; the batch loop opens the next dialog
straight after a Cancel. *Fix:* pass the token through; a Cancel stops the
batch. Paths: `documents/pdf/pdf_import.dart:46-70`,
`documents/import/import_flow.dart:63-72`. Effort M.
*Done:* measuring waits behind the dialog's Cancel (`CancellationToken.race`),
the copy checks it while hashing and while storing, and a Cancel in any
file's dialog (PDF, inserted PDF, Len file) stops the rest of the batch;
the files done before it stay.

**R10-19 P2 · New folder lands out of view with no feedback** (while
searching inside a folder, or from Favourites / Trash via Ctrl+Shift+N). ✅
*Fix:* create it in the open folder even while searching; when a search or
another section hides it, say where it went ("Created “X” in “Library”"). Paths: `library/library_operations.dart:55`.
Effort S.

**R10-20 P2 · PDF text Ctrl+C is silent and steals Ctrl+C from text
fields.** ✅ (the shortcut says "Copied"; R10-1's fix keeps Ctrl+C in the search field) The Copy button says "Copied"; the shortcut doesn't, and it
isn't wrapped in `unlessTyping`. Paths: `editor/pdf/pdf_layer.dart:23-32`.
Effort S.

**R10-21 P2 · Overview delete calls `setState` after an await without a
`mounted` check.** ✅ Paths: `documents/overview/page_overview.dart:157`.
Effort S.

**R10-22 P2 · Copy.** ✅ (`copy_rules_test` now bans straight apostrophes; progress titles have no ellipsis: "Adding image")
- Two-sentence messages whose last sentence has no full stop:
  `settings/sync_status_line.dart:39` ("…. Sync is paused"),
  `data/archive/len_format.dart:119,123` (embedded in "Couldn’t import
  “x”: …"), `settings/backup_settings.dart:37`.
- Commands that ask first without "…": trash selection "Delete" (asks,
  `library/selection/selection_bar.dart:46`).
- Straight apostrophes in UI strings beside the ’ used elsewhere
  (`settings/sync_settings*.dart`, `storage/storage_attention.dart`,
  `library/library_notice.dart`).
- "Rendering page" (`editor/document/document_commands.dart:155`) vs
  "Adding image…" for progress titles.
- Effort S.

**R10-23 P2 · Cancelling "Adding image…" still stores the image blob.** ✅
`runWithProgress` abandons the task, which writes anyway (its contract
says tasks must not). Paths: `editor/images/editor_images.dart:183`.
Effort S.

Checked and sound: a notebook reopens at its last page and zoom; empty
text boxes are cleaned up and edits are one undo step; lasso selections
drop with their page; Len and PDF import cancel leave nothing behind;
export cancel discards; sync auth / network errors pause and say so; the
library's Esc order (selection, then search) and Enter in dialogs.


## Keyboard accessibility (`a11y/keyboard`)

Lens: Len with a keyboard alone (Tab, arrows, Enter / Space, Escape, the
Menu key), the focus ring (DESIGN §6) the only cue. Tests:
`a11y_keyboard_test`, `a11y_keyboard_groups_test`,
`a11y_context_menu_keys_test`.

- ✅ **Choice groups were one Tab stop per choice** (seven shapes, ten cover
  colours, every segment, every template). → Roving focus
  (`ui/roving_focus.dart`, the WAI-ARIA radio group / toolbar pattern):
  the editor toolbar, segmented controls (`RovingSegments`), swatch grids
  and the cover row, paper choices, the template gallery and the shape
  row are one stop at the chosen choice; ← → (↑ ↓ in grids) move, Home /
  End jump, Space / Enter pick, Tab leaves. Colour dots take focus.
- ✅ **Context menus were pointer-only** (right-click, long press). → The
  Menu key or Shift+F10 opens them on notebook cards and rows, folder
  tiles and sidebar rows, tabs, templates, overview pages, the Add page
  alternates and the page itself (`ContextMenuKeys`); the canvas menu takes
  focus on its first entry, ↑ ↓ move, Escape returns to the page.
- ✅ **Overview pages could not take focus** (only their ⋯). → Each page is a
  stop: Enter opens it, the Menu key its options, its ⋯ next.
- ✅ **Library Tab order zig-zagged** (a row of covers, then all their ⋯,
  the sidebar's Settings mid-grid). → Sidebar, then content; each card's ⋯
  right after it.
- Escape from any chrome control returns to the page; menus and popovers
  opened from the keyboard give focus back to their opener.
- ✅ Reordering overview pages by keyboard: Ctrl+← / → move the focused
  page a place, Ctrl+↑ / ↓ a row (as the scan strip's Ctrl+arrows); one
  undo step per move, announced ("Page 3 moved to 4"), focus follows the
  page; screen readers get "Move earlier" / "Move later" on the tile.

## Round 9 audit — simplicity (`review/round9`)

Lens: after eight feature rounds, is Len still *elegantly simple*? Every
user-facing setting, menu row, tip, notice, gesture and mode was listed
from the code, checked for need, discoverability, naming and "one home",
and all screenshot suites were rendered (751 images, every suite passed)
and viewed downscaled, looking for clutter.

Summary: Len is calm where it matters. The editor's chrome is the
quietest of the three apps. There are 8 real preferences, and only one
menu (⋯ → View) runs past 7 rows. The drift is in three places:
- **Tips:** five one-time tips with no budget. A new S Pen user can get
  a snack bar and two tips in the first two minutes of writing.
- **Page commands:** they live in five places, each with a different
  subset and different names.
- **Vocabulary:** a dozen small name splits (zoom names, "needs"/"keeps",
  "Retry"/"Try again", "Star"/"favourite", "Paper"/"template").

Nothing here needs a new setting. Every fix is a removal, a merge, a
rename or a budget. Paths are under `app/lib/` unless noted.

### Inventory (settings, menus, modes)

Counts are for Android on a tablet, a paged notebook, sync off.

| Area | Len | GoodNotes 6 / Notewise (approx., from their UI) |
|---|---|---|
| Settings: preferences | 8: theme, draw with finger, side button, tap to undo, hold to snap, scribble to erase, search handwriting, handwriting language | GoodNotes about 20 across ~8 sections; Notewise 40+ on one long page |
| Settings: rows shown | 17 (General 2, Writing 5, Handwriting 3, Sync 3, Backup 2, About 2) | – |
| Remembered view choices | 5: toolbar docked / floating, page flow, page fit, library sort, grid / list | similar |
| Editor ⋯ (all levels) | 24: 7 top + Page 6 + View 8 + Split 3 | GoodNotes ⋯ ~14 flat |
| Library card ⋯ | 9 | GoodNotes ~9 |
| Pen popover | colour (14 + Custom + Recent), size, Feel ▸ (pressure, stabiliser, ends: style, taper length, start / end / both, follow pen speed, Reset feel), Toolbar ▸ (quick colours, quick sizes) | GoodNotes: colours, 3 sizes, pressure, tip; Notewise more |
| Canvas long press | up to 7 | GoodNotes 3–4 |
| One-time editor tips | 5 | GoodNotes: an onboarding tour, then almost none |

| # | Item | Home(s) | Needed · discoverable · named | Verdict | Effort |
|---|---|---|---|---|---|
| **Settings** | | | | | |
| 1 | Theme (System / Light / Dark) | Settings → General | yes · yes · yes | Keep | – |
| 2 | Keyboard shortcuts | Settings → General, Ctrl+/ | yes · yes · its names drift from the menus (glossary: zoom) | Keep | – |
| 3 | Draw with finger | Settings → Writing **and** ⋯ | yes · yes · yes | Keep both: the only deliberate twin. GoodNotes also puts Stylus & Palm Rejection in its document ⋯ and in Settings | – |
| 4 | Side button (Erases / Selects / Nothing) | Settings → Writing | yes · tip · yes | Keep | – |
| 5 | Tap to undo and redo | Settings → Writing | yes · tip + HUD · yes | Keep the switch; remove its tip (R9-1) | S |
| 6 | Hold to snap | Settings → Writing | yes · tip · yes | Keep | – |
| 7 | Scribble to erase | Settings → Writing | yes · tip + eraser caption · yes | Keep | – |
| 8 | Search handwriting, language, model | Settings → Handwriting (Android) | yes · yes · yes | Keep | – |
| 9 | Sync (URL, token, set up another device, turn off) | Settings → Sync, sidebar status | yes · yes · yes | Keep | – |
| 10 | Back up library…, Restore from backup… | Settings → Backup, library notice | yes · yes · "Restore" also restores from the trash (glossary: restore) | Keep | – |
| 11 | Storage (web) | Settings → Storage | yes · yes · yes | Keep | – |
| 12 | Ink Lab (7 taps on the version) | About | lead decision | Keep | – |
| **Editor chrome** | | | | | |
| 13 | Back, All pages, title (tap: rename) | top bar | yes · yes · yes | Keep | – |
| 14 | 🎙▾ Record audio / Recordings | top bar (phones: ⋯) | yes · yes · yes | Keep | – |
| 15 | Search in notebook, Export… | ⋯, Ctrl+F, Ctrl+E | yes · yes · yes | Keep | – |
| 16 | ⋯ → Page (Duplicate page, Move or copy page…, Bookmark page, Change template…, Save as template…, Delete page) | ⋯, and in part the overview tile ⋯, the overview selection and the canvas long press | yes · yes · four label sets | Merge into one `PageCommand` list (R9-3) | S |
| 17 | ⋯ → View: Scroll pages / One page at a time, Fit page / Fit width / Automatic zoom, Toolbar docked / floating, Focus mode | ⋯ | yes · yes · 8 rows, the longest menu | Keep (each pair is a real choice); fix the names (glossary: zoom) | S |
| 18 | Split view (open, swap, close) | ⋯ ▸, tab menu | yes · yes · yes | Keep | – |
| 19 | Tabs / Open notebooks (n) | tab strip (wide), ⋯ (phones) | yes · yes · yes | Keep | – |
| 20 | Focus mode (F11), presenting (F5 = focus + laser) | ⋯ → View, keys, puck | yes · F5 only through the shortcut sheet | Keep | – |
| 21 | Page indicator (tap: Go to page; long press: overview) | over the page | yes · peeks · yes | Keep | – |
| 22 | Canvas long press: Paste here, Select all on page, Add text here, **Add page after, Bookmark page, Change template…** | canvas | content rows yes; the page rows are a third home | Merge the page rows into ⋯ → Page (R9-3) | S |
| 23 | Zoom pill (Fit content, Back to start) | canvas | yes · yes · yes | Keep | – |
| 24 | Gesture HUD, "Draw anywhere" hint | canvas | yes · – · yes | Keep | – |
| **Tools** | | | | | |
| 25 | Pen, Highlighter, Eraser, Lasso, Shapes, Text, Laser, Insert ⊕ | toolbar | parity · yes · yes | Keep | – |
| 26 | Quick colours and sizes | toolbar slots | yes · yes · yes | Keep | – |
| 27 | "Toolbar ▸ Quick colours n, Quick sizes n" | pen and highlighter popovers | rarely · collapsed · **"Toolbar" also names docked / floating** | Rename the disclosure "Quick colours and sizes" | S |
| 28 | Pen ends: style, taper length, start / end / both, **follow pen speed** | Pen ▸ Feel | lead decision · collapsed · yes | Keep; make "Follow pen speed" a default (on) and drop its switch | S |
| 29 | Reset feel (pen, highlighter: at the end of Feel) vs Reset (eraser, laser: top right) | popovers | yes · two places · two names | Merge: one "Reset" in the header for every tool | S |
| 30 | Highlighter: Straight lines | highlighter Feel | yes (GoodNotes has it) · yes · yes | Keep | – |
| 31 | Eraser: Whole stroke / Partial, size, highlighter only | eraser popover | parity · yes · yes | Keep | – |
| 32 | Laser: Dot / Trail, colour, size, trail length | laser popover | lead decision | Keep | – |
| 33 | Lasso pill: Style, Cut, Copy, Delete, ⋯ (Duplicate, Paste, Convert to text, Link…, Crop, Bring to front, Send to back) | selection | yes · yes · yes | Keep (arranging shows only where things overlap: good) | – |
| 34 | Insert ⊕: Image…, Take photo, Pages from PDF…, Page with template… | toolbar | yes · yes · "Page with template…" is a fifth home for adding a page | Keep; see R9-3 | – |
| **Library** | | | | | |
| 35 | ⊕▾: New notebook, **New canvas**, Import PDF…, Import Len file…, New folder… | header (wide); phone ⊕ (long press) | New canvas duplicates the sheet's Notebook / Canvas switch | Merge: drop the ⊕▾ row | S |
| 36 | New notebook tile + ⊕▾ + Ctrl+N (wide); FAB (phones) | library | one primary action per screen holds on phones; wide has tile **and** ⊕▾ | Keep (the tile is the obvious path; ⊕▾ holds the other four) | – |
| 37 | Sheet: Import PDF…, Import Len file… (phones) | new-notebook sheet | yes on phones (long press is hidden) · yes | Keep | – |
| 38 | ⇅ View: Sort by (3), Show as (2), Select | header | yes · yes · yes | Keep | – |
| 39 | Card ⋯: **Open**, Rename…, Add to favourites, Change cover…, Duplicate, Move to folder…, Export…, Select, Move to trash | card | "Open" repeats the tap | Remove "Open" (card and folder) | S |
| 40 | Folder ⋯: Open, Edit folder…, Move to folder…, Export…, Delete folder | folder | "Edit folder…" vs notebook's "Rename…" + "Change cover…" (glossary: edit an object) | Keep; rename | S |
| 41 | Recent row | library root | yes · yes · only when one of them is in a folder (good) | Keep | – |
| 42 | Sidebar: Library, Favourites, Trash, folder tree, Settings, sync status | wide; drawer on phones | yes · yes · yes | Keep | – |
| 43 | Selection bar: Favourite, Move to folder…, Export…, Trash | library | yes · yes · differs in shape from the overview's (R8-13, open) | ✅ Keep; one bar (R8-13): one shape everywhere, the count on top and the commands under it | M |
| **Pages** | | | | | |
| 44 | Overview: All / Bookmarked / Outline, Select, Add page tile, tile ⋯ (7), selection (6) | ▦ | yes · yes · see R9-3 | Keep | – |
| 45 | Outline panel and entries | overview → Outline | lead decision | Keep | – |
| 46 | Multi-page Delete asks **and** offers Undo | overview selection | the library trashes and deletes folders with Undo only | Remove the confirmation (R9-6) | S |
| **Gestures** (no settings unless listed) | | | | | |
| 47 | Pen draws; finger draws until a stylus is seen; two fingers pan and zoom; double-tap zoom; two- / three-finger tap (setting); long press (canvas menu); hold to snap (setting); scribble to erase (setting); side button (setting); lasso tap on PDF text; highlighter snaps to PDF text; tap title (rename); long-press page indicator (overview); long-press phone ⊕ (New menu); drag and drop; file drop | – | 16 gestures; the invisible ones are each taught once (tips) or sit in captions | Keep; teach on a budget (R9-1) | – |

Modes: focus, presenting, split view, tabs, three selection modes
(library, overview, recordings), text editing, crop, search, recording
and playback. Each has one way in and Esc (or ✕) out. Keep.

### Tips and notices

All of them, from the code:

| Kind | Message | When | Where | Once? |
|---|---|---|---|---|
| Tip | "Hold the pen’s side button to erase" (or "…to select with the lasso") | first stylus contact in an editor, after the stylus snack closes | editor bottom, 10 s | per device |
| Tip | "Hold the pen still at the end of a line or shape to snap it clean" | a hand-drawn line or shape, then the pen rests 2 s | editor bottom, 10 s | per device |
| Tip | "Circle ink, text or images to select them[; tap PDF text…]" | first pick of the lasso | editor bottom, until a selection is made | per device |
| Tip | "Or scribble over ink with the pen to erase it" | second pick of the eraser | editor bottom, 10 s | per device |
| Tip | "Tap with two fingers to undo, three to redo" | third ↶ tap on touch | editor bottom, 10 s | per device |
| Snack | "Stylus detected: fingers now pan and zoom" [Keep finger drawing] | first stylus contact ever | 4 s | once |
| Snack | "Scribble erases ink only" | a scribble over a text box or image | 4 s | each time |
| Snack | "Sync stopped: the server refused the access token" / "Not synced since …" [Settings] | token refused; a day of failures | 8 s | until sync works again |
| Notice | Unsaved changes (full browser storage); files not kept (private window) | web, while true | library top | persistent |
| Notice | "Len started fresh" | storage from another version | library top | once |
| Notice | "This browser may clear your notebooks" [Keep data] | web, sync off, not persisted | library top | once |
| Notice | "Your notes are only on this device" [Back up…] [Set up sync…] | sync off, a notebook ≥ 1 day old, no backup (again after a backup is 30 days old) | library top | once (per stale backup) |
| Notice | Missing PDF [Locate file…]; parked pane [Show] [Stop] | editor | top of the canvas | while true |
| Note | Access token kept with Len's data | Settings → Sync | inline | once |
| Hint | "Draw anywhere" | an empty canvas | centre | until the first edit |
| Status | Sync alert ("Offline: not synced since …") | top bar | while failing | – |

What holds:
- Library notices never stack. `LibraryNotices._notice`
  (`features/library/library_notice.dart:116-155`) picks one by priority.
- Editor notices and tips step aside while a snack bar shows
  (`MessageQueue.stepAside`, `ui/messages.dart:147`).
- Only one tip shows at a time (`TipsController.value`).
- The device-only notice waits a day, so it never greets a new user.

What doesn't:
- **No budget.** `TipsController.offer`
  (`features/editor/chrome/editor_tips.dart:144-193`) shows any unseen tip
  at once. A new tip *replaces* the one on screen.
- **Tips can be lost.** A tip is marked seen when it is offered
  (`markSeen` at :188), not when it was read. If it is replaced after a
  second, or hidden for its whole 10 s behind a snack bar (`stepAside`
  hides it; its timer keeps running), it never comes back.
- **Tips sit on the writing.** They are on the page's bottom lines for
  10 s, and don't fade while the pen is down. Pen input that lands on the
  card goes to the card, not the page.
- **Tips can come mid-writing.** Only hold to snap waits for a calm
  pen (`calmFor`). The side-button tip follows the stylus snack, which
  comes *during* the first stroke (`editor_screen_actions.dart:8-31`).

**First hour, simulated** (new install, Android tablet with S Pen, paged
notebook; from the triggers above):

| Time | Event | What appears |
|---|---|---|
| 0:00 | Library opens, empty | Empty state ("Import PDF…", "Set up sync…"). On the web, also "This browser may clear your notebooks" (two sync nudges on the first screen). |
| 0:01 | First stroke with the S Pen | Snack "Stylus detected…" (4 s, bottom, 3 lines on a phone), **then** the side-button tip (10 s), while the user is writing the first lines |
| ~0:02 | Underlines a heading, pauses 2 s | Hold to snap tip. It **replaces** the side-button tip if that is still up; the side-button tip is spent anyway |
| ~0:05 | Taps ↶ three times | Finger-tap undo tip |
| ~0:08 | Picks the lasso | Lasso tip |
| ~0:15 | Picks the eraser a second time | Scribble tip (the eraser popover already has the same caption) |
| any | Scribbles over a text box | Snack "Scribble erases ink only" |
| 24 h later | Library | "Only on this device" notice (correct) |

The result is 1 snack and 5 tips in about 15 minutes, and 3 messages in
the first 2 minutes. GoodNotes front-loads a short tour, then stays
quiet. Len's contextual tips are the better idea, but they need a
budget.

**Proposed calm budget (R9-1):**
1. At most **one tip per editor session** (opening a notebook). At
   least **10 minutes** between tips, and none within 60 s of a snack
   bar. Keep `lastTipAt` in `SettingsRepository`, next to `tips_seen`.
2. Offer a tip only when the pen has rested ≥ 2 s (`calmFor` for every
   tip, not just hold to snap). Fade it while the pen is down, and pause
   its timer.
3. Mark a tip seen only after it has been visible for ≥ 3 s. A tip that
   is replaced or hidden stays unseen and waits for its next trigger.
4. A tip never replaces another tip. The later one waits for its next
   trigger.
5. Priority when several are due: side button > hold to snap > lasso >
   scribble.
6. **Remove the finger-tap undo tip.** The HUD names Undo and Redo when
   the gesture happens. The Settings row says it. SIMPLIFY #38 (lead
   approved) removed it, and R6-14 brought it back.
7. The side-button tip doesn't follow the stylus snack. Under rule 1,
   it goes to the next session.

With the budget, the first hour is: the stylus snack in session 1, hold
to snap or lasso in session 1, the side button in session 2, and so on.
At most one teaching message per notebook opening, never while the pen
moves. Effort S (all in `editor_tips.dart`, `editor_screen_actions.dart`
and `settings_repository.dart`), plus tests in `test/gesture_tips_test.dart`.

### Glossary (one noun, one verb, one string)

| Concept | Use | Found instead (fix) |
|---|---|---|
| notebook / canvas | "notebook" (paged), "canvas" (infinite); "notebook" for both in counts | ✓ |
| page design | **template** ("Change template…", "All templates", "My templates") | "Paper" heading in the new-notebook sheet (`library/new_notebook_sheet.dart:238`); export "Page templates" (`documents/export/export_sheet.dart:255`) → "Template", "Templates". "Paper" stays for its colour only ("Paper colour"). Canvas "Background…" stays (a canvas has no pages) |
| favourite | "Add to favourites", "Favourite" | "Star notebooks you use often…" (`library/library_empty_state.dart:63`) → "Add notebooks you use often to favourites…" |
| trash | "Move to trash", "moved to the trash"; "Trash" only as the section's name | "went to the Trash" (`editor/document/page_transfer_flow.dart:59`) → "the trash" |
| delete | "Delete" (undoable, no question), "Delete…" (asks), "Delete forever…" | ✓, except R9-6 |
| one page left | "A notebook needs at least one page" | "keeps" (`page_transfer_flow.dart:28,44`) → "needs" |
| retry | "Try again" | "Retry" (`settings/sync_status_line.dart:127`) |
| failure | "Couldn’t …" | "Could not …" (`audio/recording_controller.dart:158,205,230`, `audio/backends/record_capture.dart:84`) |
| page zoom | "Fit page", "Fit width", "Automatic zoom" (`document/page_fit.dart`) | Shortcut sheet: "Whole page", "Page width" (`settings/keyboard_shortcuts.dart:132-133`) |
| canvas zoom | "Fit content", "Back to start" (zoom pill) | Shortcut sheet: "Fit the content", "Back to the start" (`keyboard_shortcuts.dart:141,150`) |
| page commands | inside a page-scoped menu (⋯ → Page, tile ⋯, page selection): bare verbs ("Duplicate", "Bookmark", "Move or copy…", "Change template…", "Delete"); in a mixed menu (canvas long press): with "page" | ⋯ → Page says "Duplicate page", "Move or copy page…", "Bookmark page", "Delete page" (`chrome/editor_more_menu.dart:134-145`); the selection bar says "Template…" (`overview_selection.dart:79`) |
| restore | "Restore" = out of the trash | "Restore from backup…" also brings back a backup (as a copy, "nothing here is replaced"). Keep: users look for that word, and the subtitle says what it does |
| edit an object | "Rename…" + one appearance row | Notebook: "Rename…" + "Change cover…"; folder: "Edit folder…" (name and colour in one dialog). Call the folder row "Rename…" too (its dialog keeps the colour), so both objects answer to the same verb |
| stylus | "pen" in tips and tools; "S Pen (or stylus)" only in the Side button row | "Stylus detected" snack: fine (it is about the device) |
| quick slots | "quick colours", "quick sizes" | Disclosure "Toolbar" in the pen popover (`pen/ink_options.dart:118`) collides with "Toolbar docked / floating" |

One interaction model per object:
- **Notebook:** tap opens; ⋯ / right-click / long press opens the menu;
  trash with Undo. ✓
- **Folder:** the same, but its ⋯ says "Edit folder…" (glossary) and "Delete
  folder" (undoable, ✓).
- **Page:** five homes with different subsets (R9-3).
- **Selection:**
  - The lasso pill and the library and overview bars use the same verbs.
  - The two bars differ in shape (R8-13, open).
  - Page delete asks; notebook trash doesn't (R9-6).
- **Recording:** 🎙▾, the sheet's ⋯ (Rename…, Trim…, Reset trim, Save to
  device…, Delete…) and its selection. The same verbs as notebooks. ✓

### Clutter (screenshots)

- **Editor:** calm everywhere. Tablet bar: 8 tools, 3 + 3 slots, 🎙, ↶ ↷,
  ⋯. The phone bar: 2 tools and the slots. Only ⋯ → View is long (8
  rows), with radio groups that read well.
- **Library, wide:** five rows stack above the first cover:
  - the notice;
  - the title with search, ⊕▾ and ⇅;
  - Recent;
  - folders;
  - the New tile.

  It is acceptable because the notice comes after a day and Recent only
  when it adds something. But on a wide screen, "Only on this device" is
  said twice at once (the notice and the sidebar status). Keep both: the
  notice can be dismissed, and the status is ambient.
- **New-notebook sheet (phone):** "Import PDF…" and "Import Len file…"
  sit between Notebook / Canvas and Paper, and break the form. Move them
  under Create, as quiet links (P2).
- **Pen popover:** four groups; Feel and Toolbar are collapsed. Fine. Its
  Reset differs from the eraser's and the laser's (row 29).
- **Overview selection bar:** 6 actions on two rows. The library's bar
  has 4 actions on one row. Same job, two shapes (R8-13). ✅ One shape
  now: both bars put the commands in a row under the count.

### Prioritised items

**R9-1 P1 · Tips have no budget, can be lost, and sit on the writing.** ✅
See "Proposed calm budget" above. Effort S.
- ✅ Done as proposed (`fix/r9-tips-pen`). The tip card has no ✕ any
  more: it lets every pointer through, so it couldn't take a tap; it goes
  after 10 s on screen.

**R9-2 P1 · The first stroke gets the stylus snack, then the side-button
tip.** ✅ (the tip waits for the next opening)
- *What:* `_onStylusDetected` (`editor/editor_screen_actions.dart:8-31`)
  chains the side-button tip onto the snack's close.
- *Why:* the first 14 s of a new user's first page have messages over
  the bottom lines.
- *Fix:* the tip goes to the next editor session (R9-1, rule 7).
- Effort S.

**✅ R9-3 P1 · Page commands live in five places with four label sets.**
- *What:* the five places:
  - ⋯ → Page (6 rows, no "Add page after");
  - the overview tile ⋯ (7 rows);
  - the overview selection (6);
  - the canvas long press (Add page after, Bookmark page, Change
    template…);
  - adding a page from the footer, Insert ⊕ "Page with template…", the
    overview tile and the canvas menu.
- *Why:* the same command has different names, and different places
  offer different commands. A user who learned "Add page after" in the
  overview won't find it in ⋯.
- *Fix:*
  - One list, `PageCommand.values`, in one order with one label set
    (bare verbs, glossary). It is shown whole in ⋯ → Page and in the
    tile ⋯. The selection shows the multi-page subset.
  - The canvas long press keeps content actions only: Paste here,
    Select all, Add text here, links.
  - Adding a page keeps two homes: the footer / overview tile "Add page",
    and "Add page after" in the page menu. Insert ⊕ "Page with
    template…" goes; "Add page after" opens the same template choice on
    long press.
- Files: `chrome/editor_more_menu.dart`, `editor/editor_gestures.dart`,
  `documents/overview/page_commands.dart`, `overview_selection.dart`,
  `toolbar/insert_menu.dart`.
- Effort S.

*Done (`fix/r9-commands`):* `PageCommand.menu` is the one page menu, in
⋯ → Page and the tile ⋯: Add page after, Duplicate page, Move or copy
page…, Bookmark page (Remove bookmark), Change template…, Save as
template…, Delete page. Lead decision: the names keep "page" (they read
alone in the tile ⋯ too); the selection bar keeps bare verbs for several
pages, in the same order ("Template…" became "Change template…"). The
canvas long press offers content only. Insert ⊕ lost "Page with
template…": holding (or right-clicking) "Add page after", the Add page
footer or the overview's add tile asks for a template
(`PageCommand.insertWithTemplate`, `MenuRow.alternate`).
*Follow-up (`fix/r9-followups`):* screen readers get it as a custom action
"Add page with template" on the "Add page after" row (`MenuRow.alternateAction`,
`PageCommand.alternateAction`); hovering the row shows "Hold or right-click for a
template"; the Add page footer has the caption "Hold for a template" under it until
it has been held once (one-time notice `add-page-hold`, not a tip).

**✅ R9-4 P2 · Vocabulary drift.** Apply the glossary's "Found instead"
column (11 strings). Effort S.
*Done (`fix/r9-commands`):* all of them; the new-notebook sheet says
"Template" ("Background" for a canvas), the folder row is "Rename…" (its
dialog, "Rename folder", keeps the colour). `copy_rules_test` now bans the
old names ("Could not", "Retry", "the Trash", "keeps at least one page",
the old zoom names, "Template…", "Page templates", "Edit folder…").

**✅ R9-5 P2 · Two homes for "New canvas".**
- *What:* the ⊕▾ row (`library/library_new_menu.dart:24`) and the
  sheet's Notebook / Canvas switch.
- *Fix:* drop the row. ⊕▾ becomes New notebook, Import PDF…, Import Len
  file…, New folder….
- Effort S.

**✅ R9-6 P2 · Deleting several pages asks, then also offers Undo.**
- *What:* `overview_selection.dart:43-55` asks, and
  `document_commands.dart:219-226` offers Undo.
- *Why:* nothing else in Len both asks and offers Undo. Notebooks,
  folders and single pages only offer Undo.
- *Fix:* drop the confirmation.
- Effort S.

**✅ R9-7 P2 · Card and folder menus start with "Open".**
- *What:* `library/library_menus.dart:44,76`.
- *Why:* tapping the card does the same. The menu gets shorter, and the
  first row becomes Rename….
- Effort S.

**R9-8 P2 · Tool popovers reset in two ways.** ✅
- *What:* "Reset feel" sits at the end of the collapsed Feel
  (`pen/ink_options.dart:183`), while "Reset" sits in the header of the
  eraser and laser popovers.
- *Fix:* one "Reset" in every popover's header. For pens and
  highlighters it resets the feel and keeps the quick slots, as now.
- Effort S.

**R9-9 P2 · The pen popover's "Toolbar" disclosure.** ✅
- *What:* the name collides with ⋯ → View "Toolbar docked / floating".
- *Fix:* rename it "Quick colours and sizes" (summary "3 and 3").
- Effort S.

**✅ R9-10 P2 · Phone new-notebook sheet: the import links break the
form.** Move them under Create (or into the empty state and ⊕'s long
press only). Effort S. *Done:* quiet links at the sheet's foot, under
Create (hidden while the keyboard is up).

**R9-11 P2 · "Follow pen speed" is a switch nobody will tune.** ✅ (always on;
`PenEnds.followSpeed` is gone) Make it
the default for tapered ends (on) and drop the switch
(`pen/pen_ends_options.dart`). The pen's Feel loses a control. Effort S.

### Remove / Default

| What | Verdict | Effort |
|---|---|---|
| Finger-tap undo tip (`EditorTip.gestureUndo`) | Remove | S |
| Side-button tip chained to the stylus snack | Default: next session | S |
| Canvas long press: Add page after, Bookmark page, Change template… | ✅ Merge into ⋯ → Page | S |
| Insert ⊕ "Page with template…" | ✅ Merge into "Add page after" (long press: choose template) | S |
| ⊕▾ "New canvas" | ✅ Merge into the sheet's Notebook / Canvas | S |
| Card and folder ⋯ "Open" | ✅ Remove | S |
| Multi-page delete confirmation | ✅ Remove (Undo is there) | S |
| "Follow pen speed" switch | Default on | S |
| "Reset feel" at the end of Feel | Merge into a header "Reset" like the other tools | S |
| Pen popover "Toolbar" disclosure | Rename "Quick colours and sizes" | S |

Kept on purpose: "Draw with finger" in ⋯ and Settings, Restore from
backup… in Settings (a shortcut to Import Len file…), Recent, the
sidebar sync status beside the device-only notice, and the 8 rows of
View.

## Web walk-through (`test/web-explore`)

`app/tool/web_explore.py` walked the release web build (JS and `--wasm`) in
Chromium and Firefox. Found and fixed (✅):
- ✅ Inserting an image did nothing in browsers (`ImageDescriptor.width`
  throws there).
- ✅ Len files and backups written in browsers didn't open (zip headers
  big-endian after `archive`'s web deflater).
- ✅ Selection pill buttons had no names for screen readers; F11 wasn't
  named in the View menu on the web.
- ✅ The sync status and the New notebook button named the whole library
  for screen readers (their tooltips); on phones the New button and its
  long press were separate nodes.
- ✅ Ctrl+/ didn't open the shortcuts from Settings, as its row promises.
- ✅ A library card stopped being a button (an unnamed group) for screen
  readers once its ⋯ showed (hover, focus, always on touch); the hidden ⋯
  was out of their reach.
- ✅ `--wasm`: every database page read copied the rest of the database
  (dart2wasm's `setRange` into wasm memory): restoring a 20 MB backup took
  2 minutes and froze the tab for up to 50 s; now 4 s.
- Open: opening a 40-page notebook of 4 000 strokes has 0.5–1.8 s long
  tasks in both builds (reported by the walk, not failed); a folder tile
  and a list row are still groups for screen readers while their ⋯ shows.

## Round 8 audit (`review/round8`)

Scope: everything that landed after round 7: Len files and library backup
and restore, the "only on this device" notice, the Recent row and its
short-window strip item, reopening where you left off, export from the
library, moving and copying pages (including to a new notebook), the sync
alert, recordings in the library, selecting PDF text with the pen, hold to
snap in the pen's Feel, highlight colours, scribble to erase (with its
preview), the highlighter snapping to PDF text, and Import Len file on
phones. Plus a whole-app consistency sweep after eight rounds.

Method:
- Rendered all 728 images in `test/screenshots/` (every suite passed) and
  viewed them downscaled, as contact sheets and as crops.
- Walked the code of each new flow as a demanding user, checking the edge
  cases one by one: an empty library with Recent, backing up a big
  library, restoring twice, moving the last page, scribbling near text
  boxes and images, and highlighter snapping on turned PDF pages.
- Checked every item in the code. Paths are under `app/lib/` unless noted.

Summary: the features are good ideas, well placed, and they mostly look
like Len. One P0: Undo on a page move can delete work. Most P1s are about
trust:
- A backup restore fails completely over one bad byte, and nests the
  library a level deep on a new device.
- Restores can't be undone.
- The phone library now stacks a notice, Recent and folders above the
  first cover.
- Two gestures that change every stroke (scribble to erase, hold to snap)
  are invisible.

The design language itself held up. There are no `_rounded` or `Icons.*`
glyphs, and tokens are used almost everywhere. The drift is in the
vocabulary (one action, several names) and in two selection bars that
grew apart.

### Top 10 (fix first)

1. ✅ R8-1 (P0) Undoing a page move or copy deletes whatever was written in
   the destination since. With "New notebook…", it deletes the whole
   notebook for good.
2. ✅ R8-14 (P1) A restore is all or nothing: one damaged blob or line, and
   nothing comes back.
3. ✅ R8-16 (P1) A restore has no confirmation and no Undo. Restoring twice
   duplicates the library on every synced device.
4. ✅ R8-15 (P1) Restoring on a new or empty device buries the whole library
   in a "Backup 13 Oct 2026" folder.
5. ✅ R8-24 (P1) Highlighted PDF text can't be selected with the pen any more.
6. ✅ R8-25 (P1) A scribble erases along the whole stroke, not just where it
   zigzagged, and can wipe an outline it filled in.
7. ✅ R8-7 (P1) Phones: the notice, Recent and folders push the first cover
   below the middle of the screen. Held sideways, the notice takes 27 % of
   the height.
8. ✅ R8-26 (P1) Scribble to erase and hold to snap are never taught. They sit
   under "Reset feel" in the collapsed Feel section, below the fold.
9. ✅ R8-2 (P1) Move or copy pages isn't in the editor's page menu, only in
   the page overview.
10. ✅ R8-17 (P1) On the web, a backup is built entirely in memory. A library
    full of PDFs crashes the tab.

### Pages between notebooks

✅ **R8-1 P0 · Undoing a page transfer deletes later work.**
- *What:* `PageEdits.sendTo` (`features/editor/document/page_edits.dart:87-126`)
  records the transfer as a step in the source notebook's history. Its
  undo runs `removeCopies` (`data/notebook_duplicator.dart`). That deletes
  the copied pages whatever happened to them since.
- For "New notebook…" the undo also calls `discard` =
  `services.notebooks.delete` (`page_transfer_flow.dart:44`), a permanent
  tombstone of the notebook and everything in it
  (`data/notebook_repository.dart:218`). It does not go to the Trash.
- Undo stays reachable through the toolbar, gestures and keyboard as long
  as the step is in history. Older steps can be undone out of order
  (`page_models.dart:137-149`).
- *Why:* move three pages to "Biology", write there for ten minutes, go
  back to the source tab and undo twice. The writing is gone, and with a
  new notebook there is nothing in the Trash.
- *Fix:*
  - Before undoing, check whether the copies (or the new notebook) changed
    since the transfer: compare `updated_at` with the copy stamp and look
    for pages added there. If they did, refuse with "Pages changed in
    “Biology” since: move them back from there".
  - Never `delete` a notebook in an undo. Trash it, and only when it is
    untouched.
- *Done (`fix/r8-data`):* `PageTransfer` (`editor/document/page_transfer.dart`)
  marks the copies' state (`data/change_mark.dart`) when it makes them.
  Undo restores the originals. It removes the copies only while that mark
  is unchanged; changed copies stay, and the snack says "The copies in
  “Biology” changed since, so they stay". A notebook made by "New
  notebook…" always goes to the Trash with everything in it (and the
  snack says so if it changed). Redo reuses copies still there (taking
  the notebook out of the Trash), so nothing doubles; once the Trash is
  emptied it makes a new one. Tests: `page_transfer_undo_test.dart`.

**✅ R8-2 P1 · Move or copy pages is missing from the editor.**
- *What:* ⋯ → Page (`features/editor/chrome/editor_more_menu.dart:128-145`)
  and the page long-press actions (`editor_gestures.dart:73-89`) have no
  entry for it. It exists only in the overview (`page_commands.dart:14`,
  `overview_selection.dart:128`), although R7-9 promised "the page menu".
- *Why:* "file this page into Physics" happens while looking at the page.
- *Fix:* add `PageCommand.moveTo` after "Duplicate page" in ⋯ → Page.
  `DocumentCommands` already dispatches it (`document_commands.dart:137`).

*Done (`fix/r8-library`):* ⋯ → Page → "Move or copy page…" (after Duplicate page) runs `PageCommand.moveTo` on the current page: the same picker and flow as the overview (`test/page_transfer_menu_test.dart`).

**✅ R8-3 P2 · Moving every page is refused only after the user has picked.**
- *What:* the check runs after the picker has closed
  (`page_transfer_flow.dart:35-38`), and with one page the message reads
  "…copy them instead".
- *Fix:* when every live page is selected, `pickPageDestination` disables
  Move and says "A notebook keeps at least one page" under it. Then drop
  the check after the picker.

*Done (`fix/r8-library`):* `pickPageDestination(noMove: …)` when every page is sent: Move is disabled and the picker says why ("A notebook keeps at least one page, so this one can only be copied"). A guard stays after the picker for pages a sync removed meanwhile.

**✅ R8-4 P2 · One action, three names, and a borrowed icon.**
- *What:* the menu and the selection bar say "Move to…"
  (`page_commands.dart:14`, `overview_selection.dart:128`). It opens
  "Move or copy N pages" with Move and Copy (`page_transfer_flow.dart:22`).
  `drive_file_move` is also the library's "Move to folder…"
  (`library/library_menus.dart:61`).
- *Fix:* call it "Move or copy…" everywhere it opens the picker (menu,
  bar, R8-2), so Copy is discoverable. Keep the snack's "Moved 3 pages to
  “X”". Give it a different glyph from the folder move
  (`Symbols.move_group_sharp` or similar).

*Done (`fix/r8-library`):* pages: "Move or copy…" everywhere it opens the picker (overview menu and selection bar; "Move or copy page…" in the editor's Page menu), with `Symbols.move_group_sharp`; notebooks and folders keep "Move to folder…" with `drive_file_move`.

✅ **R8-5 P2 · A move isn't one database transaction.**
- *What:* `send()` calls `copyPages` (its own transaction), then
  `deleteAll`, `retargetLinks` and `touch` separately
  (`page_edits.dart:100-109`). The undo does run in one transaction
  (`:114`).
- *Why:* if something throws or the app is killed part way, the user is
  left with duplicate pages, or links pointing at copies while the
  originals still exist, and sync uploads that state.
- *Fix:* wrap `send` in `services.database.transaction`.
- *Done (`fix/r8-data`):* `PageTransfer.send` is one transaction.

**✅ R8-6 P2 · The destination picker loses its way in a big library.**
- *What:* captions show only the parent folder's name
  (`page_transfer_flow.dart:97-101`). The Recent row and search show the
  path via `LibraryController.locationOf` (`library_controller.dart:281-289`),
  so two "Week 3" notebooks in two "Lectures" folders look identical
  here.
- The list is a non-lazy `ListView(shrinkWrap: true)` over every notebook,
  with no filter (`documents/overview/notebook_picker.dart:107-135`).
- *Fix:* share `locationOf`, use `ListView.builder`, and add a filter
  field once there are more than about 12 notebooks.

*Done (`fix/r8-library`):* captions use the library's path (`LibraryQuery.pathOf`, shared with Recent and search: "School › Maths"); the list is a `ListView.builder`; over 12 notebooks a "Find a notebook" filter field shows.

### Library

**✅ R8-7 P1 · Phones: chrome pushes the notebooks off the screen.**
- *What:* `library_phone_light.png` stacks four bands above the first
  cover, which starts 55 % of the way down the screen:
  - the "only on this device" notice: four lines, with "Back up…" on a
    row of its own;
  - the header;
  - Recent;
  - two rows of folders.
- Held sideways (`library_phone_sideways_*.png`, 844×390), the notice
  takes about 105 of the 390 dp. That undoes the one-row-of-chrome work of
  round 6 (R6-2, R6-3).
- *Why:* the library's job is "get to the right page fast" (DESIGN §0),
  and on a phone this is the first screen.
- *Fix:*
  - On phones and short windows, the notice becomes one line: the title
    with "Back up…" inline and ✕ (`features/library/library_notice.dart`,
    `LibraryNotice` layout). The explanation moves to Settings → Backup,
    where it already is.
  - On phones, folders take one sideways-scrolling row (`FolderRow.strip`)
    when the Recent row is shown.

*Done (`fix/r8-library`):* on phones and short windows the device-only notice is one line (`LibraryNotice.shortTitle`: "Only on this device", Back up…, ✕; 49 dp), and under the Recent row the folders take one sideways line (`FolderRow.strip`). The first covers start at about 36 % of a portrait phone, under one row of chrome sideways.

**✅ R8-8 P2 · The device-only notice: parenthetical copy, one action, and
it never comes back.**
- *What:* the body ends with "(Settings)" and offers only "Back up…"
  (`library_notice.dart:128-140`). After one backup, `lastBackupAt != null`
  hides it for good. Settings shows "Last backup 3 Oct" with no sense of
  age (`settings/backup_settings.dart:38-40`).
- *Fix:*
  - Body: "Back up your library now and then, or set up sync." Actions:
    "Back up…" and "Set up sync…".
  - With sync off, show the notice again (once) when the last backup is
    over 30 days old and notebooks have changed since.

*Done (`fix/r8-library`):* the body reads "Back up your library now and then, or set up sync", with Back up… and Set up sync…. Without sync, the notice comes back once per backup when it is over 30 days old and a notebook changed since (`LibraryNotices.staleAfter`, tip id `notes_device_only@<time>`), saying when the last backup was.

**✅ R8-9 P2 · "Local only" against "only on this device".**
- *What:* the sidebar says "Local only" (`ui/sync_status_button.dart:15`).
  The notice, Settings → Sync (`sync_status_line.dart:32`) and Settings →
  Backup (`backup_settings.dart:25`) say "only on this device". R7-12
  chose "On this device only".
- On the Settings screen, Backup's description repeats the Sync line just
  above it, word for word in meaning (`s_settings_backup_*.png`).
- *Fix:*
  - The caption reads "On this device".
  - With sync off, Backup's description drops its first sentence and
    starts with "Back up your library now and then…".

*Done (`fix/r8-library`):* one phrase, `deviceOnlyCaption` "Only on this device" (sidebar caption, one-line notice; sentences say "only on this device"). The sidebar stacks the caption under Settings while sync is off, so it is never cut. Backup's description starts with "Back up your library now and then…" with sync off. The sync tooltip lost its dash ("Synced: tap to sync now").

**✅ R8-10 P2 · Recent: noise and lost slots.**
- *What:* notebooks at the root are captioned "Library"
  (`library_controller.dart:288`), which says nothing when you are standing
  in the Library. Trashed and deleted notebooks keep their slots, since
  `noteOpened` keeps 8 ids and only filters them when shown
  (`editor/tabs/workspace_memory.dart:32,50-55`). Trash three, and Recent
  shows five.
- The short-window item says "Recent, 3 notebooks", and its menu entries
  have no location (`recent_row.dart:196-201,231-235`).
- *Fix:*
  - No caption for root notebooks.
  - Keep 16 ids and show the first 8 that are live.
  - The strip item's caption names the latest notebook, and its menu
    entries carry the location the row shows.

*Done (`fix/r8-library`):* Recent tiles at the top level have no caption (`LibraryController.folderPathOf`); the workspace remembers 16 notebooks and the row shows the first 8 live ones; the sideways strip item is captioned with the latest notebook, and its menu rows carry the folder (`MenuRow.caption`).

**✅ R8-11 P2 · A recording match doesn't say why it matched.**
- *What:* recording titles match in the library's title filter
  (`library_controller.dart:257`). While searching, the caption becomes
  the path only (`library_content.dart:248`), and list rows lose
  "2 recordings".
- *Fix:* when only a recording title matched, caption the result
  "Recording “Lecture 4”" with the mic glyph. Better: add a recording
  result kind to `library_search_results.dart` that opens the recordings
  sheet at it.

*Done (`fix/r8-library`):* a notebook found only by a recording's title is captioned "Recording “Lecture 4”" (`LibraryController.recordingMatchOf`). A recording result kind in the full-text results is left for later.

**✅ R8-12 P2 · The sync alert says "Not synced since Just now" and goes red
for being offline.**
- *What:* when everything synced except a few file uploads, `lastSuccess`
  is set but `_failingSince` stays (`sync/sync_controller.dart:218-231`).
  After 15 minutes the tooltip reads "Not synced since Just now: open Sync
  settings" (`settings/sync_alert_button.dart:12-15,38`). Being offline
  (`SyncFailure.network`) also shows the error-red glyph and points to
  Settings, where nothing can be fixed.
- *Fix:*
  - File-upload failures: "3 files not uploaded yet".
  - Network failures: a Graphite glyph and "Offline: not synced since
    Monday".
  - Keep red for auth and incompatible failures. Write "just now" in
    lower case inside a sentence.

*Done (`fix/r8-library`):* `syncAlert`: files left to upload say "3 files not uploaded yet" (`SyncController.filesNotUploaded`), being offline "Offline: not synced since Monday" with the cloud-off glyph, both in Graphite; red only for failures Settings can fix. "just now" is lower case after "since" (`libraryDateAfter`).

**✅ R8-13 P2 · Two selection bars that grew apart.**
- *What:* the library's selection (`library/selection/selection_bar.dart`)
  is a floating panel holding "3 selected", Select all and four labelled
  actions without ellipses ("Move", "Export").
- The page overview (`documents/overview/overview_selection.dart:99-150`)
  puts "2 selected" in a top bar and a docked bottom bar with six actions,
  some with ellipses ("Move to…", "Template…", "Export…").
- Each label scales down on its own (`ui/labelled_action.dart:47`,
  `FittedBox`). On a 390-dp phone the labels end up in three sizes and
  touch each other ("DuplicateMove to…", `overview_select_phone_light.png`).
- *Fix:*
  - One selection bar component with one layout (DESIGN §6 "features
    never restyle them locally").
  - One label size: if the labels don't fit, drop all of them to icons
    with tooltips rather than shrinking some.
  - At most five actions on phones: Bookmark and Template go into a ⋯.

*Done (`fix/r8-library`):* one shared `ui/selection_bar.dart` (`SelectionBar`, `SelectionCommand`) for the library and the overview: a floating panel with ✕, the count, Select all and the commands; one row where it fits, else a second row where each command is as wide as its name needs. Names keep one size (no `FittedBox`): commands with an `overflow` rank go into ⋯ (overview: Template, Bookmark, Duplicate), and if that is not enough the bar shows glyphs with tooltips. Library labels gained their ellipses ("Move to folder…", "Export…"); the overview keeps its bar in selection mode (no separate selection app bar).

### Backup and Len files

✅ **R8-14 P1 · One damaged byte loses the whole restore.**
- *What:*
  - A blob whose hash doesn't match throws (`data/blob_store.dart:105`) and
    becomes `LenArchiveException.damaged`
    (`data/archive/len_archive_reader.dart:188-191`).
  - So does a single unparsable JSON line (`:229-230`), although the
    comment at `:214-216` says odd records are skipped.
  - The `catch` at `:160-166` then rolls back everything.
- *Why:* a backup exists for the bad day. One flipped bit in one PDF of
  a 5 GB backup gives back nothing.
- *Fix:* count a damaged blob as missing and an unparsable line as
  skipped, and carry on. The success message already reports both. Keep
  the rollback for Cancel and for errors that aren't about the file.
- *Done (`fix/r8-data`):* a damaged blob counts as missing, a bad line as
  skipped, an unreadable records part is skipped whole and a damaged
  `blobs.json` falls back to the blobs in the zip. A complete import says so
  in a snack; one with gaps opens one dialog ("Restored, with gaps": what
  was left out) with Details listing the damage (`restore_dialogs.dart`).

✅ **R8-15 P1 · Restoring on a new device nests the library, and the
destination depends on where you start.**
- *What:* every library restore goes into a new "Backup 13 Oct 2026"
  folder (`features/backup/len_file_flows.dart:112-113`,
  `data/archive/len_import_commit.dart:310-327`), even into an empty
  library, which is the main restore case.
- From the library's "Import Len file…", a backup lands *inside the open
  folder* (`library/library_actions.dart:141-143`). From Settings it lands
  at the top level.
- *Fix:* into an empty library, restore at the top level as it was
  (`folderName: null`). Otherwise put the backup folder at the top level,
  whatever the entry point.
- *Done (`fix/r8-data`), lead decisions:* into an empty library a backup
  comes back at the top level with its folders; otherwise into "Backup 13
  Oct 2026" at the top level. What the file is decides where it goes: a
  notebook or folder Len file lands in the library's open folder wherever
  the import started (`LenArchives.openFolder`, set by the library).

✅ **R8-16 P1 · A restore has no confirmation, no Undo, and duplicates
everywhere.**
- *What:* "Restore from backup…" goes from the file picker straight into
  the import (`settings/backup_settings.dart:77`). The success snack has
  no action (`len_file_flows.dart:120`).
- Everything is marked dirty and syncs (`len_import_commit.dart:356`).
  Restoring twice makes two identical folders, with the same name if
  both backups are from the same day (`len_file_flows.dart:135-136`).
- *Fix:*
  - After `LenArchiveReader.open` has read the manifest, confirm in an
    `AppDialog`: "Restore the backup from 13 Oct 2026, 14:05? Its 42
    notebooks are added as copies; nothing here is replaced." With sync
    on, add "They sync to your other devices too."
  - Offer Undo in the snack (delete the folder it made, like the
    library's undoable deletes).
  - Add the time to the folder name when the name is taken.
- *Done (`fix/r8-data`):* `confirmRestore` asks first (date, count, where it
  goes, nothing replaced, syncs). A restore keeps the ids of what isn't here
  (`LenRemap.keep`), so restoring again finds the notebooks already here
  (`LenArchives.present`) and offers "Skip those" or "Restore all" (as
  copies); skipping everything makes no empty folder. Undo (snack, or the
  gaps dialog) puts the restored notebooks in the Trash and removes its
  folders (`undoRestore`). The folder name gets the time when taken.

✅ **R8-17 P1 · The web builds the whole backup in memory.**
- *What:* `platform/len_file_io_web.dart:96-103` writes into an
  `OutputMemoryStream` and hands `getBytes()` to the download. Blobs are
  read whole (`data/archive/len_archive_writer.dart:124-127`). Import
  reads the whole file into memory too (`len_file_io_web.dart:85-86`).
- *Why:* Storage settings tells web users to back up
  (`settings/storage_settings.dart:89`). A few hundred MB of PDFs crashes
  the tab during "Backing up", with no explanation.
- *Fix:* stream to `showSaveFilePicker` where the browser has it.
  Otherwise add up the blob sizes first, and above about 500 MB say so
  and suggest backing up folders one by one, or sync.
- *Done (`fix/r8-data`):* browsers with `showSaveFilePicker` ask where first
  and stream into the file (`ChunkedOutput`, awaiting each write between
  steps); others build a blob of 4 MB chunks (the browser may keep it on
  disk) and, above 500 MB of files, ask first with the size, pointing to
  per-folder export or sync. Import still reads the file into memory on the
  web.
  *Then (`fix/r8-followups`):* imports and restores in a browser read the
  picked file in slices (`Blob.slice`): `RangedZip` loads the zip's
  structure (directory, headers), then each entry as it is read, blobs 1 MB
  at a time (`data/archive/ranged_input.dart`), so a big backup is never in
  memory whole. On the way: reading a backup's contents (for the restore
  question) closed its record parts, so a restore from a file on disk then
  imported no records; parts are now read without being kept or closed.

✅ **R8-18 P2 · Desktop writes the backup, then asks where to save it.**
- *What:* `createLenFileOutput` writes to a temporary folder
  (`platform/len_file_io_native.dart:30-41`). Only afterwards does
  `saveOrShareFile` ask for a location and copy the file
  (`platform/file_export_native.dart:137-145`).
- *Why:* minutes of work, then a save dialog. Cancelling it throws the
  work away, and the disk briefly holds twice the size.
- *Fix:* on desktop, ask first and write straight to the chosen path.
- *Done (`fix/r8-data`):* asks first, writes `<path>.part`, renames when done.

✅ **R8-19 P2 · Writing a big library freezes the UI.**
- *What:* `ResolvedScope._estimate` runs synchronous `COUNT(*)` queries
  per notebook and per page before the first `await`
  (`data/archive/len_scope.dart:105-150`). `ZipEncoder.add` is
  synchronous and reads each blob twice (`len_archive_writer.dart:130`).
- *Why:* the progress dialog and its Cancel stop responding, and Android
  risks showing "app not responding".
- *Fix:* a few aggregate queries (`… WHERE surface_id IN (SELECT id FROM
  pages WHERE notebook_id IN …)`), and yield between blobs (or write in
  an isolate on native).
- *Done (`fix/r8-data`):* the estimate is a few aggregate queries per 500
  notebooks; the writer yields between blobs. (Blobs are still hashed by
  `ZipEncoder.add` synchronously, one at a time.)
  *Then (`fix/r8-followups`):* natively, each blob file is checksummed
  (CRC-32) in a worker isolate first and handed to the encoder as stored with
  its checksum, so the UI thread only copies it (`fileCrc32`); browsers keep
  checksumming as they write (their blobs are in memory one at a time anyway).

✅ **R8-20 P2 · Backup, restore and Len export each have several names.**
- *What:*
  - A restore shows "Importing…", then "Couldn’t import …" / "Import
    failed", and only success says "Restored" (`len_file_flows.dart:103,
    125,129,146`).
  - A failed backup says "Couldn’t export “Len backup 2026-10-13.len”" /
    "Export failed" (`:85`, `documents/export/export_messages.dart:47,51`).
  - The folder menu says "Export as Len file…" while the notebook menu
    says "Export…" (`library/library_menus.dart:63,79`). The format
    segment says "Len" (`export_sheet_sections.dart:92`).
  - The backup file is "Len backup 2026-10-13", but it is restored into
    "Backup 13 Oct 2026".
  - Opening an unsupported file says "Len opens PDFs and images", leaving
    out Len files (`documents/import/import_router.dart:72-73`).
- *Fix:*
  - Library backups: "Backing up / Couldn’t back up your library / Backup
    failed".
  - Library restores: "Restoring / Couldn’t restore … / Restore failed".
  - "Export…" everywhere, and "Len file" in the format segment.
  - One date style in both names.
  - "Len opens PDFs, images and Len files".
- *Done (`fix/r8-data`):* all of the above; the backup file is "Len backup
  13 Oct 2026.len".

*Partly done (`fix/r8-library`):* the folder menu says "Export…" like the
notebook menu, and the format segment says "Len file" (names only at large
text, so it stays on one line). The backup, restore and import wording is
`fix/r8-data`'s.

✅ **R8-21 P2 · Import errors read backwards and don't say what to do.**
- *What:* `'${e.message}: couldn’t import $name'` (`len_file_flows.dart:125`;
  the messages are at `data/archive/len_format.dart:168,185`) gives "This
  file was made by a newer version of Len: couldn’t import “x.len”".
- *Fix:* lead with what failed and end with the remedy:
  - "Couldn’t import “x.len”: it was made by a newer Len. Update Len and
    try again."
  - "…: it isn’t a Len file, or it is damaged. Try the original file."
- *Done (`fix/r8-data`):* "Couldn’t import (restore) “x.len”: it was made by
  a newer Len. Update Len and try again", "…: it isn’t a Len file, or it is
  damaged. Try the original file".

✅ **R8-22 P2 · A partial backup counts as a whole one.**
- *What:* blobs not yet downloaded are skipped. The note says only "1 file
  wasn’t on this device yet" (`len_file_flows.dart:76`). Then
  `lastBackupAt` is set and the device-only notice is dismissed for good
  (`len_file_flows.dart:178`, `library/library_notice.dart:68`).
- *Fix:* "2 PDFs or recordings aren’t downloaded yet and aren’t in this
  backup". With sync configured, fetch them first
  (`SyncController.fetchBlob`).
- *Done (`fix/r8-data`):* the writer fetches missing blobs through sync first
  (stopping at the first failure, e.g. offline); what is still missing is
  said as "2 PDFs, images or recordings aren’t downloaded yet and aren’t in
  it". `lastBackupAt` is still set.
  *Then (`fix/r8-followups`):* only a complete backup sets `lastBackupAt`
  and dismisses the device-only notice; one with files missing is saved
  and says so, but the library keeps suggesting a backup.

✅ **R8-23 P2 · Library backups include the Trash, which a restore can then
purge at once.**
- *What:* the library scope takes every non-deleted notebook
  (`data/archive/len_scope.dart:56`), while folder scope skips trashed
  ones (`:46`). Remap keeps `trashedAt` (`data/archive/len_remap.dart:45`),
  so anything trashed more than 30 days before is purged on the next load
  (`data/notebook_repository.dart:163-171`).
- *Fix:* leave the Trash out of library backups (`trashed_at IS NULL`).
- *Done (`fix/r8-data`).*

### Pen and PDF

✅ **R8-24 P1 · Highlighted PDF text can't be selected with the pen.**
- *What:* the lasso treats a press as on text only when
  `!_hitsContent` (`ink/tools/lasso_tool.dart:123`). `_hitsContent`
  (`:223-226`) uses `ContentHitTest.strokeAt`, which counts highlighter
  strokes (`ink/tools/content_hit_test.dart:22-29`).
- So once a phrase is highlighted, by Highlight or by snapping, a tap
  selects the highlight stroke. A hold opens the canvas menu instead of
  selecting the word.
- *Why:* "highlight, then copy or link" is the core study flow, and it
  now needs a finger.
- *Fix:* ignore highlighter strokes in `_hitsContent` for the hold and
  drag paths. A plain tap may still pick the highlight, so recolour and
  delete keep working.
- *Done:* the lasso's "on text" test ignores highlighter strokes
  (`ContentHitTest.strokeAt(highlighter: false)`), so a tap, a hold or a
  drag on highlighted PDF text selects the text; ink written with the pen
  over it still wins. A highlight is selected with a lasso loop
  (`fix/r8-pen`).
  *Then (`fix/r8-followups`):* the text menu offers "Remove highlight" when
  the selection is (partly) highlighted: the highlighter strokes whose path
  crosses the selected lines go, as one undo step across pages
  (`pdf/pdf_highlight_removal.dart`); on a phone the menu shows two colour
  dots then, so it still fits. Highlight over several pages is one undo step
  too.

✅ **R8-25 P1 · A scribble erases along the whole stroke.**
- *What:* `ScribbleDetector` answers yes or no for the whole stroke
  (`ink/input/scribble_detector.dart:63-72`). At pen-up
  `ScribbleErase.erase` hands every point to `eraseScribbled`
  (`scribble_erase.dart:80`). Its area and crossings use the whole path
  (`ink/surface_model_editing.dart:73-91`).
- A stroke that travels, then zigzags, erases what the lead-in crossed.
- Quickly filling in a small outline (a checkbox, a bullet) makes an area
  that contains the outline, so the outline is erased.
- *Fix:* `detect` returns the matched window (first and last index), and
  only that sub-path erases. Skip strokes whose bounds enclose the window.
- *Done:* `ScribbleDetector.windows` gives the runs of passes that make
  a scribble, their outer passes cut to the span of the inner ones (and
  inner passes may be at most twice the median, so two scribbles joined by
  a line are two). Only those zigzags erase and preview
  (`ScribbleHits`). A stroke whose bounds hold a zigzag's (give or take
  20 %) with no ink in its middle is an outline being filled in, and
  stays. Tests: a lead-in, a run-on, a filled checkbox and a boxed word
  (`scribble_to_erase_test.dart`); the Ink Lab recordings still never
  scribble (`fix/r8-pen`).

✅ **R8-26 P1 · Gestures that change every stroke are hidden and never
taught.**
- *What:* "Hold to snap" and "Scribble to erase" live after "Reset feel",
  at the end of the Feel section, which starts collapsed
  (`features/editor/pen/pen_gestures.dart`, `pen/ink_options.dart:18,55`).
- Even expanded, they sit below the fold of a desktop-height popover
  (`popover_pen_feel_light.png`, 800 dp tall).
- No `EditorTip` mentions scribbling (`chrome/editor_tips.dart:111-135`),
  and neither does the eraser panel (`pen/eraser_options_panel.dart`).
- *Why:* scribble to erase was meant as the biggest daily saving for
  people with no side button, and they won't find it. Someone whose line
  snaps won't find the switch either.
- *Fix:*
  - A one-time tip "Scribble over ink to erase it", the second time
    someone without a side button picks the eraser.
  - One caption in the eraser panel: "Or scribble over ink with the pen".
  - See Simplify for their home.
- *Done (lead decision: one home):* "Hold to snap" and "Scribble to
  erase" are writing gestures in Settings → Writing, beside "Tap to undo
  and redo" (`AppPreferences`, mirrored into `ToolSettings`); the pen's
  Feel no longer has them. Each is taught once with a tip: hold to snap
  after a pen line or shape drawn by hand that it would have cleaned up,
  once the pen has rested 2 s (writing on puts it off); scribble to erase
  the second time the eraser is picked. The eraser panel says "Or
  scribble over ink with the pen" while it is on (`fix/r8-pen`).

✅ **R8-27 P2 · Text snapping hangs on "Hold to snap".**
- *What:* highlights snap to PDF text only while `holdToStraighten` is on
  (`ink/input/ink_drawing.dart:242`). Text snapping needs no hold.
- The highlighter's panel says nothing about it.
- The caption ends "highlights on PDF text snap to it", where "it" has no
  referent (`pen_gestures.dart:27-29`).
- `docs/ROADMAP.md:18` still says "hold to straighten".
- *Fix:* make text snapping unconditional (see Simplify), and shorten the
  caption to "Hold the pen still at the end of a stroke for a clean line
  or shape".
- *Done:* text snapping needs no hold (see R8-30 and Simplify); the
  Settings caption reads "Hold the pen still at the end of a stroke for a
  clean line or shape"; ROADMAP updated (`fix/r8-pen`).

✅ **R8-28 P2 · A snapped line can be erased as a scribble.**
- *What:* `_enabled` checks `!live.straightened`
  (`ink/input/scribble_erase.dart:142-143`). But `finish()` calls
  `live.finish()` first, which resets the flag (`ink/input/live_ink.dart:76`,
  `ink_drawing.dart:217-220`). The detector was fed every move before the
  snap.
- *Fix:* latch "not a scribble" in `ScribbleErase.add` once `straightened`
  is seen.
- *Done:* `ScribbleErase` latches "snapped" while the stroke goes on,
  and `InkDrawing` reads `straightened` before `LiveInk.finish` clears it
  (`fix/r8-pen`).

✅ **R8-29 P2 · Scribbling over a text box or image leaves a zigzag.**
- *What:* `scribbled` only looks at strokes
  (`ink/surface_model_editing.dart:86-91`). When it erases nothing, the
  scribble is committed as ink. Nothing dims, so there is no warning.
- *Fix:* when a recognised scribble lies mostly over an element and hits
  no ink, drop it and say "Scribble erases ink only". Over blank paper it
  stays ink, as now.
- *Done:* a recognised scribble that erases nothing and lies mostly
  (70 %) over text boxes or images is dropped, and the editor says
  "Scribble erases ink only" (`InkEvents.scribbleMissed`). Over blank
  paper it stays ink (`fix/r8-pen`).

✅ **R8-30 P2 · Underlines become highlights; turned pages are untested.**
- *What:* `_Line.holds` accepts points up to 0.85 line heights from the
  line's middle (`features/editor/pdf/pdf_highlight_snap.dart:30,154`).
  A highlighter underline drawn just below the letters snaps into a full
  highlight.
- The snap handles vertical lines (`_Line.vertical`), but
  `test/pdf_highlight_snap_test.dart` has no turned page. Only text
  selection is tested at 90°, 180° and 270° (`test/pdf_rotation_test.dart`).
- *Fix:* snap only when the stroke's middle is within about 0.35 line
  heights of the line's middle (or the stroke is at least half a line
  thick). Add the `rotatedPdf` cases to the snap test.
- *Done:* a line counts only when the stroke's middle lies within 0.35
  line heights of the line's middle on average, or within half the
  stroke's width (a wide stroke still covers it): an underline stays ink.
  `pdf_highlight_snap_test.dart` snaps along a real line on pages turned
  0°, 90°, 180° and 270° (`fix/r8-pen`).

✅ **R8-31 P2 · The highlight swatches announce "selected" and hide the
word.**
- *What:* `pdf_highlight_swatches.dart:51` passes `selected: i == 0`. In
  `ui/color_dot.dart:46-48` that becomes `Semantics(selected: true)`, so
  the swatch reads as "Highlight in yellow, selected", although it is an
  action.
- A highlighter glyph before the dots looks like a button but does
  nothing. "Highlight" is never written, even where there is room
  (`pdf_layer.dart:227`, `pdf_selection_*.png`).
- *Fix:* no selected semantics (and no ring: order shows the current
  colour). On wide windows the label "Highlight" replaces the glyph.
- *Done:* no ring and no selected state on the swatches (the order shows
  the current colour); windows wide enough for Copy's label say
  "Highlight" before the dots instead of the glyph, which screen readers
  skip (each dot says "Highlight in …"). `pdf_select_90.png` refreshed
  (`fix/r8-pen`).

✅ **R8-32 P2 · The scribble detector's per-move cost grows with the stroke.**
- *What:* every 4th kept point, `detect` re-scans the whole stroke
  (`ink/input/scribble_erase.dart:69,104`, `scribble_detector.dart:68`).
  Once a scribble is recognised, `_follow` copies all live points and
  re-runs `scribbled` against every candidate stroke (`:106-107`).
- *Why:* this is O(n²) over a long drawing stroke, on the input path.
- *Fix:* only the last 1.2 s can be a scribble (`maxDuration`), so keep a
  window of that and test only the segments added since the last
  `_follow` (the set only grows).
- *Done:* the detector looks every 4 points at the last 1.2 s only and
  keeps the zigzags it found; the preview asks the model again only when
  they grew, and only along them (`fix/r8-pen`).

✅ **R8-33 P2 · The Shapes caption points to a switch that may be off, in
template typography.**
- *What:* "Hold the pen still to snap a shape — Pen › Feel"
  (`features/editor/tools/shape_options_panel.dart:63`) shows even when
  hold to snap is off, and uses the "WORD — fragment" dash the taste bar
  calls a tell.
- *Fix:* "Hold the pen still to snap a shape (in the pen's options)".
  When the switch is off, say "Hold to snap is off in the pen's options".
- *Done:* "Hold the pen still to snap a shape (Settings → Writing)", or
  "Hold to snap is off in Settings → Writing" while it is (`fix/r8-pen`).

### Whole app

🟡 **R8-34 P2 · New surfaces have no screenshots.**
- *What:* nothing in `test/screenshots/` renders:
  - the move or copy picker;
  - "New notebook…";
  - backup progress and the restore result;
  - the scribble preview;
  - the Recent row inside a folder (hidden) or with trashed entries;
  - the notice on a short window without notebooks.
- *Why:* every round's drift was found in screenshots, and these surfaces
  will drift unseen.
- *Fix:* add them to `organise_screenshot_test.dart`,
  `app_surfaces3_screenshot_test.dart` and `toolbar_screenshot_test.dart`.
- *Partly done (pen, `fix/r8-pen`):* `toolbar_screenshot_test.dart`
  renders the scribble preview mid-stroke and the scribble tip
  (`scribble_preview_*`, `tip_scribble_*`); `pdf_screenshot_test.dart`
  a highlighter stroke snapped to PDF text on a tablet and a phone
  (`pdf_highlight_snapped_*`). The other surfaces belong to other
  branches.

*Partly done (`fix/r8-library`):* `organise_screenshot_test.dart` renders
Recent at its edges (`o_recent_*`: an empty library, all at the top level,
trashed entries, inside a folder, the sideways strip's menu, an empty
library sideways) and moving or copying from the editor (`o_page_menu_move_phone`,
`o_move_copy_only_phone`, `o_move_new_notebook_phone`; the overview's picker
was already in `overview_move_*`). Backup progress and the restore result
are `fix/r8-data`'s; the scribble preview `fix/r8-pen`'s.
*Since:* `app_surfaces3_screenshot_test.dart` renders the restore question
and result (`restore_confirm`, `restore_gaps`) and progress dialogs
(`s_import_progress_*`); `organise_screenshot_test.dart` "New notebook…".
Still unrendered: the notice on a short window without notebooks.

**✅ R8-35 P2 · Small drift from DESIGN.md.**
- *What:*
  - Off-grid paddings of 5 and 3 dp in the template gallery's Import tile
    (`documents/templates/template_gallery.dart:162,176`) and the paper
    row (`library/new_notebook/paper_row.dart:123,135`).
  - Warm greys (`#F3F3F0`, `#E4E4DF`, `#5F5F5A`) on the missing-PDF page
    (`features/editor/document/missing_pdf_painter.dart:19,25,41`), where
    §1 asks for true greys.
- The rest of the sweep was clean:
  - icons are all Sharp;
  - radii come from tokens (except two scaled or 1-dp cases);
  - the accent is used for state only;
  - there are no `·` chains.
- *Fix:* use `Gaps.xs` and `Gaps.xxs`, and true greys.
- *Partly done (PDF, `fix/r8-pen`):* the missing-PDF page uses true greys
  (`#F3F3F3`, `#E4E4E4`, Graphite `#5A5A5A`); `pdf_missing.png` refreshed.
  The off-grid paddings are left to the library branch.

*Done (`fix/r8-library`):* the template tiles, the gallery's Import tile and the paper row share `TemplateTile.ruleRoom` (`Gaps.xs`) and `pageRoom` (`Gaps.xxs`) instead of 5 and 3; the missing-PDF page paints with the light `Tones` (Board, Desk hatching, Graphite). Goldens `pdf_missing`, `template_picker*` refreshed.

### Simplify

- ✅ **Text snapping always on.** A highlight that runs ≥ 70 % along text
  lines (`pdf_highlight_snap.dart:26`) wants to be clean. Drop the
  `holdToStraighten` gate (`ink_drawing.dart:242`), and with it the
  coupling in R8-27.
- ✅ **One home for writing gestures.** Settings → Writing already holds
  "Draw with finger", "Side button" and "Tap to undo and redo"
  (`settings/writing_settings.dart`). "Hold to snap" and "Scribble to
  erase" are just as global, but sit in Pen › Feel after a per-pen reset.
  Lead decision to revisit R7-3: either move both to Settings → Writing
  (the pen panel keeps one caption), or lift them out of the collapsed
  Feel to the end of the pen popover. Both on by default, as now.
  *Done:* both in Settings → Writing (lead decision).
- ✅ **One import destination.** What the file is decides where it goes: a
  notebook or folder goes into the open folder, a backup goes to the top
  level (R8-15). Settings → Restore stays a shortcut to the same flow.
- ✅ **Len export for several notebooks.** The export sheet hides the Len
  format when several notebooks are selected (`export_sheet_sections.dart:64-66`).
  Offering it removes the folder menu's separate "Export as Len file…"
  (R8-20).
  *Done (`fix/r8-followups`):* the sheet always offers "Len file": several
  notebooks give one Len file of kind `notebooks` ("2 notebooks.len",
  imported into the open folder without their folders); a folder's
  "Export…" opens the same sheet (one PDF per notebook, PNGs, or the folder's
  Len file, "Whole folder, Len file").
- **One selection bar** for the library and the overview (R8-13).
- ✅ **Disable "Back up library…" in an empty library**, and make no empty
  "Backup …" folder when an import brings nothing.
- ✅ **Drop the ring on the first PDF highlight swatch** (R8-31).
- **Reuse `locationOf`** in the move or copy picker (R8-6) instead of
  `_locations`.
- Keep as is: no new settings are needed for any item above. Every fix is
  a default, a caption or a removal.


## Round 7 audit (`review/round7`)

Scope: what makes people stay with a handwriting app or leave it, measured
against GoodNotes 6 and Notewise (from working knowledge of both; exact
competitor behaviour may differ by version). Method: all 706 renders from
`test/screenshots/` (all suites passed), viewed as contact sheets and crops,
plus a walk through the code of the 100-times-a-day paths (tools, colours,
lasso, PDF text, pages, library, sync, data safety). Every item was checked
in the code; paths are under `app/lib/` unless noted. Round 6 items are
all fixed and not repeated.

Summary: the pen, lasso, text, planners, PDF and audio are at or above
the reference apps. Len loses users in other places. Getting back to
a notebook takes too many taps, nothing reopens what you were writing in,
pages can't leave their notebook, and nothing tells someone without a sync
server that their notes exist on one device only.

### Where Len stands vs GoodNotes 6 / Notewise

| Area | Len | Notes |
|---|---|---|
| Ink feel, pressure, latency path, palm rejection | **Better / on par** | Fitted pressure curve, wet ink, palm quiet window, automatic stylus mode with an "undo" snack |
| Tool switching on tablets | On par | One tap per tool, one tap per colour / width slot; S Pen button erases |
| Tool switching on phones | Slightly behind | Switcher plus one "previous" slot; see R7-2 |
| Colours and sizes | On par | 1–6 independent colour and width slots per ink; presets + HSV + saved colours |
| Eraser | On par | Whole stroke / partial / highlighter only; hover outline; scribble to erase (✅) |
| Lasso | **Better** | Tap or loop, move / resize / rotate, Style, convert to text, cut / copy across notebooks and pages, split-view drag |
| Shapes | On par, one gap | Hold to snap plus a Shape tool. **Missing:** fill |
| Text boxes | **Better** | Rich text, lists, checklists, rich paste from browsers / Word |
| Highlighter | On par | Behind ink, straight-line option; snaps to PDF text (✅) |
| Undo / redo | On par | Buttons, two- / three-finger taps, keyboard |
| Library, folders, favourites, trash | On par | Nested folders, drag and drop, Undo everywhere |
| Recent notebooks / reopen last | **Missing** | R7-6, R7-7 |
| Tags | Removed: fine | Folders, favourites and full-text search cover it (SIMPLIFY #45). Don't bring tags back unless users ask |
| Search | On par | Titles, text, PDF text, handwriting (recognised on Android, synced to the rest) |
| Templates and planners | **Better** | Date-aware linked planners in 19 languages, custom templates |
| Page management | On par, one gap | Overview, reorder, multi-select. **Missing:** move / copy pages to another notebook (R7-9) |
| PDF study | On par | Text select, highlight, copy, links, outline, vector export. Pen-only selection missing (R7-1) |
| Audio | **Better** | Ink replay, trims, markers per burst of writing, crash recovery, background recording |
| Export / share | On par, one gap | PDF / PNG with ranges, editable Len files (✅); not from the library (R7-8) |
| Sync | Different | Self-hosted only: great for the few with a server, absent for everyone else |
| Backup / data safety | On par (✅) | Settings → Backup: one Len file of everything, restore as copies; Android backup keeps the database (R7-12, R7-13) |
| Offline | **Better** | Local-first on every platform, including the web PWA |
| First run, empty states, feedback | On par | Calm empty states, stylus-detected snack, one-time tips |

What a heavy note-taker does 100 times a day, in taps (competitor
counts are approximate):

| Action | Len tablet | Len phone | GoodNotes 6 / Notewise |
|---|---|---|---|
| Change pen colour or width | 1 | 1 | 1 |
| Pen ↔ eraser | 0 (side button) or 1 | 0 or 1 (previous) | 0–1 |
| Pen → highlighter → pen | 2 | 3 (switcher, pick, previous) | 2 |
| Lasso, move, back to pen | 1 + loop + 1 | 2 + loop + 1 | 1 + loop + 1 |
| Recolour a selection | 2 (Style, swatch) | 2 | 2 |
| Highlight a line of PDF text with the pen | 1 + freehand stroke, or put the pen down: long-press, drag, Highlight | same | 1 + stroke |
| Add a page at the end | 1 | 1 | 1 |
| Get back to yesterday's lecture notebook | 1–3 (open its folder) | 2–4 (☰ or folder) | 1–2 (recents / reopens) |

### Top 10 (fix first)

1. R7-1 A pen can't select PDF text; only a finger long-press can.
2. ✅ R7-12 Without sync, nothing says notes live on this device only, and there is no way to back them up.
3. ✅ R7-13 Android Auto Backup is on but unconfigured: it silently stops past 25 MB and would clone the sync identity.
4. R7-6 No recent notebooks: notebooks in folders are always 1–3 taps away.
5. R7-7 Nothing reopens where you were writing after the app is killed or restarted.
6. R7-9 Pages can't be moved or copied to another notebook.
7. R7-8 Export / share only exists inside the editor.
8. R7-2 On phones the one "previous tool" slot goes to the eraser that the S Pen button already gives.
9. R7-3 "Hold to snap" changes every pen stroke but lives in the Shapes options.
10. R7-14 Phones show no sync status anywhere outside the drawer; the editor never shows a failing sync.

### Writing

✅ **R7-1 P1 · A pen can't select PDF text.** The text selection that Copy,
Highlight and link creation need starts only from the canvas long-press
menu (`features/editor/editor_gestures.dart:24`, `selectWordAt`). Long
presses are recognised only for a navigating finger with no pen nearby
(`ink/input/canvas_gestures.dart:50-53`, `eligible: navigates &&
!taps.isStylusNear`) or a right click. The lasso tip even says "long-press
PDF text" (`features/editor/chrome/editor_tips.dart:107-112`). A student
annotating slides with the S Pen has to put the pen down and use a finger,
then drag handles, then tap Highlight. *Fix:* with the lasso, a pen tap on
PDF text where no ink or element is hit selects the word, and a pen
press-and-drag that starts on text extends the selection (in
`LassoTool._tap`, `ink/tools/lasso_tool.dart:184-208`, fall back to
`PdfInteraction.selectWordAt` when `contentAt` finds nothing). Update the
tip to "Circle ink to select it; tap PDF text to select text". The bigger
win is the text-aware highlighter under Missing features.
*Done (`fix/r7-pen`):* with the lasso (any pointer), where no ink or
element is hit: a tap on PDF text selects the word, a held press selects it
and a drag extends it, and a quick open drag that circles no ink selects the
text it spans. Loops starting on text still lasso ink. Finger long-press is
unchanged. The tip says "…; tap PDF text to select it".

✅ **R7-2 P1 · Phones: the only quick tool slot goes to the eraser the S Pen
button already gives.** The phone bar is `[tool▾][previous]` plus the
strip (`features/editor/toolbar/tool_switcher.dart:97-150`).
`ToolSettings._previous` starts as the eraser and follows the last tool
(`ink/tool_settings.dart:47,60-63`). For an S Pen writer who erases with
the button, the slot shows the eraser, so pen → highlighter → pen costs
three taps (switcher, Highlighter, then previous) instead of two.
*Fix:* when a stylus is in use (`stylusOnly == true`) and the side button
erases (`penButtonAction == eraser`), skip the eraser when choosing
`previousTool`, and start it at the highlighter. Pen ↔ highlighter is
then one tap each way. No setting needed.
*Done (`fix/r7-pen`):* `ToolSettings.previousTool` skips the eraser while
`stylusOnly` and `penButtonErases` (kept in step with the preference).

✅ **R7-3 P2 · "Hold to snap shapes" changes every pen stroke but lives in the
Shapes options.** `ShapeOptionsPanel` holds the only switch for
`tools.holdToStraighten` (`features/editor/tools/shape_options_panel.dart:62-67`).
It applies to pen and highlighter strokes held for 600 ms
(`ink/input/hold_to_straighten.dart:29`). People who pause at the end of
a word get a straight line. They look for the cause in the pen's options
and never find it, because pen users don't open Shapes. *Fix:* move the
switch to the Pen's Feel section (`pen/pen_options_panel.dart`) and the
Highlighter's. Keep one caption line in Shapes ("Or hold the pen still at
the end of a stroke").
*Done (`fix/r7-pen`), lead decision:* one home, the pen's Feel only
(`pen/pen_gestures.dart`, after "Reset feel", which doesn't touch it). Shapes
says "Hold the pen still to snap a shape — Pen › Feel".

✅ **R7-4 P2 · PDF "Highlight" uses whatever colour the highlighter last
had.** `PdfInteraction.highlightSelection` takes
`tools.configOf(InkTool.highlighter).color`
(`features/editor/pdf/pdf_interaction.dart:238-254`). The selection pill
has a single Highlight button (`features/editor/pdf/pdf_layer.dart:244-246`).
Students colour-code (definitions yellow, examples green), and changing
the colour means switching to the highlighter, changing its slot, and
selecting again. *Fix:* replace the button with the highlighter's quick
colours as swatches in the pill (2–3 dots, the current one first). A tap
highlights in that colour. One undo, as now.
*Done (`fix/r7-pen`):* `PdfHighlightSwatches`, up to 3 quick colours after
a quiet highlighter glyph, the current one ringed; Copy loses its label on
phones so the row fits.

✅ **R7-5 P2 · The lasso's first-use tip covers the selection for 10 s.** The
tip stays for `visibleFor` (`features/editor/chrome/editor_tips.dart:45,
119`) even after the user has done what it says. In every
`e_convert_*`, `e_image_selected_*` and `e_shape_selected_*` render it sits
under the selection menu, above the bottom bar. *Fix:* dismiss
`EditorTip.lasso` when the first selection is made (listen to the
selection in `TipsController.followTools`) or the tool changes.
*Done (`fix/r7-pen`):* it goes with the first selection (ink, elements or
PDF text) or another tool, and isn't offered while something is selected.

### Organising and finding

✅ **R7-6 P1 · No recent notebooks.** The library shows the current folder
only (`features/library/library_controller.dart:206-219`,
`folderOf(n) == _folderId`). A student with a folder per course opens the
drawer or folder, then the notebook, several times a day. On phones that
is 2–4 taps from launch. Sorting by "Last edited" helps only inside one
folder. *Fix:* at the Library root (not in folders, not while searching),
add a "Recent" strip above the folders: the last 6 notebooks opened or
edited across all folders, as covers in one sideways-scrolling row (the
`FolderRow.strip` pattern), hidden while fewer than 2 notebooks live in
folders. No setting, no new section in the sidebar.
*Done:* a Recent row at the library root (`library/recent_row.dart`): the 8
notebooks opened lately (`WorkspaceMemory.recent`), as names with a small
cover and where they live on the covers' columns, ruled like the folder row
above which it sits; one line that scrolls sideways, the next name peeking
in. Hidden in folders, while searching or selecting and while none of them
lives in a folder. Short windows (a phone held sideways, one row of chrome)
have no room for the row: Recent is the first item of the folder strip
beside the title ("Recent, 3 notebooks"), listing them in a menu
(`RecentStripTile`, `fix/r7-followups`).

✅ **R7-7 P1 · Nothing reopens where you were writing.** `OpenNotebooks`
keeps tabs in memory only (`features/editor/tabs/open_notebooks.dart`, no
persistence). `EditorLifecycle` saves the page and zoom per notebook
(`features/editor/editor_lifecycle.dart:47-67`), not which notebooks were
open. Android kills a backgrounded app freely: after checking a message
mid-lecture, the student is back in the library, with tabs gone. *Fix:*
store the open tab ids, the active one and whether the editor was showing
(settings, on `OpenNotebooks` change and `onHide`). On a cold start where
the app was last left in the editor, open that workspace again (the
library stays underneath for Back). A user who backed out to the library
gets the library.
*Done:* `editor/tabs/workspace_memory.dart` keeps the tabs, the active one
and the split view (pane, fraction, the second pane's place) in settings
while the editor is shown (on every tab change, on hide and on window
close); pages and zoom per tab were already kept per notebook. The library
reopens them at launch; leaving the editor forgets them.

✅ **R7-8 P1 · Export / share only exists inside the editor.** The notebook
menu offers Open, Rename, Favourite, Duplicate, Move, Cover, Select, Trash
(`features/library/library_menus.dart:12-23`). The editor's top bar has no
export either; it is in ⋯ (`chrome/editor_more_menu.dart:92`). "Send
yesterday's notes to a classmate" means opening the notebook, ⋯, Export.
*Fix:* add "Export…" to the notebook menu and the selection bar, running
`exportFlow` with all pages (the same sheet; several notebooks give one
PDF each through the share path).
*Done:* Export… in the notebook menu and Export in the selection bar
(`documents/export/notebooks_export.dart`): one notebook gets the editor's
sheet with all its pages; several get the sheet without a page range and
one file per notebook (same-named ones kept apart), saved or shared together.

✅ **R7-9 P1 · Pages can't be moved or copied to another notebook.** The
overview's selection bar has Bookmark, Duplicate, Template, Export, Delete
(`features/documents/overview/page_commands.dart:8-33`). Nothing moves
pages between notebooks; lasso copy carries ink and elements but not the
page, its template or its PDF background. Splitting a term's notebook or
filing a page into the right course is impossible. *Fix:* "Move to…" and
"Copy to…" in the overview selection bar and the page menu, with the
notebook picker the link pickers already have (`editor/links/link_pickers.dart`)
plus "New notebook". Pages are appended; their backgrounds keep their blob
references. Moves are one Undo ("Moved 3 pages to “Physics” · Undo").
*Done:* Move to… in the overview's selection bar and the page menu opens a
notebook picker (recent first) with Move and Copy (`editor/document/
page_transfer_flow.dart`). `NotebookDuplicator.copyPages` copies pages,
content, links among them, their outline entries and the recordings their
ink was written during; a move deletes the originals. One history step, one
Undo. *Follow-ups (`fix/r7-followups`):* "New notebook…" heads the picker
(named first; made beside the source with its paper, paper colour and
cover, holding just the pages; Undo takes it away too). A move retargets
every live link to a moved page (from pages left behind or other notebooks)
at its copy, and Undo points them back (`ElementRepository.retargetLinks`).

### Studying and PDFs

✅ **R7-10 P2 · Lecture recordings are invisible outside the notebook.** Cards
and list rows show no sign of recordings (`features/library/notebook_card.dart`,
`notebook_list_tile.dart`). Recording titles aren't in the search index
(`data/search/*` indexes titles, folders, text boxes, PDF text,
handwriting). "Which lecture did I record?" means opening notebooks one by
one. *Fix:* a small mic glyph beside the page count on cards with
recordings ("12 pages · 2 recordings" in the list), and index recording
titles so a search for "Lecture 4" finds the notebook.
*Done:* a mic glyph leads the card caption, list rows say "2 recordings",
and the library search matches recording titles (in `LibraryController`,
not the full-text index).

✅ **R7-11 P2 · Export is two taps deep on every size.** Tablet and desktop
top bars have ← ⊞ title | tools | 🎤 ↶ ↷ ⋯ (`editor_tablet_light.png`;
nothing export-related in `chrome/editor_top_bar*.dart`). Sharing a page is
something students do daily. *Fix:* on wide bars (`ToolbarDock.inline`) add
a Share glyph (`Symbols.ios_share_sharp`) before ⋯ that opens the export
sheet. Phones keep it in ⋯.
*Closed without change (`fix/r10-open`):* round 9's simplicity inventory
(#15) keeps Export in ⋯ with Ctrl+E, and the library offers it on every
card, folder and selection (R7-8): a bar glyph would be a second home.

### Delight and trust

✅ **R7-12 P1 · Without sync, nothing says notes exist only on this device,
and there is no way to back them up.** With sync off, Settings says "Sync
is off" (`features/settings/sync_status_line.dart:29`) and the sidebar
"Sync off" (`ui/sync_status_button.dart:14`). The empty library offers
"Set up sync…" on first launch only (`library_empty_state.dart:80`). Only
the web's storage section mentions backups (`storage_settings.dart:89`).
Export makes PDFs, which can't be brought back as editable notebooks. A
lost or reset tablet loses a semester. *Fix now (copy only):* the
sidebar's sync-off caption reads "On this device only" and Settings → Sync
off says "Your notes are kept only on this device. Set up sync to keep a
copy on your server." *Then:* library backup (Missing features #1).
*Done:* the sidebar reads "On this device only", Settings → Sync "Sync is
off: your notes are only on this device", Settings → Backup explains how to
keep them (back up, or sync), and the library says so once when notebooks
are a day old and nothing was backed up (dismissable, with "Back up…").

✅ **R7-13 P1 · Android Auto Backup is on but unconfigured.**
`android/app/src/main/AndroidManifest.xml` sets neither `allowBackup` nor
`dataExtractionRules` / `fullBackupContent`, so Android backs up the whole
files directory. That holds `len.db`, `blobs/` (PDFs, images, audio) and
`recording/` (`platform/app_directory_native.dart`,
`blob_backend_native.dart:12`, `spool_storage_native.dart:12`). Past the
25 MB quota Android skips the backup entirely, without telling anyone; one
imported textbook is enough. When it does work, a restore brings back
`device_id` (stored in settings in the database,
`data/settings_repository.dart:11`), so a new phone would write as the old
one. *Fix:* backup rules that include only `len.db` (with its `-wal`) and
exclude `blobs/` and `recording/`. All ink and text then fit and come back
on a new phone, and PDFs come back through sync or show "PDF page
unavailable". On the first start after a restore (detect: the database
exists but a no-backup marker file doesn't), give the device a new id and
resync from scratch. Say so in Settings → Storage on Android: "Handwriting
and text are included in your Android backup; PDFs, images and audio are
not." *Done* as proposed (the line is in Settings → Backup); the marker
holds the device id (`data/install_identity.dart`).

✅ **R7-14 P2 · Phones show sync status only inside the drawer; the editor
never shows a failing sync.** `SyncStatusButton` is built only in the
sidebar (`features/library/library_sidebar.dart:145`). On phones the
sidebar is the drawer. `SyncAttention` speaks up only for a refused token
(`features/settings/sync_attention.dart:23-31`). A server that has been
unreachable for days goes unnoticed. *Fix:* on phones, show the cloud-alert
glyph in the library header while sync has failed for more than 15
minutes (tap: Settings → Sync). After 24 h of failures, show the
`SyncAttention` snack once ("Not synced since Monday · Settings").
*Done:* `settings/sync_alert_button.dart`: after 15 min of failures (or a
refused token) a cloud-alert glyph in the phone library's header and the
editor's bar opens Settings → Sync; the ☰ dot that lit at the first failure
is gone. After a day without a working sync `SyncAttention` says "Not
synced since …" once. The last success is kept across launches.

✅ **R7-15 P2 · ROADMAP still lists removed features.** "Customisable
toolbar … favourite pens … edit mode" and "synced favourite pens"
(`docs/ROADMAP.md:207-208,216`) were removed (SIMPLIFY #9, #10). *Done in
this branch:* the lines now describe the fixed toolbar.

### Missing features worth adding (value vs complexity; keep Len simple)

1. ✅ **Library backup and restore** (high value · M). Settings → Storage →
   "Back up…" writes one file (database + blobs, zipped) through the
   save / share path; "Restore from backup…" replaces the library after a
   confirmation, with a new device id. The same format exported per
   notebook ("Len notebook", from R7-8's Export) lets people hand editable
   notebooks to each other. Pairs with R7-13 for Android.
   *Done* as Len files (`.len`) in Settings → Backup, with one change:
   restoring adds copies into a folder named after the backup's date
   instead of replacing the library (nothing can be lost by a restore).
2. **Recent strip** (high · S): R7-6.
3. **Reopen where you left off** (high · S): R7-7.
4. **Move / copy pages to another notebook** (high · M): R7-9.
5. ✅ **Scribble to erase** (high · M; GoodNotes 6 has it). With the pen, a
   quick zigzag (≥ 3 sharp reversals within ~600 ms, small extent) over
   ink erases the strokes it crosses instead of drawing; one undo. It sits
   beside `HoldToStraighten` in `ink/input/`, with one switch in Pen →
   Feel next to hold to snap (R7-3). This is the biggest daily tap saving
   for writers without a side button (Windows pens, other styluses,
   fingers).
   *Done (`fix/r7-pen`):* stricter than proposed so writing never trips it:
   ≥ 6 passes (5 reversals) within 1.2 s, in a narrow band
   (`ink/input/scribble_detector.dart`); zero hits on the Ink Lab's real and
   simulated writing. Erases strokes mostly inside the scribble; over blank
   paper it stays ink. Pen only (not the highlighter); "Scribble to erase"
   in Pen › Feel, on by default. Follow-up: once recognised, the strokes it
   will erase dim (30 %, fading in over 100 ms) while the scribble goes on,
   and come back if it is cancelled; still one undo.
6. ✅ **Text-aware highlighter on PDFs** (high for students · M). A
   highlighter stroke whose length lies mostly over one or more lines of
   PDF text becomes the same snapped strokes `highlightSelection` makes
   (crisp, line-high, multi-line). With hold to snap off, nothing snaps.
   This removes R7-1's detour for the most common PDF action.
   *Done (`fix/r7-pen`):* `PdfHighlightSnap` (≥ 70 % of the stroke along
   text lines), whole words when more than half covered; one undo step; no
   new setting (hold to snap's caption mentions it).
7. **Shape fill** (medium · M). A fill colour for closed shapes (none /
   the stroke colour at 25 % / solid), in the Shape strip and lasso Style.
   It needs a synced stroke field.
8. **Background audio playback** (medium · M; ROADMAP ⬜). Review a
   lecture with the screen off.
9. **Document scan** (medium · M–L). Camera → edge-detected,
   perspective-corrected page for handouts and whiteboards. Insert → Take
   photo exists; this is the version students want.
10. **Zoom window** (medium on phones · L). Writing at phone scale is
    cramped. Only worth it after the above; not for tablets.

Not worth it for Len: AI summaries and chat, flashcards / study sets,
stickers and marketplace (removed), tags (removed), real-time
collaboration.

### Simplify

- **Toolbar docked / floating has two homes:** Settings → Writing
  (`features/settings/writing_settings.dart:87-98`) and ⋯ → View
  (`chrome/editor_more_menu.dart:176-181`). Keep it in View, where its
  effect is visible, and drop the Settings row.
- **"Switch back after erasing"** (`pen/eraser_options_panel.dart`) is
  covered by the side button (temporary eraser), the phone's previous-tool
  slot and the one-tap tablet bar. Candidate for removal, with the
  `autoDeselect` field. *Done (`fix/r7-pen`):* removed, setting and code.
- **Hold to snap** gets one home in the pen's Feel (R7-3), not a second
  switch.
- **Don't add new settings for R7-2, R7-6, R7-7 or R7-12:** each is a
  better default.


## Round 6 audit (`review/round6`)

Scope: the app after the Swiss-minimal redesign (DESIGN.md) and rounds 4–5.
Method: all 687 renders from `test/screenshots/` (phone 390×844, phone
sideways 844×390, tablet portrait and landscape, desktop; light, dark, 1.3×
and 2× text), viewed as contact sheets and cropped where something looked
off, plus a code walk of the core flows as a new user and as a daily S Pen
user. Every item was checked in the code; paths are under `app/lib/`.

Not repeated (`design/followups` is on them): 48-dp hit areas for popover
Reset/Custom and the sheet ✕, the split pane fading ink swatches, the
settings Handwriting/Sync structure, phone Cancel buttons in import dialogs,
the teal ∞ cover badge, the ⋯-menu switch overhang. Still-open round 5 items
(R5-11, R5-16, R5-17, R5-20, R5-21, R5-22, R5-30; all but R5-21 since
fixed) are not restated.
Harness artefacts aren't reported (the import question naming a notebook
while the library is shown; "Take photo" and Share on desktop renders).

No P0s: nothing is broken or loses data. The redesign reads as one app
now; what's left is mostly layout on short windows, a few seams between
pickers and dialogs, and commands that have no feedback or no Undo.

### Top 10 (fix first)

1. R6-1 Dragging a notebook onto a folder moves it silently, with no Undo.
2. R6-2 A phone held sideways gets tablet chrome: up to 140 dp of a 390-dp screen.
3. R6-3 A phone held sideways shows the library without a single notebook title.
4. R6-4 Tablet portrait with tabs: three chrome rows, the middle one nearly empty.
5. R6-5 Phones: Import PDF hides behind a long press on the FAB.
6. R6-6 Text colour and recolour open an HSV-first picker with a ragged 9 + 5 grid of 36-dp swatches.
7. R6-7 Rename, cover, favourite, folder edits and Duplicate in the library have no Undo.
8. R6-8 Wide task dialogs offer both ✕ and Cancel.
9. R6-9 Settings' three-way "Draw with" for a state that lasts until the first pen touch.
10. R6-10 Every quick notebook is called "Untitled notebook".

### Library and organising

✅ **R6-1 P1 · Dragging a notebook onto a folder moves it silently, with no
Undo.** `LibraryActions.drop` (`features/library/library_actions.dart:118-127`)
calls `controller.moveNotebook` and returns. The notebook disappears from the
grid with no message. The Move dialog path goes through `move()` (`:279-297`),
which says "Moved “X” to “Y”" and offers Undo. Folders dropped into folders
get no feedback either. A drop that misses by one tile loses a notebook into
the wrong folder. *Fix:* route notebook drops through `move(context, [id],
folderId)`. For folders, add a "Moved “School” into “Work” · Undo" snack
(`moveFolder` back to the old parent).
*Done:* notebook drops go through `move()` (same message and Undo);
folder drops say "Moved “School” to “Work”" with Undo; a drop where the
item already is does nothing.

✅ **R6-3 P1 · A phone held sideways shows no notebook titles.**
`library_phone_sideways_*`: four covers about 190 dp wide fill the 390-dp
height, the titles are below the fold, and the FAB sits on the fourth cover.
The column count depends only on width (`CoverGridDelegate.columnsFor`,
`features/library/library_content.dart:58,317-318`; `coverWidth = 150`, at
least two columns). *Fix:* cap the cover height on short windows. When
`Breakpoints.libraryCompact` is true because of height, take `coverWidth`
from the height (a cover plus its caption at most about 60 % of the
viewport, so about 110 dp at 390), which gives six columns with titles in
view. Alternative: switch to the list view below `shortHeight`.
*Done:* `CoverGridDelegate.columnsFor` (now `cover_grid.dart`) adds
columns until a cover and its caption take at most 60 % of the viewport's
height (never narrower than 96 dp); the folder row follows the same
columns. Sideways: seven covers about 100 dp wide, titles in view. Card
titles break only between words; a word too long for the line ends in
"…" on one line.
*Then (`fix/followups-r6`):* header and folder row took ~170 of the 390 dp.
Short windows (`Breakpoints.short`) now have one row of chrome: ☰, the
title as a heading with its caption, a hairline, the folders as a strip
that scrolls sideways (`FolderRow.strip`; its own row while searching), 🔍
⇅; one hairline under it (~60 dp). The grid sizes a row to the room under
that chrome (`precedingScrollExtent`), so covers are ~150 dp wide (five
columns, was seven at ~100). A card's ⋯ glyph sits flush with the cover's
edge, level with the title's first line, and the title leaves it 24 dp
(was 40; its 48-dp target overlaps the title's end). Checked by
`accessibility_test` at 844×390 (library, editor states, 2× text).

✅ **R6-5 P1 · Phones: Import PDF hides behind a long press on the FAB.**
After the first notebook, phones offer importing a PDF only through a long
press on the FAB (`features/library/library_screen.dart:281-305`,
`onLongPressHint: 'More: canvas, PDF, folder'`). The empty state shows
"Import PDF…" once (`library_empty_state.dart:73-79`), and wide screens have
⊕▾. On Android you can also share a PDF to Len, but you can't find it from
inside the app. *Fix:* put the source into the New notebook sheet, the one
place phones go to create: Notebook | Canvas | PDF… as the segmented control
(`new_notebook_sheet.dart`), with PDF… opening the file picker. Keep the
long press as a shortcut.
*Done:* where the library is compact (no ⊕▾), the New notebook sheet has a
quiet "Import PDF…" under Notebook / Canvas; it closes the sheet and opens
the file picker. Chosen over a third segment (a segment that opens a
picker isn't a choice of kind) and over a menu on ⊕ (an extra tap on the
most frequent command). One home per width: ⊕▾ when wide, the sheet when
compact; the empty state's button and the long press stay as shortcuts.

✅ **R6-7 P2 · Library edits without Undo.** Rename, cover, favourite and
folder edits write straight away (`library_actions.dart:154-172, 204-214`).
Duplicate shows a plain toast (`:173-175`). Trash, move and folder delete
already offer Undo. CONVENTIONS says every visible edit is undoable, and a
cover change or a mis-tapped favourite is the kind of edit you want back.
*Fix:* reuse the move pattern: remember the old `Notebook`/`Folder` and show
"Cover changed · Undo", "Renamed to “X” · Undo" and "Duplicated as “X” ·
Undo" (Undo trashes the copy).
*Done:* rename, cover, favourite (menu, list star, sidebar drop, selection
bar) and folder edits say what changed with Undo (Undo puts back only the
field that changed); Duplicate's Undo trashes the copy. Favouriting a
selection ends it, like move and trash, so the message takes the bar's
place.

✅ **R6-10 P2 · Every quick notebook is "Untitled notebook".** An empty title
becomes `'Untitled notebook'` or `'Untitled canvas'`
(`features/library/new_notebook_sheet.dart:101,113`). A week of quick lecture
notes then fills the grid with identical names, and library search can't
tell them apart. *Fix:* default to the date, as a planner does ("Notes 13
October", or "13 October" for a canvas), and number repeats on the same
day ("13 October 2").
*Done:* an empty title becomes the day in the device's date format
("13 October", "October 13", "13. Oktober"; `intl` via the planner
languages), for notebooks and canvases alike (the cover shows the kind),
with no English word in front; a taken title is numbered "13 October (2)"
(a bare "2" read like part of the date). The field's hint shows it.

✅ **R6-11 P2 · The favourite star is amber chrome on a white plate.**
`_FavoriteBadge` (`features/library/notebook_cover.dart:163-178`) draws a
`Palette.favourite` (`#F5A524`, `ui/app_theme.dart:208`) star on a paper
square. The list tile also tints the star amber (`notebook_list_tile.dart:149`).
DESIGN §1 allows no orange in chrome, and this badge has the same "sticker"
look as the ∞ badge being fixed on `design/followups`. *Fix:* give it the
same treatment as the ∞ badge (an Ink filled star, no plate, or a paper
label), and use `onSurface` in the list.
*Done:* the badge is the ∞ tag's twin (paper plate, Rule-ish edge, filled
light-Ink star); the list's star is `onSurface`; `Palette.favourite` is
gone.

✅ **R6-12 P2 · Library selection bar: bare icons; the overview's has labels.**
`LibrarySelectionBar` is icon-only (select all, ☆, folder, 🗑, with tooltips;
`features/library/selection/selection_bar.dart:35-44`).
The overview's `SelectionBar` puts a label under each icon (Bookmark,
Duplicate, Delete; `features/documents/overview/overview_parts.dart:38-50`).
On touch, tooltips need a long press, so "☆" (favourite or unfavourite?) and
the folder glyph (move? new folder?) are guesses. *Fix:* one selection bar
pattern: labelled actions on touch (Favourite, Move, Trash; Restore and
Delete in the trash), icons only with a pointer.
*Done:* one pattern, `ui/labelled_action.dart` (`LabelledAction`), in both
bars: every command named under its glyph (Favourite / Unfavourite, Move,
Trash; Restore, Delete), with pointer and touch alike; the long names stay
as tooltips. Select all is a quiet text button by the count, as in the
overview. Narrower than 520 dp (phones) the commands take a second row.

✅ **R6-13 P2 · The library's "View" button looks like Sort and holds
Select.** The header's menu uses `Symbols.swap_vert_sharp` with the tooltip
"View" and holds Sort by, Show as and Select
(`features/library/library_header.dart:410-439`). The glyph promises sorting
only, so grid/list and multi-select are hard to find on phones. *Fix:* a
neutral glyph (`tune` or `view_agenda`) and the label "View". Multi-select
already starts with a long press then Select. Consider dropping "Select" from
this menu once the context menu's Select is the documented way (one home).
*Done:* the glyph is `tune` (tooltip "View"). Select stays in View: on
phones it is the only visible way into multi-select.

### Editor chrome

✅ **R6-2 P1 · A phone held sideways gets tablet chrome.** Dock and tab strip
are chosen by width only: `dockFor` (`features/editor/editor_chrome_host.dart:50-59`)
returns `row` at 844 dp (two rows: bar 52 + tools 48), and `showsStrip`
(`chrome/editor_top_bar.dart:84-86`) adds the 40-dp tab strip with two or
more notebooks open. That is 140 dp plus the status bar on a 390-dp screen,
over a third of the height, just when you turn the phone to write wider.
The library already treats short windows as compact (`Breakpoints.libraryCompact`).
No screenshot covers it. *Fix:* below `Breakpoints.shortHeight` use one row:
the inline dock (tools centred; `fitsOneRow` with the title dropped first)
and no tab strip (tabs move to ⋯ → Open notebooks, as on phones). Add
`editor_phone_sideways` renders.
*Done (`fix/r6-editor`):* below `Breakpoints.shortHeight` the dock is
`ToolbarDock.slim`: one 52-dp row with ← ▦, the title when it has room, the
phone's switcher, previous tool and quick controls, then ↶ (↷) ⋯; no tab
strip (tabs and audio in ⋯; recording controls dock at the bottom as on
phones). Wide short windows whose full tools fit keep the inline bar.
Renders: `editor_phone_sideways_*`.

✅ **R6-4 P1 · Tablet portrait with tabs: three chrome rows.**
`e_tabs_tablet_portrait_*`: tab strip (40), then a bar that hides its title
(`showTitle: !strip || split`, `chrome/editor_top_bar.dart:132`) and keeps only
← ▦ on the left and 🎙 ↶ ↷ ⋯ on the right, then the tool row (48). About
52 dp of a 1280-dp-tall tablet is an almost empty row. *Fix:* when the strip
shows and the dock is `row`, drop the middle bar. Put ← ▦ at the start of
the tool row and 🎙 ↶ ↷ ⋯ at its end (the row is centred and has room at
800 dp), or put them at the ends of the tab strip.
*Done (`fix/r6-editor`):* the tool row has no room for them at 800 dp on
touch, so ← ▦ and 🎙 ↶ ↷ ⋯ sit at the ends of the tab strip (52 dp) over
the tool row: two rows, 100 dp. The active tab names the notebook (double
tap renames). Split views keep both bars, which name each pane.

✅ **R6-14 P2 · Gesture undo is never taught.** Tap to undo (two fingers) and
redo (three) are on by default, but the only tip is the side button
(`features/editor/chrome/editor_tips.dart:12-15`). The gestures are described
only in Settings ("Two fingers undo, three redo"). A daily S Pen user keeps
reaching for ↶ at the top of a phone, the farthest point from the bottom
tool row. *Fix:* a second tip, offered after the third ↶ tap on a touch
device: "Tap with two fingers to undo, three to redo". Same
`TipsController`, once per device.
*Done (`fix/r6-editor`):* `EditorTip.gestureUndo`, offered on the third ↶
tap in an editor on a touch-first device with finger-tap undo on
(`TipsController.undoTapped`); once per device, never with a pointer.

### Pens, colours, tools

✅ **R6-6 P2 · Text colour and recolour open a different, cramped picker.**
The text bar's colour (`features/editor/tools/text_format_bar.dart:214-230`)
and the selection's recolour (`tools/selection_style_panel.dart`) go through
`pickColour` → `pickColor`, the generic `ColorPicker`. It leads with the HSV
square, hue band and hex field (`ui/color_picker/color_picker.dart:95-140`),
and its palette is a `Wrap` of dots clamped to 36 dp
(`_SwatchGrid`, `:209-235`). That's 9 + 5 per row on a phone (`e_text_colour_phone_*`),
with 36-dp targets. The ink popovers show the palette first, 2 × 7 with
48-dp cells on touch, plus Recent and a Custom disclosure (R5-2). Changing a
text colour is the frequent case, and a custom colour the rare one. *Fix:*
build `pickColor` on the ink popovers' `ColorChoices` (palette, Recent,
Custom ▸ HSV), laid out with `EvenGrid`. One colour picker everywhere.
*Done (`fix/r6-pickers`):* `pickColor` is `ColorChoices` in a popover
(touch width as the tool popovers); the lasso Style panel embeds
`ColorChoices` itself (a custom colour applies once it rests, one Undo
step); paper/pattern "Custom colour…" swatches open `pickCustomColor`
(square, hue, hex). The old picker's swatch grid and recent row are gone.

✅ **R6-15 P2 · "Hold to snap shapes" lives in three places, one of them
above a Reset that ignores it.** `HoldToSnapSwitch` is one global setting.
It shows in the pen's Feel (`features/editor/pen/pen_options_panel.dart:50`),
the highlighter's Feel (`highlighter_options_panel.dart:52`) and the Shapes
popover (`features/editor/editor_tools.dart:157`). In the pen popover it sits
right above "Reset feel" (`pen/ink_options.dart:102-114`), which resets only
the pen's own feel (`withFeelDefaults`), so the switch looks per-pen and
resettable but is neither. *Fix:* one home, the Shapes popover (where shapes
are). Or, if it stays in Feel for discoverability, move it out of the
disclosure into its own row under Size, so Reset feel covers exactly what's
above it.
*Done (`fix/r6-editor`):* one home, the Shapes popover (`ShapeOptionsPanel`,
under a rule); gone from the pen's and the highlighter's Feel, so Reset feel
covers only per-pen settings. *Superseded by R7-3 (`fix/r7-pen`):* the one
home is now the end of the pen's Feel, after "Reset feel" (`PenGestures`);
Shapes shows one caption pointing there.

✅ **R6-16 P2 · The lasso popover is three lines of hints.** Tapping the
active lasso opens a popover with no controls
(`features/editor/tools/lasso_options_panel.dart`): "Circle ink, text or
images…", "Drag to move them…", "To select PDF text, long-press it". Every
other popover is a place to change something, and you open this one again
and again by habit. *Fix:* show the hints once as a tip the first time the
lasso is picked, and either give the lasso a real option (GoodNotes-style:
what it selects: ink, images, text; or freeform/rectangle) or open nothing.
*Done (`fix/r6-editor`):* no popover; tapping the active lasso does nothing
(its tooltip still names it). The first time it is picked, a one-time tip
says "Circle ink, text or images to select them" (with "; long-press PDF
text" in notebooks with PDF pages). The tip's ✕ is a full touch target now.

### Pages, templates

✅ **R6-17 P2 · The overview's selection can't export or retemplate.**
`SelectionAction` is bookmark, duplicate, delete
(`features/documents/overview/overview_parts.dart:9`). To send three pages
to a classmate, a user notes their numbers, leaves the overview and types a
range into Export. The export sheet already takes custom pages
(`ExportRange.custom`, `features/documents/export/export_options.dart:17`),
and Change template already has "All pages". *Fix:* add Export… (opens the
export sheet with the selection as the custom range) and Change template…
(applied to the selection) to the bar, or behind a ⋯ in it.
*Done:* the bar is Bookmark, Duplicate, Template…, Export…, Delete.
Export… opens the export sheet at Page range with the selection filled in
("1-3, 5"; `initialPages`); Template… is Change template on the selected
pages (one undoable step, "All pages" still widens it). Bar labels scale
down rather than cut off on phones.

✅ **R6-18 P2 · The primary button names the same act two ways.** The template
picker says "Apply" in Change template and "Use template" in Canvas
background and when creating (`features/documents/template_picker.dart:231-233`).
Background… on a canvas is a change too. *Fix:* "Apply" for every change of
an existing page or canvas. "Use template" stays only where the picker
chooses for something not created yet (the new notebook's More…).
*Done (`fix/r6-editor`):* "Apply" for Change template and Canvas
background; "Use template" only when creating.

✅ **R6-19 P2 · Template filter chips repeat the gallery's headings and cut
mid-word on phones.** The chooser has search, a chip row (All, Paper,
Writing, Planners, My templates; `features/documents/templates/template_chooser.dart:213-245`)
and a gallery grouped under the same headings. On a 390-dp sheet the row
scrolls off as "My t" (`e_dialog_add_page_template_phone_*`,
`templates_picker_*`). *Fix:* see S3. Drop the chips, keep search, and let
the headings be the categories (jump links in the wide dialog's left column
if anything).
*Done (`fix/r6-editor`):* the chips are gone (and `templateSections`'
`only` filter); search plus the gallery's headings remain. No jump links.

### Dialogs, fields and copy

✅ **R6-8 P2 · Wide task dialogs offer both ✕ and Cancel.** On dialogs,
`SheetHeader(onClose:)` and `SheetActions(onCancel:)` both show: New folder
and Edit folder (`features/library/dialogs/folder_dialog.dart:91,121-124`),
Cover (`dialogs/cover_sheet.dart:71,91`), New notebook
(`library/new_notebook_sheet.dart:173`), and the template picker. DESIGN §6.3
draws the dialog without a ✕ (quiet Cancel, Ink primary); the ✕ belongs to
the phone sheet. *Fix:* `SheetHeader` shows its ✕ only when not `wide`.
*Done (`fix/r6-pickers`):* one rule, per caller (the header can't see the
footer): a dialog with Cancel has no ✕ (folder, new notebook, template
picker, Export without Save to device); dialogs without Cancel (Move,
Cover, shortcuts, languages) and every phone sheet keep it.

✅ **R6-20 P2 · Some fields carry a leading icon, most don't.** "Save as
template" puts `dashboard_customize` inside its field
(`ui/text_prompt.dart:75`, passed from
`features/documents/templates/user_templates.dart:148`), and the export page
range a numbered-list glyph (`documents/export/export_sheet_sections.dart:168`).
Rename, folder, sync and title fields have none, and R5-26 removed them from
sync. DESIGN §6 fields are rulings: label, value, rule. *Fix:* drop both
prefix icons and the `icon` parameter of `showTextPrompt`.

✅ **R6-21 P2 · Full stops and a heavy button in empty states; a toast with a
stop.** Single-sentence messages end in "." in the library's empty states
("Nothing matches “zzz”.", "Create a notebook to start writing, or import a
PDF to write on.", "Star notebooks you use often to find them here.";
`features/library/library_empty_state.dart:44-68`), the canvas hint
(`features/editor/canvas/canvas_empty_hint.dart:85`), and the toast "A
folder can’t be moved into itself." (`library_actions.dart:125`). "Clear
search" is an Ink `FilledButton` (`library_empty_state.dart:126-133`), the
loudest thing on an empty screen for the least important act. *Fix:* drop
the stops. Make Clear search a quiet `TextButton`. Extend
`test/copy_rules_test.dart` to the record/switch tuples and `_toast` calls
it misses today.
*Done:* the canvas hint lost its stops (`fix/r6-editor`); in the library,
no stops in its empty states or the folder toast; Clear search is a quiet
`TextButton`; `copy_rules_test` also reads `_toast` and
`showOverviewMessage`. Left: the record tuples, which the scanner can't
tell from non-UI literals.

✅ **R6-22 P2 · The trash's subtitle differs by width.** "Kept for 30 days" on
phones, "1 notebook, deleted forever after 30 days" on wide screens
(`features/library/library_header.dart:106-108`). The phone loses the count,
and the two sentences sound like different policies. *Fix:* one string, "1
notebook, deleted after 30 days" (short enough for 390 dp).
*Done* as proposed.

### Sync and settings

✅ **R6-9 P2 · Settings' "Draw with: Automatic / Stylus / Both" models a
passing state.** Automatic (`stylusOnly == null`) lasts until the first pen
contact. `_onStylusDetected` then sets Stylus and offers "Keep finger drawing"
(`features/editor/editor_screen.dart:322-340`). Meanwhile the ⋯ menu shows
the same preference as a switch, "Draw with finger"
(`chrome/editor_more_menu.dart:104-111`), and one round trip through it
leaves Automatic for good. So Settings carries a three-way control
(`features/settings/writing_settings.dart:41`) whose first option the user
can't usefully choose after day one, and the two homes disagree on its
shape. *Fix:* see S1. Settings shows the same "Draw with finger" switch, and
Automatic stays the unseen first-run default.
*Done (`fix/r6-pickers`):* Settings has the menu's switch (same visibility:
touch devices, or once a stylus was seen); its subtitle explains the
first-run behaviour ("Until a stylus touches the screen; then fingers pan
and zoom"). The side button shows on desktops once a stylus was seen.

✅ **R6-23 P2 · Setting up the second device means retyping a URL and a
token.** Sync setup is two text fields and Connect
(`features/settings/sync_settings.dart:220-280`). There is no link, code or
QR to carry the setup from a connected device (no such code in the app).
Typing a long access token with an S Pen on a tablet is the worst part of
setup. *Fix:* on a connected device, "Copy setup link" (a `len://sync?url=…&token=…`
link, also shown as a QR on wide screens). On a new device, "Paste setup
link" fills both fields, or opening the link does. The server stays the
same.
*Done (`fix/r6-pickers`):* Settings → Sync on a connected device has "Set
up another device…": a QR code of `len://sync?url=…&token=…` (pure-Dart
`qr`, painted in `ui/qr_code_view.dart`), Copy link, and a note that the
link holds the token. Pasting the link into Server URL fills both fields;
on Android the `len://sync` intent filter opens Len, which opens Settings
with the form filled (`IncomingFiles.syncSetup`). Connect stays the user's.
*Done (`fix/followups-r6`):* Linux and Windows too: `len "len://sync?…"`
(or a link opened from a browser: `x-scheme-handler/len`, the installer's
URL protocol), also forwarded to a running Len. A form filled from a link
says where links come from next time (Settings → Sync → Set up another
device… on a connected device), under Server URL.

### Simplify (one home per command; defaults over settings)

| # | Proposal | Why | Files |
|---|---|---|---|
| S1 ✅ | Settings "Draw with" becomes the "Draw with finger" switch (R6-9) | Automatic is a first-run state, not a choice; one control shape in both homes | `features/settings/writing_settings.dart`, `chrome/editor_more_menu.dart` |
| S2 ✅ | No ✕ on wide dialogs that have Cancel (R6-8) | Two exits on one form; DESIGN §6.3 | `ui/sheet_parts.dart` (`SheetHeader`) |
| S3 ✅ | Template chooser: drop the category chips (R6-19) | Search plus headings already filter; the chips repeat the headings and cut off on phones | `features/documents/templates/template_chooser.dart` |
| S4 ✅ | Folder delete: no confirm (or none for empty folders); the snack's Undo restores it | Trashing a notebook has no confirm and relies on Undo; deleting an empty folder asks "The folder is empty." (`library_actions.dart:241-252`) | `features/library/library_actions.dart` |
| S5 ✅ | Lasso: no hint popover (R6-16) | A popover with nothing to set | `features/editor/tools/lasso_options_panel.dart`, `editor_tools.dart` |
| S6 ✅ | "Hold to snap shapes" in one place (R6-15) | One global switch, three homes | `pen/pen_options_panel.dart`, `pen/highlighter_options_panel.dart`, `editor_tools.dart` |
| S7 ✅ | Cover: the colour applies on tap, Undo in a snack; no Apply/Cancel | The preview is the result; four taps for one colour | `features/library/dialogs/cover_sheet.dart`, `library_actions.dart:168-172` |
| S8 ✅ | `showTextPrompt` loses its `icon` parameter (R6-20) | One field style | `ui/text_prompt.dart` |
| S9 ✅ | One colour picker (R6-6): `pickColor` built on `ColorChoices` | Two pickers with different layouts, sizes and order | `ui/color_picker/` |

S4 done: "Delete folder" (no …) deletes at once; the message says what
went ("“Work” deleted, 1 notebook to the trash") and Undo restores all.

Kept on purpose: the long press on the FAB (it stays as a shortcut once
R6-5 lands), the toolbar pair in View ▸ and Settings (REDESIGN §2.1), and
Bookmark and Duplicate in the overview bar.

### What's good now

The redesign holds together across all 687 renders. Hairlines, Board/Sheet/Desk
steps, Ink primaries and the margin rule read the same in the library,
editor, dialogs and settings, in light and dark. Dark mode keeps paper
light, and the dark snack slab works over it. Large text reflows properly:
stacked segmented controls in Settings, stacked dialog actions, and the
search bar's second row. The phone bar's previous-tool button, the 2 × 7 pen
palette and the empty library's three covers are calm and clear. The
destructive confirms, ruled progress, the convert-to-text states and the
startup error screen are consistent and specific.

---

## Design review (`design/polish`, the Swiss-minimal redesign as a whole)

A design lead's last critique before showing the client: all 687 renders
from `test/screenshots/` (phone, phone sideways, tablet portrait and
landscape, desktop; light, dark, 1.3× and 2× text) checked against
`docs/DESIGN.md`. The areas had landed separately, so the review looked for
seams between them: radii, hairlines, type roles, accent misuse, grey
plates, Material leftovers and old tints. Fixed (details in DESIGN §9,
"Final polish"):

- Seams: three chip styles (Pencil edges, check glyph, borderless plate)
  became one; popover headings mixed Small label and Ink label, readouts and
  quiet buttons missed the right edge; sheets put their ✕ in three places;
  the current row was a grey plate in the outline and link picker but the
  margin rule elsewhere; radios were Graphite in menus and blue in export.
- Leftovers: grey plates (All templates, Add page, the new-notebook preview
  strip, the play button), a pill PDF selection bar, a blue wash on split
  drop targets, a blue-tinted desk and laser slab, an orange current search
  match, a round blue playhead, a circular spinner, rounded page miniatures,
  a monospace hex field, `·` in planner labels.
- Large text: template names broke mid-word; the editor search field shrank
  to four letters; durations split from their units.
- Layout: a phone held sideways got the desktop sidebar with one folder
  visible; stacked folders had no rules; Music staff previews were blank on
  phones; planner options previewed a crop of the month name.

Left (ranked): the inactive split pane fades ink swatches with its chrome;
settings' Handwriting section is a lone sentence without a row; the sync
explanation sits under Connect; import dialogs on phones stack an outlined
Cancel where other dialogs use a quiet one; the canvas ∞ badge is a
saturated plate on covers.

## Round 5 audit (`review/ux-round5`)

Scope: the app after the round 4 merges (navigation feel, editor chrome,
pen popovers with mm sizes, the highlighter palette and Reset with Undo,
library and dialogs, accessibility with 48-dp touch swatches, undo for page
edits, keyboard, export and sync feedback, web storage, the schema reset
notice and synced handwriting). Method: all 676 renders from
`test/screenshots/` (phone 390×844 @2x, tablet portrait and landscape,
desktop; light, dark, 1.3× text), each one opened, plus a code walk of the
main flows. Every item below was checked in the code. Compared against
GoodNotes 6, Notewise and Apple Notes.

Not repeated (other branches are working on them): the open library and
dialog items from round 4 (P1-13…P1-21, P2-16…P2-28, A11Y-1/2) on
`fix/library-r4`, and split-view titles and dimming, the focus puck and
desktop pointer mode on `fix/editor-followups` (✅ done there: both panes'
bars titled and both split notebooks marked in the tab strip, receding
content rather than whole bars; the puck moves clear of writing on release;
Space / Shift+Space type into a text box in focus mode; the overview's
"2 pages duplicated · Undo"; the player always leaves room for Add page;
desktop renders use a pointer). Harness artefacts aren't reported either:
screens pumped as the first route have no back button.

No P0s: nothing is broken or loses data. Paths are under `app/lib/`.

Status: ✅ fixed in `fix/r5-rest` · 🟡 partly fixed (the rest is visual, left to `design/foundation`) · ⬜ open. Pen and tools items: `fix/r5-pen-tools`.

**Round 5 fixes on `fix/r5-rest`** (functional and copy only; the visual
halves wait for `design/foundation`):
- R5-9/S11: phones show ↷ only after an undo. R5-10: one `PageCommand` glyph
  and label for both menus. R5-12: key hints by input (`Targets.touchFirst`)
  in ⋯ and the zoom menu. R5-13: `modifierLabel()` in the selection ⋯, list
  styles, format bar, undo/redo and ⊕▾ (the focus puck's tooltip is left to
  `fix/editor-followups`). R5-14: tips sit at the bottom and step aside for
  snacks.
- R5-18/S9: the field holds one reading and the chips the others; loading
  says "Recognising handwriting…"; no text or a failure keep the dialog
  with Try again and Close (the caller chose this over snacks); a minimum
  content height keeps the dialog steady. ✅ (`fix/r5-leftovers`) the
  selection pill steps aside while a dialog or sheet is open over it
  (`RouteOwners.dialogOpen`).
- R5-19: a converted reading shrinks (to 70 %) to keep the ink's line count
  before it wraps.
- R5-24/S7: "Basic" merged into "Paper" (the selected label's colour is
  visual, left). R5-26: "Connect", plain footnote (alignment left).
  R5-27/S8, R5-28: caption only where nothing recognises; status-only
  subtitle. R5-29: "The server didn’t accept the access token. Sync is
  paused", LEN_SYNC_TOKEN under Details. R5-31, R5-32: one "Couldn’t …"
  pattern, reasons under Details. R5-33: stops swept (also R5-8's hints),
  guarded by `test/copy_rules_test.dart`.
- S1–S3: ⋯ → Page is about this page (no Add page after / with template /
  to outline); one name per command. S10: "1 of 3" / "3 matches"
  everywhere. S12: Bring to front / Send to back only when something else
  overlaps the selected element.
- ✅ on `fix/r5-leftovers`: R5-15 (the first match, on open and when
  stepping, lands below the measured search bar; pages can scroll clear of
  it while it is open), R5-23 (page thumbnails and library previews keep
  dots and rulings: at least 1 px and a little more contrast when small;
  staves as grey bands), and the copy test now reads adjacent / multi-line
  literals and `showMessage` messages.
- Open: R5-21 (split drag, `fix/editor-followups`); visual items.

### Top 10 (fix first)

1. R5-1 The pen palette never shows the current colour (the defaults aren't in it).
2. R5-2 The phone pen sheet covers most of the screen; use a 14-colour, 7-column palette.
3. R5-4 Phones: pen ↔ eraser takes two taps each way.
4. R5-5 Reset in ink popovers wipes your quick colours, and its Undo vanishes with the popover.
5. R5-12 Shortcut hints show on touch tablets (menus gate them by width, not input).
6. R5-18 Convert to text: a duplicated reading, a bare spinner, and modal dead ends.
7. R5-19 Replaced text can grow over the next line of handwriting.
8. R5-26 Settings → Sync doesn't line up with the other cards.
9. R5-27 Handwriting settings without a recogniser: a row that isn't a control, and "Android" twice.
10. R5-30 The accent marks plain states (palette ring, active tab, template label, audio toggles).

### Pen and tools

✅ **R5-1 P1 · The pen palette never shows the current colour.** `phone_pen_sheet`,
`popover_pen_*`, `popover_from_slot_*`: no swatch has a ring, while the
highlighter, text and laser palettes do. The pen defaults
(`ink/pen/pen_defaults.dart:52`: `0xFF1A2233`, `0xFF1C4ED8`, `0xFFDC2626`)
aren't in `ColorSwatches.palette` (`0xFF1F2937`, `0xFF1C7ED6`, `0xFFE03131`).
So a new user sees no current colour, and picking the "same" black, blue or
red from the palette quietly swaps it for a near-twin. *Fix:* build the
palette around the defaults (put the three defaults in the palette, dropping
their near-twins) and add a test that every tool's default slot colours are
in its palette. *Files:* `ui/color_picker/color_swatches.dart`,
`ink/pen/pen_defaults.dart`.
*Done (fix/r5-pen-tools):* the palette is built around the defaults (pen, highlighter, text); a test keeps every default colour in its palette.

✅ **R5-2 P1 · The 4×5 touch palette makes the phone pen sheet cover most of the screen.**
`phone_pen_sheet`, `phone_highlighter_sheet_text13`: on touch the 20 pen
colours are now 4 rows of 48-dp cells (192 dp tall, against about 70 for the
old 2×10). The sheet starts 130 dp below the top of an 844-dp phone, so you
can't see the page you're tuning the pen for. The grid also sits to the left:
`maxSpacing: Gaps.lg` caps the gaps at 16, which leaves a 54-dp ragged gap
on the right that lines up with neither the slots, Custom nor the slider.
*Verdict:* 48-dp cells are right; four rows aren't. Twenty presets are too
many anyway: there are near-twins (black / `1F2937`, two greens, two light
blues), and Recent plus Custom cover the rest. *Fix:* a 14-colour palette in
7 columns, two rows of 48-dp cells on touch (96 dp, which fits the 358-dp
phone sheet: 7 × 48 = 336), and the same 2 × 7 at 32 dp with a pointer. Give
the tablet tool popover 7 cells' room on touch (`popoverWidth` 320 → 384, or
16-dp side padding). Spread the cells to the full width (no `maxSpacing` cap
on touch). The highlighter keeps its ten colours (2 × 5). Alternatives
considered: 2 × 10 small cells (fails the 48-dp rule); one row of family
heads that expands to shades (one more tap for every colour change); a
horizontally scrolling row (hides half the colours with no cue). *Files:*
`ui/color_picker/color_swatches.dart`, `ui/color_picker/color_choices.dart`,
`ui/adaptive_popover.dart`.
*Done:* 14 colours in 2 × 7, spread across the full width on touch (48-dp cells), the tool popover 368 dp wide on touch; the highlighter keeps 2 × 5.

✅ **R5-3 P2 · One sheet, two selection rings.** `phone_highlighter_sheet_text13`,
`popover_highlighter_*`: the quick slots ring the current colour in
`onSurface` (`pen/slot_button.dart:82`), but the palette below rings the
same colour in the accent (`ui/color_dot.dart:76`). The accent is for focus
and handles, and selected states are neutral (CONVENTIONS). *Fix:* use the
`onSurface` ring in `ColorDot` (covers palettes, covers and folder colours).
*Files:* `ui/color_dot.dart`.
*Done:* `ColorDot` rings in `onSurface`.

✅ **R5-4 P1 · Phones: switching pen ↔ eraser takes two taps each way.** The
phone bar is `[✎▾] | colours | sizes`, and every tool change goes through
the 4 × 2 switcher grid (`toolbar/tool_switcher.dart:43`). The pen's options
hide behind a long press on the switcher, or a tap on the active slot.
GoodNotes and Notewise phones switch tools in one tap. Finger users (no side
button) feel this on every correction. *Fix:* next to the switcher, a
48-dp button for the previous tool (`[✎▾][⌫]`): one tap swaps the two, so
pen ↔ eraser and pen ↔ highlighter become one tap. The bar has about 40 dp
spare with 3 + 3 slots; take the rest from the gap between the colour and
size groups. Hide the button when the slots need the room (5 + 5).
*Files:* `toolbar/tool_switcher.dart`, `editor_toolbar.dart`,
`ink/tool_settings.dart` (previous tool).
*Done:* a 48-dp previous-tool button beside the switcher (`PreviousToolButton`, `ToolSettings.previousTool`, the eraser at first); the slots give up to 4 dp of their cells for it (41 dp at 390), and it steps aside when they would go under 40 (narrow phones, 5 + 5).

✅ **R5-5 P1 · Reset in ink popovers is a big hammer with a short-lived Undo.**
`ResetButton` (`pen/option_controls.dart:186-237`) restores
`PenConfig.defaultsFor(ink)`: the quick colours you chose, their sizes, the
slot counts and Feel. Undo lives only in the button's `State`: closing the
popover (a tap on the page, which is the usual next move) loses it, and ↶
doesn't know about it. In the sheet, "Reset" sits where a title-bar Done
would. *Fix:* scope Reset to what you can't see at a glance: a "Reset feel"
inside Feel (pressure, stabiliser, ends). Quick colours and sizes are your
choices, not settings to reset. If the whole-tool Reset stays, keep the
pre-reset config on `ToolSettings` for the session so Undo survives closing.
*Files:* `pen/option_controls.dart`, `pen/ink_options.dart`,
`pen/pen_options_panel.dart`.
*Done:* "Reset feel" at the end of Feel; nothing resets the quick colours and sizes. Quick slots now edit only themselves (a colour slot: palette, Recent, Custom; a size slot: a size slider with a live preview); the full options open from the tool button only.

✅ **R5-6 P2 · Tool sizes use three units.** Pen and highlighter show mm
("0.66 mm"), the eraser and laser px (`pen/eraser_options_panel.dart:61`,
`tools/laser_options_panel.dart:73`, also the eraser slot tooltip), and text
a bare "24" (`tools/text_options_panel.dart:40`). Below 1 mm the pen shows
two decimals ("0.66 mm"), which reads as false precision next to GoodNotes'
steps. *Fix:* text "24 pt"; the eraser and laser sizes in mm too if they're
on the page, else no unit (a dot preview is enough); round sub-millimetre
sizes to 0.05 mm ("0.65 mm"). *Files:* the three panels, `pen/ink_slots.dart`
(`formatWidth`).
*Done:* sub-millimetre sizes round to 0.05 mm ("0.65 mm"); the eraser and laser sliders show no px (the eraser's dot shows the size; screen readers get a percentage); eraser slots read "Eraser size 1…3". Text keeps the bare "24": its unit is the page's 1/96 in, not pt, and the text bar shows the same number.

✅ **R5-7 P2 · The text popover differs from the ink popovers.** `popover_text_*`:
Size → Font → Colour, while pen and highlighter go Colour → Size. Font is a
row with a Material filled triangle (`tools/text/text_style_menus.dart:59`,
`arrow_drop_down_rounded`), which round 4 replaced with rounded chevrons
everywhere else; the audio split button (`audio/ui/audio_bar_button.dart:60`)
still has one too. *Fix:* Colour, then Size, then Font, as in the ink
popovers; `expand_more_rounded` for every drop-down affordance. *Files:*
`tools/text_options_panel.dart`, `tools/text/text_style_menus.dart`,
`features/audio/ui/audio_bar_button.dart`.
*Done:* Colour → Size → Font; `expand_more_rounded` in the font menu and the audio split button.

✅ **R5-8 P2 · Hints in tool popovers break the copy rule.** Single sentences
ending in a full stop: "Drag to draw, in the pen’s colour and size."
(`tools/shape_options_panel.dart:55`), "Tap the page to add a text box; tap a
text box to edit it." (`tools/text_options_panel.dart:60`), "To select PDF
text, long-press it." (`tools/lasso_options_panel.dart:23`). The stabiliser
hint already has none. *Fix:* drop the stops (see also R5-33).
*Done:* the three hints lose their full stops.

### Editor chrome and navigation

 **R5-9 P2 · The phone title gets about 120 dp.** `editor_phone_*`,
`e_bookmarked_phone_*`, `toolbar_text13_phone`: "Physics — Me…", and
"Lecture n…" at 1.3×. The bar is ← ▦ title ↶ ↷ ⋯ (five 48-dp targets), and
↷ is disabled nearly all the time. *Fix:* on phones show ↷ only while
there's something to redo (it appears after an undo, where the user is
looking anyway), and give the title the 48 dp. The full title stays in the
rename target's tooltip. *Files:* `chrome/editor_top_bar.dart`,
`chrome/undo_redo_buttons.dart`.

 **R5-10 P2 · "Add page after" has two glyphs.** In ⋯ → Page it uses
`vertical_align_bottom_rounded` (`documents/overview/page_commands.dart:9`),
which reads as "download" (`e_page_menu_*`). The canvas long-press menu uses
`add_rounded` (`editor_gestures.dart:75`). *Fix:* one glyph for the command
(`add_rounded`, or `note_add_rounded` as for "with template") from
`PageCommand.icon`, used by both menus. *Files:* `page_commands.dart`,
`editor_gestures.dart`.

**R5-11 P2 · Zoom menu labels are 6 dp out of line.** ✅ (the rows reserve `Glyphs.menu`) `e_zoom_menu_*`: the
50 / 100 / 200 % rows reserve `SizedBox(width: 24)` for the check
(`canvas/zoom_indicator.dart:127`), but the icons are 18 dp, so "Fit content"
and "Back to start" start 6 dp further left. *Fix:* reserve `Glyphs.menu`
(or the menu theme's icon size). *Files:* `canvas/zoom_indicator.dart`.

 **R5-12 P1 · Shortcut hints show on touch tablets.** `e_page_menu_tablet_*`
("Ctrl+F", "Ctrl+E", "Shift+1", "F11"), `e_zoom_menu_tablet_*`
("Shift+1", "Home"). The ⋯ menu gates them on `compact` (phone width,
`chrome/editor_more_menu.dart:213,226`) and the zoom menu on
`width >= compactWidth` (`canvas/zoom_indicator.dart:111`). CONVENTIONS says
targets go by input, not width, and `MenuRow` already hides hints when
`Targets.touchFirst`. An S Pen tablet without a keyboard shows four
meaningless key names. *Fix:* gate on `!Targets.touchFirst` in both places.
*Files:* `chrome/editor_more_menu.dart`, `canvas/zoom_indicator.dart`.

 **R5-13 P2 · "Ctrl" is hard-coded where `modifierLabel()` exists.** The
selection ⋯ (`tools/selection_menu.dart:136-142`), the list styles
(`tools/text/text_style_menus.dart:193-195`) and the tab shortcut in the
shortcuts sheet (`settings/keyboard_shortcuts.dart:65`) say "Ctrl+…" to a
Mac using the web app, while Settings says "⌘/". *Fix:* build the strings
with `modifierLabel()`. *Files:* as listed.

 **R5-14 P2 · One-time tips sit on the first lines of writing.**
`e_tip_pen_button_phone_*`: "Hold the pen’s side button to erase" is placed
under the HUD at the top of the canvas (`chrome/editor_chrome.dart:226`),
over the first written line, just when the user starts writing there.
*Fix:* show tips at the bottom, above the toolbar, through `MessageInsets`
(where snacks go), and queue them behind a showing snack (round 4 P2-26).
*Files:* `chrome/editor_tips.dart`, `chrome/editor_chrome.dart`.

**✅ R5-15 P2 · The in-notebook search bar covers the match on phones.**
`e_search_phone_light_folded`: the bar sits over the top of page 1, and the
first match ("Forces…") is under it. `e_search_phone_light_none`: "No
matches" cuts through a line of ink. The tablet pushes the page down only
after Next. *Fix:* inset the viewport by the bar's height while search is
open (or reveal the current match below it). *Files:*
`features/search/editor/editor_search_host.dart`,
`features/search/editor/editor_search_layer.dart`.

**R5-16 P2 · Search result rows are 36 dp tall on touch.** ✅ `_MatchTile`
(`features/search/editor/editor_search_bar.dart:259`): one line plus 8 dp
padding top and bottom. The "Page 3" label is `labelSmall` (bold overline)
pinned to the top, so it outweighs the snippet. *Fix:* rows at least
`Targets.menuRowHeight`; the location as `bodySmall`, aligned with the first
line's baseline. Add the search panel to `accessibility_test.dart`. *Files:*
`editor_search_bar.dart`.
*Done (`fix/r10-open`):* rows are at least `Targets.menuRowHeight`; the page
sits on the snippet's first line (`editor_search_results.dart`).

**R5-17 P2 · Recording: paused looks like recording, and dark mode shouts.** ✅ (the controls are flat in the bar; only the dot is red, grey while paused)
`e_audio_paused_tablet_*`: the pill stays red-tinted with a dimmed red dot,
and only the word "Paused" changes. `e_audio_recording_*_dark`: the deep red
fill is the loudest thing on screen, and the level meter is dark red on dark
red. *Fix:* paused → the neutral pill (`Surfaces.pressed`) with a pause
glyph; recording in dark → `errorContainer` at a lower tint, with meter
bars in `onErrorContainer` (now `scheme.error`, `audio_bar_button.dart:157`).
*Files:* `features/audio/ui/audio_bar_button.dart` (`RecordingPill`).

### Writing, selection, text, convert

 **R5-18 P1 · Convert to text shows the reading twice, has a bare spinner, and ends in modal dead ends.**
`e_convert_tablet_*`, `e_convert_phone_*`: the "Recognised text" field and
the first, ticked "Alternatives" chip say the same thing. The chips stack one
per line on a wide dialog. `e_convert_loading_*`: title, a small spinner and
Cancel, with no words. `e_convert_empty_*` / `e_convert_error_*`: a modal
whose only button is Close, for "No text was found in the selection." (full
stop). Each state also moves the dialog's top edge (578…670 px on phones),
and the selection pill peeks out above it. *Fix:* the field holds the best
reading, and the chips list only other readings (tap = put it in the field),
wrapped. Loading: a "Recognising…" row under the title. No text or a
failure: close the dialog and show a snack ("No handwriting found in the
selection", "Couldn’t read this handwriting · Try again"). Keep the dialog's
height across states, and hide the selection pill while a dialog is up.
*Files:* `editor/recognition/convert_to_text_dialog.dart`.

 **R5-19 P1 · Replaced text can grow over the next line.** `e_convert_*_replaced`:
one line of ink becomes a box two lines tall ("Newton’s second law: / F =
ma"). The font comes from the letter height and the box wraps at the ink's
width, so its bottom cuts through the next handwritten line. *Fix:* when
the text needs more lines than the ink had, shrink the font (down to a floor,
for example 70 %) until it fits the ink's height, and only then wrap.
*Files:* `ink/recognition/convert_to_text.dart` (`textBox`).

**R5-20 P2 · Text boxes have no inner padding.** ✅ (the frame sits 6 dp outside the text) `e_text_editing_*`,
`e_text_colour_*`: "Exam on Friday!" touches the selection frame, and the
caret sits on the right edge. *Fix:* draw the editing frame outset by
`Gaps.xs` (chrome only, so the text's layout and position don't change).
*Files:* `tools/text_box_editor.dart`.

**R5-21 P2 · Split view: dragging to copy makes the original slide away.**
`split_drag_*`: "Drop to copy here" shows on the target, but the source page
looks emptied: the selection moved with the pointer out of its pane, and a
zero-width frame with handles is stuck at the pane edge. *Fix:* once the
pointer leaves the source pane, snap the source preview back in place (or
ghost it at 40 %) and draw the moving copy only in the target. *Files:*
`ink/tools/lasso_tool.dart` (`dragOut`), `editor/split/split_drop_highlight.dart`.

### Pages, templates and overview

**R5-22 P2 · The outline's header and list don't share an edge on tablets.** ✅ (the outline column starts on the filter's margin)
`o_outline_panel_tablet_*`, `pdf_outline_tablet_*`: round 4 centred the
outline list in a 640-dp column (P2-14), but the title and the All /
Bookmarked / Outline control stay at the left edge, so nothing lines up and
a 300-px gutter opens on the left. *Fix:* put the header and the filter in
the same centred column on the Outline filter (or use one 960-dp column
for the whole screen). *Files:* `features/documents/overview/page_overview.dart`.

**✅ R5-23 P2 · Thumbnails of faint papers look blank.** `paper_dotted`,
`paper_gridSmall`, `paper_music` (the left thumbnail): the dots and fine
lines drop out at thumbnail size. College and narrow ruled keep only the
margin line. In the overview and the library, a dotted or small-grid page
looks like Blank. *Fix:* a minimum stroke width and alpha for pattern lines
when rendering below a scale (thumbnail pass). *Files:*
`domain/templates/*` (pattern painting), `features/editor/document/page_thumbnail.dart`.

 **R5-24 P2 · Template categories: "Basic" and "Paper" overlap.**
`templates_picker_tablet_all`: Basic holds Blank and Dotted, and Paper holds
the grids, isometric, music and storyboard. Dotted is a grid's sibling, and
two one-word categories for "plain papers" make you guess. The selected
tile's label turns blue and bold (`template_gallery.dart:245`), so "College
ruled" wraps while "Narrow ruled" doesn't. *Fix:* one "Paper" category
(blank, dotted, grids, music, storyboard; Writing and Planners stay). The
selected label stays `onSurface` (the ring and check carry the selection).
*Files:* `domain/templates/paper_style.dart`,
`features/documents/templates/template_gallery.dart`.

**R5-25 P2 · The planner's "More options" is a Material `ExpansionTile`.** ✅
`templates_*_planner`: its chevron, padding and type differ from Feel's
`OptionDisclosure` and the settings rows next to it. *Fix:* use
`OptionDisclosure` (moved to `ui/`) for both. *Files:*
`documents/templates/planner_options.dart:76`, `editor/pen/option_sections.dart`.
*Done (`fix/r10-open`):* `OptionDisclosure` lives in `ui/` and folds both.

### Settings, sync, handwriting

 **R5-26 P1 · Settings → Sync doesn't line up with the other cards.**
`s_settings_sync_*`, `settings2_*`, `settings_tall_*`: the "Sync is off" icon
and text sit about 15 dp right of every other row's icon and title columns.
The Server URL and Access token fields bring a third column (icons inside
filled fields), and the icons there are 24 dp against the rows' 20. "Connect
& save" uses an ampersand, and the footnote talks Docker. *Fix:* the status
as a standard settings row; fields without leading icons, inset to the title
column; "Connect"; footnote "Sync across your devices through your own Len
server", with the setup link in About or the README. *Files:*
`features/settings/sync_settings.dart`, `sync_status_line.dart`,
`settings_section.dart`.

 **R5-27 P1 · Handwriting where nothing recognises (new): a row that isn't a control, and "Android" twice.**
`s_settings_handwriting_phone_*` / `_tablet_*` (Linux, Windows, web): a
"Search handwriting" row with a search glyph says "Nothing recognised yet."
(with a full stop) and reads like a disabled switch. The footnote says
"recognised on Android devices running Len … Converting handwriting to text
works on Android." *Fix:* no row. One caption: "Handwriting written on
Android is recognised there and synced, so search finds it here", plus
"· 312 lines" once there are any. *Files:*
`features/settings/handwriting_settings.dart:41-61`.

 **R5-28 P2 · "Search handwriting" (Android) mixes a description with a status.**
`s_settings_handwriting_on_*`: "Recognises handwriting in the background
while you are not writing. Up to date: no handwriting yet." wraps to four
lines beside the switch at 1.3×. *Fix:* the subtitle is the status only ("Up
to date · 312 lines", "Recognising… 3 pages to go"), and the description
moves into the section's footnote, which already explains search.
*Files:* `handwriting_settings.dart:95-113`.

 **R5-29 P2 · The sync error is technical.** `f_sync_rejected_*`: "…check that
it matches LEN_SYNC_TOKEN. Sync is paused until you fix the token."
Users who set up a server know the variable, but the sentence is three
clauses long. On phones "Turn off sync…" wraps to its own line, indented
differently from "Sync now". *Fix:* "The server didn’t accept the access
token. Sync is paused" with Change…; the variable name goes under Details.
Lay the actions out in a `Wrap` with one start edge. *Files:*
`sync/sync_errors.dart`, `features/settings/sync_settings.dart`.

### Consistency and copy

**R5-30 P2 · The accent marks plain states.** ✅ Accent is for primary buttons,
focus, handles, links, switches, progress and the selected sidebar row.
It also shows on:
- ✅ the palette's selection ring (R5-3);
- the active tab's notebook glyph (`tabs/notebook_tab_strip.dart:196`);
- the selected template's label (`documents/templates/template_gallery.dart:245`);
- the audio "tap ink to play" toggle and a non-1× speed
  (`features/audio/ui/playback_bar.dart:129,187`);
- `AppDialog`'s icon disc, which defaults to the accent
  (`ui/app_dialogs.dart:92`): the progress dialog's decorative hourglass
  (`s_import_progress_*`, `features/documents/progress_dialog.dart:188`).

*Fix:* `onSurface` with `fill: 1` or the pressed plate, as for tools.
*Done (`fix/r10-open`):* tap-to-play on is the ink plate, a changed speed
reads in Ink, and `AppDialog`'s icon is Graphite. The active tab and the
selected template keep their 2-dp accent rule: that is the margin rule
(DESIGN §1.2), not a plain state.

 **R5-31 P2 · "Could not" and raw reasons in user templates.** `documents/templates/user_templates.dart:65`:
"Could not import x: <FormatException message>" (everywhere else says
"Couldn’t", and raw messages moved under Details in round 4). *Fix:*
"Couldn’t import “x”" with the reason under Details (`ui/error_details.dart`).
*Files:* `features/documents/templates/user_templates.dart`.

 **R5-32 P2 · Import messages disagree.** `s_import_failed_*` says "Couldn’t
open “scan.pdf”: it may be damaged, or not a PDF". `s_import_unsupported_*`
says "“Budget 2026.xlsx” can’t be opened: Len opens PDFs and images." (with a
full stop). *Fix:* one pattern, "Couldn’t open “Budget 2026.xlsx”: Len opens
PDFs and images". *Files:* `features/documents/import/import_router.dart:64-65`.

 **R5-33 P2 · Full-stop sweep.** Besides R5-8, R5-18 and R5-27, single
sentences that end in a stop: "One document with sharp, zoomable ink."
(`documents/export/export_sheet_sections.dart:82`), "No text was found in the selection." and "The
handwriting could not be recognised." (`convert_to_text_dialog.dart:216,223`),
and "Nothing recognised yet." (`handwriting_settings.dart:60`). In the
library (not in `fix/library-r4`'s list): "Select…" opens no question
(`library/library_header.dart:409`), so it gets no ellipsis. *Fix:* a test
that greps `Text('…')` literals for a single sentence ending in "." would
keep this from creeping back.

**R5-34 P2 · Dark mode: the HUD pill is light lavender.** ✅ (the HUD is the inverse slab with a Pencil edge, like snack bars, which are light in dark mode too) `e_hud_phone_dark`,
`e_hud_tablet_dark`: "Nothing to undo" is a pale pill, while the tip banner
and snacks are dark. Over cream paper it barely separates. *Fix:* the HUD on
`Surfaces.overlay` (dark in dark mode), like the other floating messages.
*Files:* `chrome/gesture_hud.dart`.

### Simplify (one home per command; defaults over settings)

| # | Proposal | Why | Files |
|---|---|---|---|
| ✅ S1 | ⋯ → Page drops "Add page after" and "Add page with template…" | Adding a page already has five homes: the Add page footer, Insert ⊕ → "Page with template…", the canvas long-press, the overview's Add page tile and its ⋯. Page ▸ goes from 8 rows to 6 and reads as "this page" | `chrome/editor_more_menu.dart` |
| ✅ S2 | ⋯ → Page drops "Add page to outline…" | The outline panel has "Add page N to outline", and the dialog names it differently ("…to the outline") | `editor_more_menu.dart`, `outline/outline_panel.dart` |
| ✅ S3 | One name per command: "Page with template…" (Insert) vs "Add page with template…" (Page ▸); "Add page N to outline" vs the dialog's "Add page N to the outline" | Two names for one thing | `toolbar/insert_menu.dart`, `outline/outline_entry_dialog.dart` |
| ✅ S4 | Ink popovers: Reset becomes "Reset feel" inside Feel (R5-5) | Quick colours are choices, not settings; one reset scope | `pen/ink_options.dart` |
| ✅ S5 | Quick colour and size counts fold under a collapsed "Toolbar" disclosure ("3 colours · 3 sizes"); the max goes 6 → 5, as SIMPLIFY #13 decided (`PenConfig.maxSlots` is 6) | Two always-open stepper rows for a one-time choice; the popover's default view becomes Colour · Size · Feel | `pen/ink_options.dart`, `ink/pen/pen_config.dart` |
| ✅ S6 | Pen palette: 20 → 14 presets (R5-2) | Near-twins; Recent and Custom cover the rest; halves the touch height | `ui/color_picker/color_swatches.dart` |
| ✅ S7 | Templates: merge "Basic" into "Paper" (R5-24) | Two categories for plain papers | `domain/templates/paper_style.dart` |
| ✅ S8 | Handwriting settings without a recogniser: a caption, no row (R5-27) | A status row with nothing to do | `settings/handwriting_settings.dart` |
| ✅ S9 | Convert to text: no first "alternative" equal to the field; empty and failed results as snacks (R5-18) | One reading shown once; no modal for "nothing" | `recognition/convert_to_text_dialog.dart` |
| ✅ S10 | In-notebook search: one counter format ("3 matches", "1 of 3"), not "3 found" / "1/3" on phones | One string set; at 390 dp the long form fits once R5-15 frees the field | `features/search/editor/editor_search_bar.dart:135-140` |
| ✅ S11 | Phones: ↷ only while there's something to redo (R5-9) | A permanently disabled button in the tightest bar | `chrome/editor_top_bar.dart` |
| ✅ S12 | Selection ⋯: "Bring to front" and "Send to back" become one "Arrange ▸" row (or go when only one element is selected and nothing overlaps) | Rare commands take two of the ⋯ menu's ~8 rows | `tools/selection_menu.dart` |

Kept on purpose (not proposed): the toolbar pair in View ▸ (REDESIGN §2.1),
"Draw with finger" in ⋯ and in Settings (it's situational), canvas
long-press page commands (context shortcuts like GoodNotes'), and the laser
in the tool row (SIMPLIFY #5).

### What's good now

The new pieces hold up. Reset/Undo reads clearly and is disabled at the
defaults. Size in mm with a log slider feels right. The highlighter palette
works. Undo for page edits ("Template changed on 9 pages · Undo") behaves
like ink undo. The startup error, schema-reset and storage-full notices are
calm and specific. The phone ⋯ menu drills in instead of cascading. The tab
switcher sheet, destructive confirms and the new export Save to device /
Share footer are consistent in both themes.

---


## Round 4 audit (`review/ux-round4`)

Scope: the whole app after the redesign phases and round 3. Method: all
663 renders from `test/screenshots/` (phone 390×844 @2x, tablet portrait
800×1280, tablet landscape 1280×800, desktop 1440×900; light, dark, 1.3×
text), each one read; plus a code read of the main flows (first launch,
create, write, tools, undo, lasso, images, text, pages, export, search,
sync, web storage, trash, shortcuts, input). Compared against GoodNotes 6
and Notewise. Items still open above (progress Cancel, convert-to-text
Try again, ragged stacked actions, phone new-notebook preview at 1.3×, FAB
over empty Favourites and search, phone search panning, dark lasso
handles, crop bar overlap, phone page submenu, routed text-bar and pen3
items) are not repeated.

Screenshot names are files in `app/build/screenshots/` (regenerate with
`flutter test test/screenshots --dart-define=SCREENSHOTS=true`). The suites
pump screens as the first route, so missing back buttons on Settings and
Pages in the renders are harness artefacts and are not reported.

Code paths are under `app/lib/` (`features/editor/` is often left out for
editor files: `chrome/…`, `tools/…`, `pen/…`, `document/…`).

Status: per item (✅ fixed, 🟡 partly fixed).

### Top 10 (fix first)

1. P0-1 Web blobs silently fall back to memory (data loss).
2. P0-2 A database failure at startup shows a blank window.
3. P1-1 Opening a notebook in dark mode flashes a light editor.
4. P1-7 Changing a template (all pages) can't be undone.
5. P1-10 Phones have no visible route to the page overview.
6. P1-4 Tool options popover: the slot-count steppers read as values, and it runs off short screens with no cue.
7. P1-22 Sync errors show raw exceptions and live only in the sidebar tooltip.
8. P1-24 Export success says nothing useful about where the file went (and nothing on Android).
9. P1-12 Missing desktop basics: Ctrl+A, arrow nudge, Ctrl+= / − in notebooks.
10. P1-26 Convert to text → Replace makes a one-line box that runs off phones.

### P0 — broken

✅ **P0-1 Web: if IndexedDB can't open, PDFs, images and audio live in memory and vanish with the tab.**
`platform/blob_backend_web.dart:14-20` catches any error and returns
`MemoryBlobBackend()` with only a `debugPrint`. Browsers that block
IndexedDB (older private modes, locked-down profiles, storage disabled) hit this. The user imports a PDF, annotates it,
closes the tab and the backgrounds are gone ("PDF page unavailable"), with
no warning ever shown. *Fix:* expose `blobsArePersistent` on `AppServices`;
show a persistent library banner ("Files you add won't be kept in this
browser window. Turn on sync or use a normal window.") and say so in
Settings → Storage. *Files:* `platform/blob_backend_web.dart`,
`data/blob_backend.dart`, `app_services.dart`, `features/settings/storage_settings.dart`,
`features/library/library_screen.dart`.
*Done:* the web fallback is a `VolatileBlobBackend`;
`AppServices.blobsArePersistent` drives a library banner ("Files you add won't
be kept in this browser window"), a Settings → Storage row, and a one-time
snack the first time a file is stored.

✅ **P0-2 A database or blob-store failure at startup leaves a blank window.**
`main.dart:27-31`: `AppDatabase.openDefault(dir)` and `openBlobBackend(dir)`
are awaited with no try/catch before `runApp`, so a locked, corrupt or
unwritable database (full disk, a second desktop instance racing, a broken
wasm VFS) gives an empty window and no clue. *Fix:* wrap startup; on failure
`runApp` a small error screen (what happened in one sentence, the data folder
path on desktop, Copy details, Try again). *Files:* `main.dart`, a new
`ui/startup_error.dart`.
*Done:* `main.dart` opens the storage in a try; on failure
`ui/startup_error.dart` explains (data folder on desktops), with Try again and
Copy details.
A database from an older pre-release (same `user_version`, different
tables) no longer lands there: it is backed up and started fresh, and the
library says so once with the backup path (`SchemaCheck`).

### Editor chrome

✅ **P1-1 Opening a notebook in dark mode flashes a light editor.**
`open_tablet_dark_40.png`, `open_tablet_portrait_dark_40.png`,
`open_phone_dark_40.png`: mid-transition the editor fades in over the
paper-coloured growing cover, so the whole bar and backdrop read as pale grey
over the dark library, every open and close. *Fix:* in `NotebookOpenRoute`
put the dark `canvasBackdrop` under the fading editor (the paper only where
the page is), or cross-fade from the cover to the backdrop first. Check the
`_back` frames too. *Files:* `features/editor/tabs/notebook_open_route.dart`.
*Done (`fix/editor-chrome-r4`):* dark mode flies on `canvasBackdrop` (light
mode keeps the paper); the open and back frames stay dark.

✅ **P1-2 Focus mode's exit is nearly invisible on touch, and the puck sits on the writing.**
`editor_focus.png`, `present_light.png`, `present_dark.png`: the 32-dp exit is
at 40 % on a light chip in the top-right corner (about 2:1), and touch has no
hover to reveal it. The puck's grip is a separate bubble beside it, and
both sit over the last lines. *Fix:* the exit at full contrast for 2 s after
entering and after any tap on empty chrome space, then 40 %; Android back
(and Esc, already) leave; merge the grip into the puck's capsule; the puck
starts at the bottom edge but snaps clear of the page content when it overlaps
ink on release. *Files:* `chrome/focus_handle.dart`, `chrome/tool_puck.dart`.
*Done:* the exit shows in full for 2 s on entering, then rests at 70 % on
touch (40 % with a mouse), `onSurface` glyph, a 48-dp target on touch; back
and Esc already left. The grip is inside the puck's capsule
(`ToolbarSlot.joined`). Released over writing, the puck moves to the nearest
clear spot along the edges (`chrome/puck_clearance.dart`, `fix/editor-followups`).

✅ **P1-3 The tab strip cuts the last tab with no cue, and squeezes the active tab first.**
`e_tabs_tablet_portrait_light.png` ("Spanish voca" cut at the edge, no fade,
no overflow control), `e_tabs_desktop_light.png` (the active "Physics —
Mecha…" is the only truncated tab while 200 px are free). *Fix:* `ScrollFade`
on the strip and scroll the active tab into view; size tabs to their title up
to 220 dp and shrink inactive tabs before the active one. *Files:*
`features/editor/tabs/notebook_tab_strip.dart`.
*Done:* tabs keep their size (inactive up to 220 dp, the active one 280) and
the strip scrolls with a 48-dp `ScrollFade`; a newly active tab scrolls into
view; the strip starts at the leading edge (it was centred on desktops).

✅ **P2-1 The phone top bar wastes its width.** `editor_phone_paged_light.png`,
`editor_narrow_paged.png`: ↶ ↷ ⋯ sit about 48 dp apart (96 px @2x), so long
titles truncate early ("Physics — …" in the narrow render) while there is no
▦ (see P1-10). *Fix:* 40-dp visual buttons in 48-dp targets packed together
(no extra gaps); use the gained width for ▦ and the title. *Files:*
`chrome/editor_top_bar.dart`, `chrome/bar_button.dart`.
*Note:* ↶ ↷ ⋯ already are 48-dp targets edge to edge (48 dp is the minimum
pitch on touch); ▦ on phones comes with P1-10 (`fix/pages-writing`).

✅ **P2-2 The phone ⋯ menu is long and mixes ellipsis rules.** `editor_phone_more_menu.png`:
9 rows; "Record audio" and "Recordings…" are two rows; "Settings…" and
"Recordings…" have ellipses though they ask nothing (CONVENTIONS: … only
for commands that ask first); the submenu arrows are filled triangles, unlike
the rounded chevrons elsewhere. *Fix:* one "Audio" row (record; recordings
when there are any, as on wide); drop the ellipses; a `chevron_right_rounded`
trailing glyph for submenus. *Files:* `chrome/editor_more_menu.dart`,
`ui/menus.dart`, `features/audio/ui/audio_bar_button.dart`.
*Done:* "Recordings" shows only once there are any (Record audio stays one
tap); "Settings" and "Recordings" lose the ellipsis; wide submenus showed a
chevron *and* Material's triangle → one rounded chevron (theme `submenuIcon`).

✅ **P2-3 View ▸ runs three radio groups together.** `e_page_zoom_menu_*`,
`menu_more_view*`: Scroll / One page, Fit width / Fit page / Automatic and
Toolbar docked / floating show three checks at once with no dividers; Fit
width (Shift+2) is listed above Fit page (Shift+1); "Automatic" doesn't say
what it automates. *Fix:* dividers between groups; order Fit page, Fit width,
"Automatic zoom"; consider dropping the toolbar pair from View (it is in
Settings → Writing; one home). *Files:* `chrome/editor_more_menu.dart`.
*Done:* the dividers were already there; Fit page, Fit width, "Automatic
zoom" now in shortcut order. The toolbar pair stays (REDESIGN §2.1 puts it in
View as well as Settings).

✅ **P2-4 The empty-canvas hint talks touch on desktops.** `editor_empty_canvas_tablet_*`
vs desktop: "two fingers… long-press" appears with a mouse too, and is
smaller than on phones. *Fix:* pick the copy by `Targets.touchFirst` (mouse:
"Scroll to pan, Ctrl+scroll to zoom, right-click for more"). *Files:*
`features/editor/canvas/canvas_empty_hint.dart`.
*Done:* copy by `Targets.touchFirst` (was the platform), "…for more options".
The screenshot suites render desktop sizes (≥ 1400 dp) with a pointer
(`setWindow`), so desktop renders show pointer copy and sizes.

✅ **P2-5 The page indicator shows "1 / 1".** `open_phone_light_80.png`,
`open_tablet_portrait_light_80.png`: a one-page notebook gets the pill (and it
pops mid-transition). *Fix:* don't peek with a single page; keep the tap target
via ⋯ → Go to page only when there are pages to go to. *Files:*
`chrome/peeking.dart`, `page_navigator.dart`.
*Done:* no indicator with a single page (`editorPageNavigator`).

### Pen and tools

✅ **P1-4 The tool options popover is hard to read and runs off short screens.**
`popover_from_slot_light.png`, `popover_pen_*`, `phone_pen_sheet*`:
- "Colour − 3 +" and "Width − 3 +" are the *number of quick slots*, but read
  as a value; the slider below is "Width 2 … 2.5" (slot index plus value).
- With Feel open the panel runs past the bottom of a 800-px-high tablet
  ("Ends" is half visible) with no fade or scrollbar.
- The slot row repeats the toolbar's slots right under them.

*Fix:* drop the slot steppers from the top; put "Quick slots: − 3 +" as one
row at the bottom (or under Feel). Label the slider "Size" with a unit
("0.8 mm"). Add `ScrollFade` to the popover body. *Files:*
`features/editor/pen/ink_options.dart`, `pen/option_controls.dart`,
`ui/adaptive_popover.dart`.
*Done:* Size slider with mm on the page (log scale, "0.66 mm", also in slot
tooltips and the selection's Style); "Quick colours / Quick sizes − n +" rows
at the bottom; the popover body scrolls with `ScrollFade` (vertical; it now
keeps its content's state when the fade appears); the slot row shows only in
the phone sheet, which covers the toolbar; "Ends" uses the row label style and
slider tracks line up with their labels.
*Follow-ups (fix/a11y-tools):* the lasso Style panel's Size slider uses the
same log scale (`pen/size_scale.dart`); the phone sheet scrolls with
`ScrollFade` too; on touch the colour swatches sit in 48-dp cells
(`EvenGrid`: the pen palette shows its four colour families as rows of 5).

✅ **P1-5 Shapes: the selected kind looks switched off, and the panel says the snap tip twice.**
`e_shape_picker_tablet_light.png` / `_dark`, `popover_shapes*`: unselected
kinds have a grey plate and the selected one is the light one (inverted from
every other picker). Seven kinds wrap 5 + 2. The help paragraph repeats the
"Hold to snap shapes" switch below it ("Tip: … pause at the end of a stroke")
and "Hold Shift" shows on touch tablets. Also the toolbar shows a separate
kind button □ with no chevron, a second home for the same choice. *Fix:*
`Surfaces.pressed` plate only on the selected kind; one row of seven (or
`EvenGrid` 4 + 3); one help line, the Shift hint only with a keyboard; give
the strip's kind button a ▾ or drop it. *Files:* `tools/shape_options_panel.dart`,
`tools/shape_strip.dart`.
*Done:* seven kinds in one row of 40-dp tiles, `Surfaces.pressed` only on the
selected one; one help line, the Shift line only with a pointer (not
touch-first); the snap switch subtitle says "Hold still…"; the strip's kind
button is gone (the Shapes button shows the kind).

✅ **P1-6 The selected width slot looks like the selected black colour.**
`toolbar_pen_more_slots*`, `editor_phone_paged_light.png`: both selections are
a ring around a dark dot ("◉ ● ●   · ◉ ●"); at a glance there are two black
colours. *Fix:* width slots show a short stroke or a hollow plate selection
(`Surfaces.pressed`) instead of the colour's ring. *Files:*
`pen/slot_button.dart`, `pen/ink_slots.dart`.
*Done:* size and eraser slots select with the neutral pressed plate
(`SlotButton.plate`); colours keep the ring.

✅ **P2-6 The highlighter offers the pen palette.** `popover_highlighter*`: black,
navy and white highlighters are useless at 30 % opacity. *Fix:* a highlighter
palette of light, saturated colours (the existing default yellow, green,
pink, blue, orange, purple) plus recent and Custom. *Files:*
`pen/ink_options.dart`, `ui/color_picker/*`.
*Done:* `ColorSwatches.highlighter`, ten light hues in one row (new
highlighter slots start from it too).

✅ **P2-7 Popovers disagree on their header and colour controls.** `popover_laser*`
(no Reset; a bare palette icon instead of "Custom"), `popover_text*` (15 swatches
wrap 9 + 6, another palette, no Reset), `e_text_colour_tablet_*` (text colour
needs an "Apply" while every other colour applies live). *Fix:* one header
(title + Reset) and one `ColourChoices` block for all tool popovers; text
colour applies live. *Files:* `tools/laser_options_panel.dart`,
`tools/text_options_panel.dart`, `tools/colour_sheet.dart`.
*Done:* title + Reset on pen, highlighter, eraser, text and laser (lasso and
shapes have nothing to reset); one `ColorChoices` block ("Colour" + Custom,
palette, recent) in ink, text and laser; `pickColour` has no Apply: live, and
closing keeps the last pick (and notes it as recent).
*Follow-ups (fix/a11y-tools):* Reset now restores everything its popover
shows (for ink: quick colours and sizes, their counts and Feel), then reads
Undo until something else changes; it is disabled at the defaults. Undo sits
in the popover rather than a snack bar, which would sit under the sheet or
popover barrier. The template dialog's paper and pattern colours
(`ui/color_picker/pick_color.dart`) are live the same way; `pickColour`
builds on it.

✅ **P2-8 Copy in tool popovers.** "Auto-deselect" (eraser) is jargon → "Switch
back after erasing"; the lasso help is a long paragraph → two short lines.
*Files:* `pen/eraser_options_panel.dart`, `tools/lasso_options_panel.dart`.
*Done:* "Switch back after erasing / Returns to your pen or highlighter";
lasso: two short lines plus the PDF hint.

### Writing, selection, text, images

✅ **P1-26 Convert to text → Replace makes a one-line box that runs off the screen.**
`e_convert_phone_light_replaced.png` / `_dark`: "Newton's second law: F = m…"
runs past the right edge, handles included. *Fix:* give the new box the
recognised ink's width (wrapping) and keep it in the viewport.
*Files:* `features/editor/recognition/convert_to_text_dialog.dart` (replace
path), `ink/elements/text_*`.
→ ✅ The box wraps at the ink's width (never narrower than its longest word) and stays inside the visible page or canvas (`ConvertToText.textBox(area:)`).

✅ **P1-7 Changing the template is not undoable.** `document/document_commands.dart:150-162`
→ `PageActions.setTemplate` writes `services.pages.setPaper` directly; no
history entry, no Undo snack (delete page has one). "Apply to all pages" on a
100-page notebook can't be taken back. Page reorder
(`page_actions.dart:90`) and bookmark toggles (`:106`) also bypass undo.
*Fix:* record old papers and offer "Template changed · Undo" (as delete
does), or better push page-level commands into the editor history so Ctrl+Z
works. *Files:* `document/document_commands.dart`, `document/page_actions.dart`,
`features/documents/overview/page_commands.dart`.
→ ✅ Templates, moves, bookmarks (many as one step), added, duplicated and deleted pages are steps of the notebook-wide undo history (`PageEdits` → `PageModels.record`), so Ctrl+Z and ↶ take them back in order with ink. "Template changed on N pages · Undo"; snack-bar Undo goes through the same history (`PageModels.undoEdit`). Pages inserted from a PDF are one step too, and so is duplicating several pages in the overview ("2 pages duplicated · Undo").

✅ **P1-8 Phones: the selection bar and handles get clipped at the edge.**
`e_shape_selected_phone_*` (handles cut at the screen edge),
`o_selection_menu_phone_*` (bar 8 dp from the edge, opens below and covers
the next lines), `pdf_selection_phone_*` (Copy / Highlight bar below the
selection, covering the next line; above on tablets). *Fix:* clamp handles
12 dp inside the viewport (pan if needed); bars prefer above, like tablets.
*Files:* `tools/selection_menu.dart`, `features/editor/pdf/*` (text selection bar).
→ ✅ Handles stay 12 dp inside the view (`SelectionChrome.edgeInset`); resizing follows the true corner, so a clamped or off-centre grab never jumps. The selection bar keeps 12 dp from the sides. Both bars already prefer above; they go below only when there's no room above (left as is).

✅ **P1-9 Microphone denied is a dead end; pause failures are silent.**
`audio/recording_controller.dart:149-150` throws "Microphone access was not
allowed." shown as a plain snack; after a permanent denial there is no path
to fix it. `audio_bar_button.dart:146` fires pause/resume unawaited and
`recording_controller.dart:217-224` sets *Paused* before the capture pauses,
so a failure leaves "Paused" while the mic still records. Messages embed raw
exceptions ("Could not start recording ($e)."). *Fix:* a Settings action on
the denial snack (open app settings); await pause/resume, revert state and
`showMessage` on failure; drop `($e)` from copy (log it). *Files:*
`features/audio/recording_controller.dart`, `features/audio/ui/audio_bar_button.dart`,
`features/audio/playback_controller.dart`.
→ ✅ Denial says "Allow microphone access for Len in system settings" (browser: site settings). The message's Settings button opens Len's app settings on Android and the microphone privacy page on Windows. Pause/resume wait for the recorder, ignore double taps, keep the real state and show a message on failure. No raw exceptions in copy (logged).

✅ **P2-9 Paste with nothing to paste does nothing.** `ink/tools/content_tools.dart:136`
returns silently; Ctrl+V and the canvas menu's Paste give no feedback. *Fix:*
"Nothing to paste". *Files:* `ink/tools/content_tools.dart`,
`features/editor/images/editor_images.dart`.
→ ✅ "Nothing to paste" (Ctrl+V; the menus only offer Paste when there is something).

✅ **P2-10 Image insert: storage errors escape.** `images/editor_images.dart`
(`_prepare`) only catches `ImageImportException`; a write failure in
`ImageImport.store` (disk full, quota on web) is unhandled. *Fix:* catch
`Object` → "Couldn't add the image". *Files:* `images/editor_images.dart`.
→ ✅ Any storage failure says "Couldn't add the image".

✅ **P2-11 Audio: player icons and recordings sheet.** `e_audio_playback_*` mixes
filled and outline glyphs, the seek track is dotted with a bare bar for a
thumb, and trim floats alone; `e_audio_sheet_*` subtitle "4 recordings ·
1:16:54 · 64 bytes on this device" wraps over 2–3 lines and shows sizes per
row; `e_audio_recording_phone_*` the recorder pill covers "Add page".
*Fix:* outline Rounded glyphs with tooltips; a solid track with a round thumb;
subtitle "4 recordings · 1 h 17 min", sizes only in a row's menu; lift the pill
above the add-page footer (`MessageInsets`-style inset). "Sync and try
again" (`audio/backends/audioplayers_playback.dart:48,64`,
`audio/recording_export.dart:81`) offers no Sync: add "Sync now", or say "It
downloads when you're online". *Files:* `features/audio/ui/*`,
`features/audio/backends/audioplayers_playback.dart`, `features/audio/recording_export.dart`.
→ ✅ Solid seek track with a round thumb; Recordings uses an outline glyph; subtitle "4 recordings · 1 h 17 min", sizes moved into a row's menu; "…It downloads when you're online". The pill and player add room past the end so Add page scrolls clear (see the
follow-up notes). Not done: trim into the overflow.

✅ **P2-12 "Draw with finger" is hidden in Automatic and named differently.**
`chrome/editor_more_menu.dart:82` shows the switch only once a stylus was seen
(`stylusOnly != null`); Settings calls it "Draw with: Automatic / Stylus only /
Stylus & finger". The stylus-detected snack's action "Undo"
(`editor_screen.dart:330`) sets Stylus & finger permanently and reads like
document undo. *Fix:* label the snack action "Keep finger drawing"; in ⋯ use
the Settings wording ("Draw with finger" stays but shows in Automatic too,
on = until a stylus is seen). *Files:* `chrome/editor_more_menu.dart`,
`editor_screen.dart`.
→ ✅ The switch shows in Automatic on touch screens (on until a stylus is seen; with a mouse, once a stylus was seen); the snack action reads "Keep finger drawing".

### Pages and navigation

✅ **P1-10 Phones have no visible route to the page overview.** The phone bar is
`← title ↶ ↷ ⋯` (`chrome/editor_top_bar.dart:230-238`, no ▦), and ⋯ offers
"Outline", which opens the overview *filtered to the outline*
(`editor_actions.dart:52`). The other route is a long press on the page pill,
which only shows while scrolling. GoodNotes and Notewise phones have a
thumbnails button. *Fix:* put ▦ in the phone bar (there's room, P2-1), and
drop "Outline" from ⋯ (the overview's filter is its home); on wide screens ⋯ →
Outline duplicates ▦ too. *Files:* `chrome/editor_top_bar.dart`,
`chrome/editor_more_menu.dart`, `editor_actions.dart`.
→ ✅ ▦ in the phone bar; Outline dropped from ⋯ (all widths) — it is the overview's filter.

✅ **P1-11 "Add page 1" in the outline reads as "insert a page".** `o_outline_panel_*`,
`pdf_outline_*`: the button `Text('Add page ${current + 1}')`
(`outline/outline_panel.dart:120`) sits above the "This notebook" heading it
belongs to. *Fix:* "Add this page to the outline" (or "Add page 1 to outline")
under the heading. *Files:* `features/editor/outline/outline_panel.dart`.
→ ✅ "Add page N to outline" under the heading (a text button); one row marks the page on screen (the deepest entry); "PDF outline".

✅ **P2-13 Overview: the selection bar and the current-page badge.**
`overview_select_*`: bottom-bar icons are about 12 px over 14 px labels and
read as bullets; the current-page badge uses the selection blue, so page 2
looks selected; "Bookmark" on a mixed selection doesn't say whether it adds or
toggles. `overview_*`: the per-page ⋯ is tiny and low contrast; title, filter
and grid start at three different x positions. *Fix:* 20-dp `Glyphs.bar`
icons; a neutral badge (or none) in selection mode; "Bookmark" / "Remove
bookmark" by state; one horizontal inset. *Files:*
`features/documents/overview/overview_parts.dart`, `page_tile.dart`.
→ ✅ 20-dp icons; the current-page badge is the neutral plate; "Remove bookmark" when all selected pages are bookmarked (mixed adds), one undo step; the title lines up with the filter when there's no back button.

✅ **P2-14 The outline view on tablets is a full screen with an empty half.**
`o_outline_panel_tablet_*`, `pdf_outline_tablet*`: rows run 720 px wide with
page numbers far from short titles, and that screen has ← but no Select while
the All filter has Select but no ←. *Fix:* cap the list at 640 dp, centred; one
app bar for all filters. *Files:* `features/documents/overview/page_overview.dart`.
→ ✅ The outline is a centred 640-dp column. The app bar is already one for all filters (Select is hidden on Outline only).

✅ **P2-15 Planner pages mix languages and fade their labels.** `paper_daily_tr*`,
`paper_weekly_sunday_ru*`: weekdays and months are localised but "Week 41",
"SCHEDULE", "PRIORITIES", "TO DO", "NOTES" stay English; labels are tiny
light-grey caps (worst on A5); a week across two months shows only one month.
*Fix:* add those labels to the planner label tables; darker labels; "Dec –
Jan". *Files:* `domain/templates/patterns_planner.dart`, planner label tables.
→ ✅ Week, Schedule, Priorities, To do and Notes come in all 19 planner languages; a week across two months reads "Dec – Jan"; headings slightly bigger.
*Done (fix/a11y-tools):* darker labels: muted planner text is drawn at 80 %
(`PatternLabel.mutedOpacity`, was 62 %), over 3:1 on every paper colour.

### Library

✅ **P1-13 The floating selection bar covers cards.** `select_tablet*` (over card
titles), `select_phone*` (over the bottom row): the grid has no bottom padding
for it. *Fix:* pad the grid by the bar's height while selecting (as results
are padded for the FAB). *Files:* `features/library/selection/*`,
`library_content.dart`.
→ ✅ The grid and list end with 120 dp of room (160 on phones), so the selection bar, ⊕ and a snack bar above it clear the last row.

✅ **P1-14 Phone FAB covers the last card's ⋯.** `library_phone_*`: the + sits on
the last card's caption and menu button. *Fix:* bottom padding = FAB + 16 dp in
grid and list (search already does). *Files:* `library_content.dart`.
→ ✅ Same end room in grid, list and search (`library_content.dart`).

✅ **P1-15 Trash never empties itself, and restore loses the folder.**
`library_empty_state.dart:60` "stay here until you delete them forever"; no
purge anywhere. Restoring a notebook whose folder was deleted puts it at the
root (`data/notebook_repository.dart:141-147`) silently; Restore and Move show
no message (`library_actions.dart:182`, `selection/selection_actions.dart:41`).
*Fix:* purge after 30 days ("Deleted 3 Oct · 27 days left"); "Restored to
School" / "Moved 3 notebooks to Work · Undo". *Files:*
`features/library/library_actions.dart`, `library_controller.dart`,
`data/notebook_repository.dart`.
→ ✅ The trash deletes notebooks forever after 30 days (cards count down, header and empty state say so); Restore says where notebooks went, Move says so with Undo.

✅ **P1-16 Deleting a folder doesn't say how much goes, and can't be undone.**
`library_actions.dart:225-231`: "Its subfolders are deleted too; notebooks
inside move to the trash." No counts and no Undo; restored notebooks lose
their folders. *Fix:* "Delete “School”? 2 subfolders and 14 notebooks go to
the trash." plus an Undo snack (folders are soft-deleted already). *Files:*
`features/library/library_actions.dart`, `library_controller.dart`.
→ ✅ "Delete “School”? 2 subfolders and 14 notebooks go to the trash." and an Undo snack that brings the folders back with their notebooks.

✅ **P2-16 Empty states disagree.** `empty_phone_light`, `empty_folder_phone`,
`empty_search_phone`, `s_library_favourites_empty*`, `s_library_trash_empty*`:
illustration vs grey disc; "New notebook" vs "New notebook here" (filled) vs
"Clear search" (outlined); the header caption says "Empty" above "This folder
is empty"; empty Favourites and Trash keep search and ⇅ active; the folder's
copy "drag notebooks onto this folder" can't be done on a phone. *Fix:* one
`EmptyState` (icon in a disc, title, one line, one filled action); no caption
and no search/⇅ while empty; touch copy "Move notebooks here from their ⋯
menu". *Files:* `features/library/library_empty_state.dart`,
`library_header.dart`.
→ ✅ One empty-state style (disc icon, title, line, one filled action; New notebook everywhere); no caption, search or ⇅ while a view is empty; touch copy for folders.

✅ **P2-17 First launch offers only "New notebook".** `library_empty_state.dart:92-97`:
no Import PDF, no hint that sync exists (a user with a server sees an empty
library). *Fix:* secondary actions "Import PDF…" and "Set up sync…" under the
primary. *Files:* `features/library/library_empty_state.dart`.
→ ✅ First launch offers Import PDF… and Set up sync… under New notebook.

✅ **P2-18 The phone folder header stacks breadcrumbs over ☰.** `empty_folder_phone.png`:
"Library ›" above "☰ Sketches"; ☰ inside a folder reads as "you're at the top".
*Fix:* in folders on phones, ← (up one level) replaces ☰; no breadcrumb row.
*Files:* `features/library/library_header.dart`.
→ ✅ Phones go up from folders with ← (no breadcrumb row).

✅ **P2-19 Three ways to start a notebook on wide screens.** `desktop_folder`,
`large_library_tablet`: the "New…" tile, ⊕▾ and, in the sheet, "Import PDF…".
The tile's label "New…" is vague and low-contrast in dark. *Fix:* label the
tile "New notebook"; keep ⊕▾ for the other kinds. *Files:*
`features/library/new_notebook_tile.dart`.
→ ✅ The tile says New notebook; Import PDF… only in ⊕▾ and the empty state.
*Done (fix/a11y-tools):* contrast: in dark mode the tile has the firmer
`outline` edge (its face is close to the background).

✅ **P2-20 The ⇅ View menu has no group labels.** `s_library_view_menu*`: sort,
layout and Select… run together with a ragged icon column; the current sort
isn't shown in the header. *Fix:* "Sort by" / "Show as" `SectionLabel`s, the
leading slot always reserved; caption "7 notebooks · by name" when not the
default. *Files:* `features/library/library_header.dart`, `library_menus.dart`.
→ ✅ Sort by / Show as headings; the caption names a non-default order; Select without an ellipsis.

✅ **P2-21 List view.** `desktop_list.png`, `s_library_list*`: an outline star on
every row (the grid only marks favourites) and the star and ⋯ sit 1300 px from
the title on desktop. *Fix:* stars only on favourites (hover shows the toggle);
cap the list at 960 dp or add a "Edited" column. *Files:*
`features/library/notebook_list_tile.dart`.
→ ✅ Rows star only favourites (the toggle on hover); the list stops at 960 dp.

✅ **P2-22 Search results mix two layouts.** `s_library_search*`, `desktop_search.png`:
title matches are big grid cards, content matches list rows, and every row
says "1 match". *Fix:* sections "Notebooks" and "Pages" as rows; omit "1
match". *Files:* `features/search/library_search_results.dart`.
→ ✅ Titles as rows under Notebooks, matches under Pages; no "1 match".

✅ **P2-23 Small touch targets on cards and folders.** `notebook_card.dart:199`
(`height: Targets.touchFirst ? 36 : 28`) and the folder ⋯
(`folder_tile.dart:133`, about 32 dp wide). *Fix:* 48-dp hit area with the same
visual; tooltip "More" on both (not "Folder options"). *Files:*
`features/library/notebook_card.dart`, `folder_tile.dart`.
→ ✅ 48-dp ⋯ targets on touch; folder ⋯ is "More".

✅ **P2-24 Covers flash flat colours, then thumbnails.** On loading, notebooks
show their cover colour before their thumbnail. *Fix:* neutral placeholder and
a `Motion.fast` cross-fade. *Files:* `features/library/thumbnails/*`.
→ ✅ A neutral placeholder until the preview is checked (`ThumbnailCache.isPending`), cross-fading (`Motion.medium`) to the thumbnail or the plain cover.

### Dialogs, sheets and settings

✅ **P1-17 Sheets and dialogs still disagree on their footer and close controls.**
`folder_dialog_phone` (full-width Save, no Cancel) vs `s_dialog_cover*` (✕ +
Cancel + Apply) vs `export_phone_*` (Cancel + Export) vs rename (no ✕) vs move
(✕, no footer) vs the new-notebook sheet (no drag handle, unlike the others).
REDESIGN §5 says: task sheets have ✕ and a footer of Cancel + one filled
primary; Confirms have no ✕. *Fix:* apply that in `SheetActions` /
`SheetHeader` everywhere; pickers that commit on tap (move) keep only ✕.
*Files:* `ui/sheet_parts.dart`, `ui/dialog_or_sheet.dart`,
`features/library/dialogs/*`, `features/library/new_notebook_sheet.dart`.
→ ✅ One rule: task sheets have ✕; wide ones add Cancel + one filled primary, on phones ✕ is Cancel and the primary is full width (folder, cover, change template, export on Android); pickers that commit on tap (move) keep only ✕; Confirms (rename) have no ✕; the new-notebook sheet has the drag handle. Stacked secondary buttons are outlined.

✅ **P1-18 Ten cover colours wrap 9 + 1.** `desktop_cover_sheet.png`,
`dialog_cover_light/dark.png`: Sand alone on a second row with empty space
below, while the new-notebook form fits all ten in one row. *Fix:* the same
`EvenGrid` row as the new-notebook form (10 × 1 wide, 5 × 2 on phones).
*Files:* `features/library/dialogs/cover_sheet.dart`, `cover_picker.dart`.
→ ✅ One `CoverRow` for the cover sheet and the new-notebook form: ten in a row, two rows of five spread across the width on touch where one row would shrink targets under 48 dp.

✅ **P1-19 The wide new-notebook dialog clips Portrait / Landscape.**
`desktop_new_sheet.png`, `new_desktop_*`, `large_new_tablet*`: the form scrolls
inside a short dialog and the orientation control is cut in half above the
footer, with no fade; at 1.3× "All templates…" breaks mid-word ("All tem /
plates…"). *Fix:* let the dialog grow to the window (max 720 dp tall) and add
`ScrollFade` above the footer; never break the tile label mid-word (wrap on
spaces, or "More…"). *Files:* `features/library/new_notebook_sheet.dart`,
`features/library/new_notebook/*`.
→ ✅ The form fades where it runs under the footer; the tile says More… (never breaks mid-word).

✅ **P1-20 Template side panels clip and wrap.** `e_dialog_add_page_template_desktop_*`,
`e_dialog_canvas_background_desktop_dark`, `templates_*`: chips half cut at
the panel bottom with no scroll cue; the custom-colour button wraps alone
(6 + 1); two previews; spacing presets repeat the ruled templates. Searching
"grid" leaves the "Planners" chip selected; selected chips are barely visible
in dark. *Fix:* `ScrollFade` on the panel; Custom inline in the swatch row; one
preview; drop the presets (the slider plus the templates cover them); clear
the category on search; selected chips use `Surfaces.pressed` + a check.
*Files:* `features/documents/templates/paper_options.dart`,
`paper_option_rows.dart`, `template_chooser.dart`, `template_gallery.dart`.
→ ✅ Both chooser columns fade under the footer (`ScrollFade`); swatch rows stay on one line with the custom colour; one preview (the page preview when shown, else the actual-size swatch); no spacing presets. A search already selects All; selected chips use `Surfaces.pressed` (no check: it would shift the row).

✅ **P1-21 Change template on phones: three stacked buttons eat a third of the sheet.**
`e_dialog_change_template_phone_*`: Apply to this page, Apply to all pages and
Cancel (plus ✕) leave 1.5 rows of templates. *Fix:* a "This page · All pages"
segmented control and one Apply; ✕ is Cancel. *Files:*
`features/documents/template_picker.dart`.
→ ✅ "This page · All pages" segments and one Apply (phones: full width, ✕ cancels; wide: Cancel + Apply).

✅ **P2-25 Settings copy and controls.** `settings_*`, `s_settings_*`:
- "Draw with" segments are shrunk to a smaller size than the others (`ShrinkToFit`).
- "Side button: While you hold the S Pen (or stylus) button" shows on desktops and the web.
- "Toolbar: Along the top; at the bottom on phones" describes Docked even when Floating is chosen.
- Handwriting "Not available here" is followed by a paragraph on how to use it.
- "Sync is off" is a grey pill that looks like a disabled field.
- On wide screens the "Settings" title scrolls away under an empty app bar.
→ ✅ Segments sit under their text at full size; side button only on Android or for stylus users; the toolbar subtitle follows the choice; no how-to where recognition is unavailable; sync status is a plain row with an icon; the title is in the pinned app bar.

*Fix:* two-row segments rather than shrunk text; the side-button row only
where a stylus can be (Android, or once seen); the toolbar subtitle follows the
choice; hide the how-to where recognition is unavailable; status as a plain row
with an icon; the title in the app bar on wide screens. *Files:*
`features/settings/*`.
*Update (synced handwriting):* where nothing recognises, Handwriting now
says Android devices recognise and their text is found here after sync, with
a "Search handwriting" row counting the lines that arrived — no "Not
available here", no toggles.

✅ **P2-26 Snack bars still collide.** `e_snack_saved_template_phone_*` (two lines
grow down over the bottom toolbar), `e_snack_stylus_detected_phone_*` (snack
and the side-button tip at once), `e_missing_planner_page_phone` (PDF notice
and snack at once). *Fix:* `MessageInsets` anchors the snack's bottom edge,
so it grows upward; queue tips behind snacks; shorten "Saved “Physics —
Mechanics, page 1” to My templates" → "Page saved as a template". *Files:*
`ui/messages.dart`, `chrome/editor_tips.dart`, `document/document_commands.dart`.
→ ✅ Snack bars are anchored by their bottom margin and grow upward; the side-button tip waits for the stylus-detected snack bar; "Saved to My templates".
✅ *Rest (fix/a11y-library):* standing notices (the missing-PDF card) fade away while a snack bar shows (e.g. "no page for Wed, 14 Oct") and come back after it (`MessageQueue`), so one message shows at a time.

✅ **P2-27 Export sheet polish.** `export_*_range`, `export_narrow_large_text_scrolled`,
`export_tablet_portrait_*`: the range error shows in the field and again in
the footer ("Check the page range", wraps on phones); disabled Export is grey
on grey in dark; content scrolls under the header with no divider; 800-dp
tablets get a bottom sheet while 1280 gets a dialog. *Fix:* error in the field
only, helper "e.g. 1–3, 5"; theme disabled colours; header divider when
scrolled; `showDialogOrSheet` threshold at 600 dp. *Files:*
`features/documents/export/export_sheet*.dart`, `ui/dialog_or_sheet.dart`.
→ 🟡 The range error shows in its field only (helper "Pages 1–N, separated by commas", hint "e.g. 1-3, 5").
*Done (fix/a11y-tools):* disabled filled buttons keep a readable label
(`onSurfaceVariant` on a 12 % plate, theme-wide) instead of 38 % grey.
✅ *Done (fix/a11y-library):* a hairline under the header once the options scroll (as Settings' pinned bar). The 600-dp `showDialogOrSheet` threshold stays at 840 (lead decision: it would move every task sheet on 800-dp tablets).

✅ **P2-28 Missing-PDF notice copy.** `e_missing_pdf_background_*`: "A PDF these
pages are drawn on isn't on this device" / "Relink…" is awkward and repeats
the hatched placeholder. *Fix:* "The PDF for these pages isn't on this
device." with "Locate file…" and "Try again". *Files:*
`chrome/missing_pdf_notice.dart`.
→ ✅ "The PDF for these pages isn’t on this device" with Try again and Locate file….

### Sync, storage and files

✅ **P1-22 Sync errors are raw and hidden.** `sync/sync_api.dart:234,274` "Cannot
reach sync server: $e" (embeds `ClientException` / `SocketException` text),
`:251,289` "Sync server error 401…", `sync_controller.dart:189` "Sync failed: $e".
The only place an error shows is the sidebar status (`ui/sync_status_button.dart`),
where a tap retries and the message is a tooltip (long-press on touch, and the
drawer on phones must be opened first). A revoked token (401) retries forever.
*Fix:* map `SyncFailure` kinds to plain copy ("Can't reach your server. Check
the address or your connection." / "The server refused the access token.");
tapping a failed status opens Settings → Sync with the message and Details;
on auth failure, a one-time snack with "Settings"; a dot on the phone ☰ while
sync fails. *Files:* `sync/sync_api.dart`, `sync/sync_controller.dart`,
`ui/sync_status_button.dart`, `features/settings/sync_settings.dart`,
`features/library/library_header.dart`.
*Done (building on `sync_errors.dart`):* unexpected errors read "Something
went wrong on this device while syncing" with the raw text under Details (also
for blob upload errors); a failed status opens Settings → Sync (scrolled to);
a rejected token pauses automatic syncs until the settings change
(`SyncController.waitsForSettings`, `syncInBackground`) and says so once in a
snack with Settings; the phone ☰ gets a dot while sync fails.

✅ **P1-23 Sync setup is strict and has no off switch.** `s_settings_sync_error_phone_*`:
"len.example" is rejected ("Enter a full URL, e.g. https://…",
`sync_settings.dart:23`) instead of assuming `https://`; turning sync off
means clearing the URL and pressing "Connect & save" (`sync_settings.dart:66-71`).
*Fix:* prepend `https://` when no scheme is typed (show the result); once
connected show the server, last sync and a "Turn off sync…" text button
(Confirm) instead of the form. *Files:* `features/settings/sync_settings.dart`.
*Done:* `https://` is assumed (and shown) when no scheme is typed; once
connected Settings shows the status, the server, Sync now, Change… and Turn
off sync… (confirm).

✅ **P1-24 Export success doesn't say where the file went.** `documents/export/export_flow.dart:101,165`:
desktop shows "Saved /home/…/very/long/path.pdf" with no action; several
images say "Saved 3 images" with no folder; on Android the share sheet
returns null and nothing confirms (`platform/file_export_native.dart:38-59`),
and there is no "Save to device". Failures show `'Export failed: $e'`
(`export_flow.dart:107,170`, also `audio/recording_export.dart:104`). *Fix:*
"Saved “Lecture.pdf”" with Show in folder / Open on desktop; on Android offer
Share and Save to device (SAF `createDocument`) in the export sheet;
friendly failure copy, details in the log. *Files:*
`features/documents/export/export_flow.dart`, `platform/file_export*.dart`,
`features/audio/recording_export.dart`.
*Done:* `saveOrShareAll` returns `ExportedFiles`; messages say "Saved
“Lecture.pdf”" (Show in folder on desktops), "Saved 3 images to “Exports”",
"Shared …", "Downloaded …"; on Android the export sheet offers Save to device
(system save dialog, `SaveDocumentPlugin.kt`) beside Share; failures read
"Couldn’t export “x”" with Details (notebooks, canvases, recordings).

✅ **P2-29 Export drops content silently.** `documents/export/pdf_images.dart:72` (image
not embeddable → skipped), `pdf_page_sources.dart:42`, `pdf_export.dart:200`
(raster fallback, links omitted) only `debugPrint`. *Fix:* collect warnings
and end with "Exported · 2 images couldn't be included". *Files:*
`features/documents/export/*`.
*Done:* `ExportReport` collects missing PDF pages, images that couldn't be
embedded and PDF pages included as pictures; the success message ends "· 2
images couldn’t be included". PNG exports (pages and canvases) report images
and PDF pages they couldn't include too.

✅ **P2-30 Web: storage warnings live only in Settings.** Unpersisted storage with
sync off is shown in Settings → Storage only; there is no handling of quota
errors on write. *Fix:* a one-time library banner when storage isn't persisted
and sync is off; catch `QuotaExceededError` → "This browser is out of space
for Len". The "Len is open in another tab" screen (`main.dart:43-62`) is text
only: add "Use here", which takes the lock over. *Files:*
`features/settings/storage_settings.dart`, `features/library/library_screen.dart`,
`platform/*_web.dart`, `main.dart`, `platform/single_instance_web.dart`.
*Partly done:* a one-time library notice when the browser may evict data and
sync is off (Keep data / ✕). *Done (fix/web-robust):* quota errors on write
keep the changes in memory and retry ("Browser storage is full: your latest
changes are kept in this tab until there's room", once, with Try again; a
library notice while it lasts; "Your changes are saved" after). The other-tab
screen has "Use here": the old tab stores everything and stops writing before
it releases the lock (ARCHITECTURE *Platforms*, *Tab handover*). *Done
(fix/web-followups):* Settings → Storage shows unsaved changes too; reloading
the tab that has Len open keeps it there instead of handing it to a waiting tab.

✅ **P2-31 PDF import errors are generic.** `documents/pdf/pdf_import_flow.dart:91`
"It may be damaged or password-protected." *Fix:* tell the two apart (pdfium
reports encryption) and say "This PDF is password-protected" (a password
prompt can come later). *Files:* `features/documents/pdf/pdf_import_flow.dart`,
`pdf_relink_flow.dart`.
*Done:* `pdf_open_failure.dart` tells `PdfPasswordException` ("it’s
password-protected") from damaged files, in import and relink.

### Platform-specific: desktop keyboard, split view

✅ **P1-12 Desktop keyboard: the library and editor miss basics.**
- Editor: no Ctrl/⌘+A (select all exists: `editor_gestures.dart:66`,
  `content_tools.dart:114`), no arrow nudge of a selection (arrows turn pages
  even with a selection: `editor_shortcuts.dart:76-79`), and no Ctrl+= / − / 0
  zoom in paged notebooks (only canvases bind them).
- Library: only Delete trashes (`library_screen.dart:188`; no ⌘⌫ on Macs), no
  F2 rename; arrow keys between cards rely on Flutter's default directional
  focus (not checked with a real grid).
*Done:* Ctrl/⌘+A selects all on the page (or in view); arrows nudge a
selection 1 pt (Shift 10 pt), a burst of nudges (≤ 1 s apart, nothing else
edited between) one undo step, and only turn pages without
one; +/−, Ctrl/⌘+= / − and Ctrl/⌘+0 zoom paged notebooks; F2 renames and ⌘⌫
trashes the focused notebook; all in the shortcuts sheet. Arrow keys between
library cards still use Flutter's directional focus.

*Fix:* bind them (arrows nudge 1 pt, Shift 10 pt, as one undoable move while a
selection exists) and list them in the shortcuts sheet. *Files:*
`features/editor/editor_shortcuts.dart`, `tools/content_shortcuts.dart`,
`features/library/library_screen.dart`, `features/settings/keyboard_shortcuts.dart`.

✅ **P1-25 A parked pane and the second pane's header are unclear.** `split_parked_portrait_*`:
the parked pane is an unlabelled pill cut at the bottom edge; `split_*`: the
two panes' headers differ (the second has ✕ and a title, the first no title
while tabs show), and the tab strip shows the right-hand notebook as an
inactive tab. *Fix:* a labelled chip "Biology · in split view" with Show;
show the title in both panes; mark both split notebooks in the strip.
*Files:* `features/editor/split/*`, `chrome/parked_pane_notice.dart`,
`tabs/notebook_tab_strip.dart`.
*Done (fix/followups-1):* the pane on screen shows a chip "“Biology” in split
view · Show" while the other is parked (with Stop while it records;
`split/parked_pane_notice.dart`). *Left open:* the title in the first pane's
bar and marking both split notebooks in the tab strip (the strip and bar
were being reworked on fix/editor-chrome-r4 at the same time).
*Done (fix/editor-followups):* both panes' bars show their notebook's title,
and the strip marks both split notebooks with a split glyph.

✅ **P2-32 Dragging a selection across panes.** `split_drag_*`: the dragged ink is
a full-size, full-opacity copy over the target, and the target goes flat grey
in dark. *Fix:* 60 % opacity preview, a tinted (not grey) drop target.
*Files:* `features/editor/split/*`.
*Done (fix/followups-1):* the preview is drawn at 60 %; the drop target is
tinted with the accent and its chrome is no longer dimmed while a drop
would land there (a dimmed bar over a light canvas read as flat grey in
dark); the "Drop to copy here" pill uses the text roles and `Shadows.low`.

### Accessibility and simplification notes

- Contrast: focus-mode exit (P1-2), the "New…" tile in dark (P2-19), planner
  labels (P2-15) and the disabled Export in dark (P2-27) fall under 3:1.
  ✅ P2-19, P2-15 and P2-27 (fix/a11y-tools); P1-2 is fix/editor-chrome's.
- ✅ Accessibility pass (fix/a11y-tools). `test/accessibility_test.dart` runs
  Flutter's guidelines (tap targets: 48 dp on phones, 44 elsewhere; labelled
  tap targets; WCAG text contrast in the test font) on the library, settings,
  editor, every tool popover, the export sheet, the template dialog and the
  new-notebook dialog, phone and tablet, light and dark, and at 2× text.
  Fixed: tool buttons carried a second, unlabelled long-press node and a
  40-dp hit area (now 48 on touch, the visual stays 40; Insert too); notebook
  cards were an unlabelled tap target (now one node: title and caption,
  selected while selecting); the phone ⊕ had no label; settings switches had
  no label (a row that toggles reads as one control); the sidebar announces
  the current section, and folders expand with a screen-reader action
  (Expand / Collapse) instead of the 22-dp chevron; colour swatches and
  slots say colour names ("Colour 1, dark blue") rather than hex; "Custom"
  is a full target on touch; folder tiles grow with large text (they
  overflowed at 2×). A focus ring (`ui/focus_ring.dart`, accent, 2 dp) follows
  keyboard focus everywhere; touch and mouse never show it.
- ✅ **A11Y-1 Small targets in the tablet library sidebar.** Sidebar rows are
  40 dp (42 with spacing), New folder 40, the footer's Settings and Sync
  40, the search field 40: under 44 on touch tablets. At 2× text the footer
  squeezes the Settings label away. *Fix:* rows and footer buttons
  `Targets.of(context, 40)` on touch; the footer stacks at large text.
  *Files:* `ui/sidebar_item.dart`, `features/library/library_sidebar.dart`,
  `library_header.dart`.
  → ✅ Rows, New folder, the footer's Settings and sync status, and the search field are
  `Targets.menuRowHeight` (48 on touch, 44 with a pointer); at large text the footer stacks
  (Settings, then the sync status with its caption). Allowlist entries removed.
- ✅ **A11Y-2 Settings segmented buttons shrink on phones.** `ShrinkToFit`
  scales "Draw with" and "Side button" down to fit 390 dp (to about 38 dp
  high, smaller text), more at large text. *Fix:* below a width, a menu or
  radio rows instead of a segmented button. *Files:* `ui/segment_label.dart`,
  `features/settings/writing_settings.dart`.
  → ✅ `FitSegments` (`ui/fit_segments.dart`): a segmented button that doesn't fit its room
  stacks its segments (vertical `SegmentedButton`) at full text size and 48-dp height (Theme,
  Draw with, Side button, Toolbar). Allowlist entry removed; so is the card ⋯ one (48 dp on
  touch since fix/library-r4).
- Targets: library ⋯ buttons (P2-23); the phone cover row of ten swatches is
  34 dp each (5 × 2 on phones, P1-18).
- Simplify without losing parity: drop the spacing presets in paper options
  (P1-20); one "Audio" row in the phone ⋯ (P2-2); drop "Outline" from ⋯ (P1-10);
  drop the toolbar pair from View ▸ (P2-3); drop the shape-kind button or the
  kind grid (P1-5); "Import PDF…" only in ⊕▾ and the empty state, not in the
  new-notebook sheet (P2-19).

---

## Screenshot sweep after the redesign (all suites, phone / tablet / desktop, 1.3× text)

- ✅ Toolbar: a tool without quick controls (lasso, text) left a divider
  trailing into nothing → hidden (`StripDivider`). Quick controls cut off by
  a narrow bar fade at the edge (`ScrollFade`).
- ✅ Tool switcher: Insert's label rode 3 dp above the tools' → level.
- ✅ Text format bar on phones: the cut showed as a double divider → fades.
- ✅ Selection pill ⋯ → Link… opened its menu over the pill → below ⋯.
- ✅ Outline rows: the current page's highlight ran edge to edge → 8 dp in;
  row menus ⋮ → ⋯ (outline, recordings) like every other row.
- ✅ New notebook (wide): the paper row overflowed the form by 18 dp → fits.
- ✅ Library at 1.3× text on a phone: card captions cut ("1 pa…") → the
  caption takes the full width under ⋯; folder names cut ("Sket…") → one
  folder column.
- ✅ Settings: "Up to date: 0 lines recognised." → "no handwriting yet".
- ✅ A phone held sideways (844 × 390) was never tested: the empty library's
  button was pushed off screen and Go to page overflowed → windows under
  520 / 480 px drop the picture, the new sheet's preview and the page strip.
  `short_window_test` now opens the main surfaces at that size.
- ✅ Keyboard shortcuts had no list → a reference (Ctrl/⌘+/, Settings).

## Peeking page indicator (REDESIGN phase 5)

- ✅ The page control is now a compact `3 / 12` pill on every screen. It
  appears when the pages move, fades after 1.5 seconds and leaves no
  permanent bottom inset. Tap it to enter a page number; long-press for
  the overview. The page commands live in ⋯ → Page, and adding a page
  with a template or PDF is in Insert ⊕. The freed strip goes to the
  page, so pages on wide screens re-fit slightly (their goldens were
  refreshed); phones centre the pill, wider screens tuck it bottom-right.
- ✅ Page Up / Page Down and the arrow keys still turn pages in single-page
  flow; the indicator itself no longer repeats those controls.
- ✅ The canvas's persistent Fit button stays for discoverability: the zoom
  pill is hidden at rest, so removing Fit would leave no visible way to
  reach its menu without first zooming. Make that menu discoverable before
  removing the button. → The zoom pill now peeks like the page indicator:
  when the canvas opens and while the view moves (pans too), so its menu
  (with Fit content, also Shift+1) is found; the Fit button is gone.
- ✅ Go to page (`document/go_to_page_dialog.dart`) has the spec's number
  field over a thumbnail strip: typing a number rings and scrolls to that
  page, a thumbnail tap goes there at once, and a number out of range
  can't be submitted. Ctrl/⌘+G opens it as a keyboard route besides the
  indicator tap (still one menu home, SIMPLIFY #24). The page is followed
  by id, so a sync that reorders pages meanwhile still lands on the page
  picked.

## Library and settings redesign (`feat/library2`, REDESIGN phases 7 and 8)

Reviewed from the `library_`, `flows_`, `organise_` and `app_surfaces*` suites
(phone 390, tablet portrait 800, tablet 1280, desktop 1440; light and dark;
1.3× text) and the `search_library*` goldens.

- ✅ **Navigation:** sidebar (248 dp, `chrome` + hairline) from 840 dp, the same
  content in a drawer below; `Breakpoints.medium` is 840, so 800-dp tablets in
  portrait get the drawer and full-height sheets.
- ✅ **Header:** title (breadcrumbs above it in folders) with a caption; a 280-dp
  search field when wide, a 🔍 that opens the field over the title when narrow;
  ⊕▾ (New notebook, New canvas, Import PDF…, New folder…; wide only) and ⇅ View
  (Last edited / Created / Name, Grid / List, Select…). Both are `MenuIconButton`s
  (`showMenuBelow`), not `PopupMenuButton`s. Shortcut hints show in menus only
  where a keyboard is likely.
- ✅ **Grid:** covers of about 150 dp (columns stretched to the width), `raised`
  (a shadow in light mode, a hairline in dark), a two-line title and a caption;
  ⋯ by the title fades in on hover or focus and always shows on touch. Folders
  are a wrapping row of equal compact tiles (36-dp folder glyph in its colour,
  name, count). The "New…" tile is a quiet plate with an accent +.
- ✅ **New notebook:** one column (title; Notebook / Canvas; six recent papers +
  "All templates…" → the template picker; ten cover colours in one row; page size)
  with the preview beside it when wide and a 120-dp strip on phones. Recent
  papers are remembered (`AppPreferences.recentPapers`).
- ✅ **Desktop:** hover states on cards, folders and rows; right-click menus;
  Ctrl / ⌘-click toggles a notebook into the selection, Shift-click selects a
  range, Ctrl+A selects everything shown, Esc ends selection; Select… is also in
  each card's menu.
- ✅ **Task sheets:** folder (new / edit) and move are `showDialogOrSheet` task
  sheets with ✕; the handwriting language is a task sheet instead of a
  `SimpleDialog`. No `showModalBottomSheet`, `AlertDialog`, `SimpleDialog` or
  `PopupMenuButton` is left in `features/library`, `features/settings` or
  `features/search`.
- ✅ **Search results:** flat rows split by hairlines, page chips `xs` on
  `surfaceContainerHigh`; an empty result offers Clear search.
- ✅ **Settings:** one centred column (640 dp): General (theme: System · Light ·
  Dark), Writing (Draw with: Automatic · Stylus · Both; side
  button; tap to undo and redo; toolbar), Handwriting (search, language; the
  model row only until it is downloaded), Sync (with Sync now), Storage (web),
  About (version: 7 taps open Ink Lab, kept in release builds; licences).
  Segmented controls trail on wide rows and go below the text on narrow ones.
- ✅ **Performance:** the grid's columns come from a `SliverGridDelegate`
  (`CoverGridDelegate`) instead of a `SliverLayoutBuilder`, which rebuilt every
  card on every scroll frame (75 → 4 card builds a frame with 200 notebooks);
  covers requested last render first. `test/perf/library_perf_test.dart` pins it.
- ✅ Phones create folders only from the drawer (no ⊕▾ there, by the spec); a
  long-press on the FAB could offer New folder. → A long press on ⊕ offers
  what ⊕▾ does on wide screens: notebook, canvas, PDF, folder.
- ✅ The sidebar shows sync as an icon beside Settings, not yet the "Synced 2m"
  caption of the spec's sketch. → It reads "Synced 2m" / "Syncing…" / "Sync
  failed" / "Sync off" beside the icon (`syncCaption`, refreshed every 30 s).

## Library and dialogs, round 4 (`fix/library-dialogs`)

Reviewed from the `library_`, `organise_`, `flows_`, `app_surfaces*`,
`templates_` and `export_` suites (phone, tablet portrait and landscape,
desktop; light and dark; 1.3× text). There were two review passes, and the
second one checked the first one's fixes.

- ✅ **Dialog actions:** `DialogActions` (in `AppDialog`) keeps the
  buttons in one end-aligned row while they fit. Otherwise it stacks them
  full width, primary on top, each at least 48 dp. At large text,
  `AlertDialog` narrowed the content's side padding but not the actions'.
  `AppDialog` undoes that, so fields, text and buttons share one edge.
- ✅ **Cancel everywhere:** `runWithProgress` dialogs (Rendering page,
  Adding image) now have Cancel. Cancel closes the dialog at once and
  drops the result. Importing a template is cancellable and stops before
  it stores anything. The progress dialog is as wide as the other
  dialogs. Its track shows on dark dialogs.
- ✅ **Convert to text:** after a failed recognition the dialog offers
  Try again.
- ✅ **⊕ (FAB):** it shows only in the library and its folders. It hides
  in favourites, the trash, search and selection, and when the empty state
  offers New. It now uses the primary colours, so dark mode matches the
  other primary buttons.
- ✅ **New notebook:**
  - Phones: the sheet has rounded corners (its own Material had squared
    them). The preview scrolls with the form.
  - Tablets in portrait: the sheet sizes to its content (it had a 350-dp
    gap).
  - The dialog is 720 dp tall, so the orientation row is no longer cut.
  - The footer has a hairline over the scrolling form.
- ✅ **Cover sheet:** one row of ten colours, as in New notebook and the
  folder sheet. It had 9 + 1 on desktop and a grid leaning left on
  phones. On phones it has a single full-width Apply; ✕ cancels.
  `EvenGrid` now prefers 5 + 5 to 9 + 1 everywhere.
- ✅ **Library:**
  - Dark folder tiles: the hairline no longer narrows the name
    ("Sketch…").
  - Selected covers keep their colours: a ring and check only, no blue
    wash.
  - Empty states sit a little above the middle.
  - The phone trash caption no longer truncates.
  - Empty trash… has its ellipsis.
  - New folder from the drawer closes the drawer first.
  - At large text the sidebar's sync caption gives way to "Settings".
- ✅ **Chips:** on dialogs and sheets, unselected chips were filled with
  the screen surface (a chip's own `Material` falls back to
  `canvasColor`), so they looked like dark holes in dark mode.
  `ChipSurface` fixes this in the template chooser, the paper options and
  Convert to text.
- ✅ **Template search:** a search looks through every category, so the
  chips show All. Choosing a category ends the search.
- ✅ **Settings:**
  - A pinned "Settings" bar on every size, aligned to the column, with a
    hairline once scrolled. Content was cut under an empty bar on wide
    screens.
  - "Sync is off" is a plain status line, not a filled pill that read as
    a field.
  - "Draw with" is Automatic / Stylus / Both. It trails like the other
    choices and is no longer shrunk to a smaller size than them.
  - Copy: "then choose Convert to text".
- Not done (judged minor or out of scope):
  - Two snack bar issues. On desktop the snack bar centres on the window
    rather than the content pane. A screenshot showed the list clipped
    above the snack bar (right after trashing the last card).
  - "Select…" keeps its ellipsis (it enters a mode).
  - On tablets at 1.3× text, "All templates…" breaks mid-word.
  - Export sheet details (labels inset 8 dp, the footer status wrapping)
    are left to the export owner ➡️.

## Toolbar redesign (`feat/toolbar`, REDESIGN phases 3–4)

User feedback: "the UI needs an entire overhaul — especially the toolbar and in
notes". Reviewed from `test/screenshots/toolbar_screenshot_test.dart` (phone
390, tablet portrait 800, tablet 1280, desktop 1440; light and dark; every
tool's options popover; Insert and ⋯ menus; floating; 1.3× text) and the
`workspace_` and `editor_` suites.

- ✅ **One home per control.** The top bar keeps navigation (←, ▦, title),
  the tools when they fit and the actions (🎙▾, ↶ ↷, ⋯); bookmark, insert
  image, search, export, focus and split moved to ⋯, Insert ⊕ and shortcuts
  (Ctrl/⌘+E export is new). The tune and palm buttons, tool names,
  favourite pens and edit mode are gone.
- ✅ **Docked by width, not by guess.** Inside the bar on wide panes, a row
  attached under it on portrait tablets and split panes, a bottom row on
  phones. The strip's width is reserved, so switching tools never moves a
  button or relays out the page.
- ✅ **Calm selection.** A neutral plate slides between tools; slots show a
  2-px `onSurface` ring; widths are neutral dots at real size; dark inks get a
  firmer edge on dark chrome.
- ✅ **One options popover** for every tool (tap the active tool, or the
  selected slot): colour (palette, recent, custom) and width of the selected
  slot, slot counts (1–6 each), feel collapsed.
- ✅ **Fast:** switching tools, picking slots and opening the popover rebuild
  only the toolbar's parts (checked by a rebuild-count test).
- ✅ The floating palette doesn't snap to edges or go vertical yet (phase 6).
  → Released within 48 dp of an edge it snaps to that edge's middle; at the
  left or right it runs down (tools, then slots; scrolls in short panes).
- ✅ The page navigator is still the old pill (phase 5: peeking indicator).
  → Replaced by the peeking `3 / 12` indicator (see the top of this file).
- ✅ Keyboard: no arrow-key navigation inside the tool cluster. → ← / →
  move between toolbar controls while one has focus (Space picks).

## Paper and laser pointer (`feat/paper`)

User feedback: page settings lacked customisation (dot spacing, colours); the
laser pointer was not customisable and "crazy slow". Reviewed from
`test/goldens/paper_looks.png`, `template_picker*.png` and `laser.png`.

- ✅ **Paper options**: one compact "Paper" section in the template picker
  (change page / all pages, add page, new notebook, canvas background): an
  actual-size preview, paper colour (presets + custom), pattern colour
  (Auto + presets + custom) and opacity, spacing (slider + presets such as
  narrow / college / wide), line weight or dot size, margin line and header
  chips — only the controls the template uses, with Reset.
- ✅ Dots no longer sit on the page edges: dotted pages are centred.
- ✅ **Laser pointer**: dot or trail, six colours + custom, size and trail
  length in its options popup; soft glow with a bright core on a smooth,
  fading, thinning curve. Fast: no blur filters, a ring buffer and a
  self-contained repaint (see ARCHITECTURE *Editing tools*).
- ✅ The laser dot shows only while pressed; a hover dot for mouse
  presenters would be nice. → With the laser and a mouse, the dot follows
  the pointer without a press (no trail; frames only while something
  fades); it fades on leaving the page or switching tools.

## Workspace features (`feat/workspace`)

Split view, the customisable toolbar, presentation mode and double-tap zoom,
reviewed from `test/screenshots/workspace_screenshot_test.dart` (split view
tablet 1280×800 and desktop 1440×900, light and dark, with the split menu and a
selection dragged across; toolbar with favourites and in edit mode on tablet and
phone; the phone tool switcher with favourites; presentation, light and dark).

- ✅ Split panes take the compact chrome below 640 px (tablets in landscape):
  phone top bar with the tab switcher, one-row toolbar. The 640–720 px gap
  where the wide bar showed neither tab strip nor switcher is closed (the strip
  starts at the compact width).
- ✅ Dragging a selection across shows the target outlined, *Drop to copy here*
  and a preview of the copy at the target's zoom (the source clips at its edge).
- ✅ Edit mode reads on phones (tools on their own row; favourites, Reset and
  Done below) and favourite glyphs are outlined, so dark inks show in dark mode.
- ✅ Fitted pages re-fit when the chrome goes away in focus mode (the new
  scroll bounds used to nudge the view and skip the re-fit).
- ✅ The second pane's top bar is shorter than the first's when the first shows
  the tab strip (desktop). → It shows an empty strip-coloured band; the bars line up.
- ✅ Reordering in edit mode needs a long press, also with a mouse. → A mouse or
  trackpad drags at once (`ReorderStartListener`); touch and stylus keep the hold.

### Split view robustness (`fix/split`, QA round 2)

Reviewed from `split_same_tablet_*`, `split_parked_portrait_*` and
`split_restored_tablet_*` (one notebook in both panes; turned to portrait and back).

- ✅ Turning a tablet to portrait parks the second pane instead of closing it: a
  running recording continues and its undo history survives; landscape shows it again.
- ✅ One notebook in both panes: edits, undo and redo show in the other pane at once
  (no reload every 250 ms while drawing), and one history means the other pane's undo
  can't resurrect erased ink.
- ✅ Recordings list in both panes; only one recording at a time (the other notebook
  says *Already recording in “…”*).
- ✅ Renames and new paper show in both panes; PDF caches are shared.
- ✅ A second pane whose notebook was deleted elsewhere says so in the first pane and
  leaves the first pane's dialogs open.
- ✅ A parked pane gives no hint in portrait (e.g. its recording runs unseen; the first
  pane only learns of it when it tries to record). → While the parked pane records,
  the pane on screen says "Recording in “…”" with Show (swaps the panes) and Stop.
- ✅ A selection or a text box being edited in one pane hides those items in the other
  view of the same notebook until it ends. → The owner (selection, text editor) gives
  the surface what to draw in their place (`SurfaceModel.setLifted`); other views
  paint it over their ink, moving and retyped live; a view never repaints its ink for
  its own selection's drags.

## Editor polish (`fix/editor-ux`)

Reviewed from `editor_*`, `editor_surfaces*`, `toolbar_` and `workspace_`
(phone, tablet, desktop; light, dark; 1.3× text) against GoodNotes 6 and
Notewise. The open editor items of round 3 are closed above; besides them:

- ✅ Search: stepping to the first match on a phone left it under the
  result list (the top of page 1 can't scroll lower) → the list folds.
- ✅ Text boxes: outline, handles, caret and selection were the pale dark
  theme accent on white paper → ink blue in both themes, like the lasso.
- ✅ Text format bar on phones: B, I, U… were hidden behind an unhinted
  scroll → two rows (font "Aa", size, paragraph, ⋯ over the character
  formats and ✓); very narrow windows still scroll, with a fade one button
  wide so a cut always shows.
- ✅ ⋯ menu: submenu arrows were Material's filled triangles → rounded
  chevrons; reopening always starts at the top level.
- ✅ Zoom menu showed "Shift+1" and "Home" on phones → hints only where
  the ⋯ menu shows them.
- ✅ Text tool popover: 15 swatches wrapped 9 + 6, the title touched Size
  → the whole palette in two even rows, spaced like the other popovers;
  the laser's sliders no longer touch its swatches.
- ✅ The recording pill can cover the "Add page" footer at the end of a
  document → the floating pill and player add room past the end
  (`DocumentController.setEndRoom`); scrolled to the end, the view stays
  at the end, so the footer moves clear (`fix/editor-chrome-r4`); short
  screens and zoomed-out documents too (tested on `fix/editor-followups`).
- ✅ A text box typed near the bottom of a phone can sit under the docked
  format bar → it pans up just clear of the bar when the box or the bar
  (keyboard) changes, never on the user's own pans (`TextBoxReveal`).
- ✅ Menu rows are 44 dp on touch tablets → `Targets.menuRowHeight` by input:
  48 on touch, 44 with a pointer (`TouchMenus`, was `PhoneMenus`).

## Round 3 — whole app (`feat/ux3`)

Scope: every surface. The library, settings, dialogs, import and export
flows, the editor chrome and the editor surfaces (search, convert to text,
audio, images, lasso, shapes, menus, tabs, overview, snack bars, error
states). Pen toolbar internals (feat/pen3) and text boxes (feat/text) are
reviewed for style tokens only; issues there are routed ➡️.

Method: about 600 screenshots from `test/screenshots/` (`app_surfaces*`,
`editor_surfaces*` and the earlier suites). Sizes: phone 390×844 @2x,
tablet portrait 800×1280, tablet landscape 1280×800 and desktop 1440×900,
each in light and dark, plus 1.3× text. All were read and compared against
GoodNotes 6 and Notewise. Those apps have one icon style, one dialog
pattern, sentence-case copy, menus with destructive items last and red,
nothing hidden behind floating chrome, and calm, consistent motion.

Status: ✅ fixed in `feat/ux3` · 🟡 partly fixed · ⬜ open · ➡️ routed.

### P0 — broken

1. ✅ **The lasso selection toolbar overflows on phones** (8+ actions: overflow
   stripes, Delete clipped; `e_convert_*_replaced`). → Keep the main
   actions and move the rest into a "More" menu when the row doesn't fit.
2. ✅ **The convert-to-text loading dialog fills the whole screen height**
   (`e_convert_loading_*`). Its error and empty states still show disabled
   Copy / Replace and offer no retry.
3. ✅ **The settings toolbar-position control breaks words at 1.3×**
   ("Botto / m"; `s_settings_editor_phone_light_large`).
4. ✅ **Dialog actions overflow on phones into a right-aligned stack with
   Cancel on top** (import ask, convert to text). → One dialog pattern
   (`AppDialog`): when the actions are stacked, the primary goes on top
   and Cancel at the bottom.

### P1 — inconsistent or unpolished

5. ✅ **Floating chrome hides content.**
   - The FAB covers the last search result and, at 1.3×, the last card
     title.
   - The empty folder shows the FAB *and* "New notebook here" (two
     primary actions).
   - Snack bars cover the editor's bottom toolbar and page pill, and span
     the full width of a 1440 px window.
   - → Results get bottom padding. The FAB is hidden while an empty state
     shows its own call to action. Snack bars are capped at 560 px on wide
     screens and lifted above the editor's bottom chrome.
6. ✅ **The phone Trash header squeezes search to "Sea…"**: the
   "Empty Trash" button sits in the search row. → An icon button on
   compact widths, tinted red because the action is destructive.
7. ✅ **Copy.**
   - Title Case: "Empty Trash", "Move to Trash".
   - Ellipses are missing on items that open a dialog (Rename, Change
     cover, Edit folder; menus elsewhere already use "…").
   - "Rename" in the library but "Rename notebook…" in the editor.
   - Snack bar punctuation is mixed ("Page 1 deleted" vs "…one page.").
   - Section labels are mixed: "FOLDERS" and "BASIC" in capitals,
     "Folders" elsewhere.
   - Sync talks to developers ("See server/README.md").
   - A "→" glyph is missing from the fonts.
   - Double brackets: "Automatic (English (US))".
   - → Sentence case everywhere and "…" for every command that asks
     something first. Snack bars are fragments without a full stop unless
     there are two sentences. Section labels are sentence case
     (`SectionLabel`).
8. ✅ **Icon style is mixed.** Filled `_rounded` glyphs sit next to
   `_outlined` line glyphs in the same bar or menu (layout toggle, "All
   pages", lasso bar). A magic wand stands for "Erases". `crop_free` and
   `fullscreen` look identical in one menu. → Rule: action and menu icons
   use outline glyphs from the rounded family (`*_outline_rounded` /
   `*_border_rounded`, else `*_outlined`). Filled glyphs only mark a
   selected or active state (navigation, favourite, bookmark).
9. ✅ **The sort menu is a raw `CheckedPopupMenuItem`**: bold text, a grey
   selected row and different padding from every other menu. → `MenuRow`
   with a check.
10. ✅ **Destructive items are not red**: "Delete page" in the Page menu,
    "Empty Trash" (primary blue).
11. ✅ **Dark-mode contrast.**
    - Dark dialogs use `surfaceContainerHigh`, the same colour as the text
      field fill, so fields have no edge (Search templates, Recognised
      text) and the "Current" pill disappears in the move dialog.
    - Navy swatches vanish on dark surfaces.
    - The light switch thumb's check is pale on white.
    - The empty-canvas hint is about 2:1 on paper.
    - → Fields use a fill that contrasts with any container. `ColorDot`
      gets a hairline ring when it is close to the surface colour. The
      switch icon uses `primary`. Hint colours come from the paper, not
      the UI theme.
12. ✅ **Dialog headers differ.** Some have a tinted icon and a centred
    title, others are left-aligned, and the progress dialog has a bare
    hourglass. Template sheets disagree on footers: "Change template" has
    no Cancel, and the primary labels and icons vary. → Tinted
    `DialogIcon` for confirmations and progress; every sheet has Cancel
    plus one filled primary. (Checked again: all dialogs go through
    `AppDialog`; Change template has Cancel, Apply to all pages and the
    filled Apply to this page.)
13. ✅ **The editor search bar squeezes the query to about 2 characters on
    phones** (counter plus 4 icon buttons in one row). "0 matches" and
    "No matches" show at the same time.
14. ✅ **The template picker footer truncates at 1.3×** ("Apply to all p…").
15. ✅ **Phone folder cards have no "⋯" button** (tablets do); the menu is
    long-press only.
16. ✅ **The zoom preset menu is misaligned**: percentages have no leading
    slot and the current zoom is not marked.
17. ✅ **Settings sync**: the URL error shows next to the button instead of
    under the field, and the phone settings bar is empty once scrolled.

### P2 — refinement

18. ✅ Motion: 26 literal durations in features/ → `Motion` tokens.
19. ✅ Phone menus show desktop shortcut hints ("Ctrl+F", "F11").
20. ✅ Menus sit flush against the screen edge (no 8 dp margin). → Popup
    menus keep 8 dp; tall chrome menus clear the system bars by 8 dp
    (`menuReservedPadding`); the chrome's `MenuAnchor`s (⋯, Insert, zoom)
    keep 8 dp from the sides too (`MenuEdgeMargin`: the anchor's padding
    never reaches its overlay, but display features do, so two 8-dp side
    strips are added as features for those menus only).
21. ✅ Colour dots (40 dp) and selection
    checkboxes (28 dp) are under 48 dp on phones. → `EvenGrid(touchTargets:)`
    gives swatch cells 48 dp on phones (visuals unchanged, the whole
    cell takes taps); the checkmark never was a target (the whole cover is).
22. ✅ The playback bar truncates the title (title and time share one row);
    → the title wraps to two lines (time and Trim stay on the first), the
    whole title on hover;
    ✅ the paused recorder shows "Paused" in place of the level meter and
    Resume is a play icon.
23. ✅ List view shows the favourite star twice (cover badge plus column).
24. ✅ A missing PDF background renders as a silently blank page (should be
    a placeholder with a "Relink…" action). → Hatched "PDF page
    unavailable" pages and thumbnails, and an editor notice with Retry and
    Relink… (same file restores it; a different one replaces it page for
    page after a confirm, refused if it has too few pages).
25. ✅ Canvases can't be exported (no entry point). → ⋯ → Export… and
    Ctrl/⌘+E export the whole drawing as one PDF page or PNG, sized to it
    with a margin, the background grid aligned as on screen.
26. ✅ Desktop: folder cards and the notebook grid end at different right
    edges, and titles are limited to one line. → Checked in
    `library_desktop_light`: both stretch to the same gutters (equal-width
    tiles filling each row), and notebook titles wrap to two lines.
27. ✅ Bookmark colour differs between the editor (orange), the overview
    (brown or peach) and the app bar (primary). → One colour,
    `Palette.bookmark`: the page ribbon, overview tiles, Go to page strip,
    the selected Bookmarks filter and the link picker.

### What changed (round 3)

Shared building blocks in `app/lib/ui`, so screens stop restyling
things locally:

- `AppDialog` is the one dialog pattern: a tinted `DialogIcon` header for
  confirmations, progress and downloads, actions that stack with the
  primary first, two-line titles. Every `AlertDialog` now goes through it.
- `messages.dart` (`showMessage` / `appSnackBar` / `MessageInsets`) is
  the one snack bar. It floats, is at most 560 px wide and centred, and
  sits above the editor's bottom chrome. Every `showSnackBar` call goes
  through it. ✅ Messages from the audio player or ink replay (e.g. "Trimmed
  … · Undo") sit above the player instead of covering it (`AudioLayer`
  nests a `MessageInsets` that adds the player's height).
- `FilledFieldBorder` keeps the floating label inside filled fields. The
  field fill is a tint of the text colour, so fields show on any
  container.
- `MenuRow` gained `checked` and `enabled`, and the icon is optional. The
  library sort menu uses it.
- Small shared widgets:
  - `SectionLabel`: sentence-case group headings in the library,
    sidebar and template gallery.
  - `SegmentLabel` / `ShrinkToFit`: segmented controls never wrap
    mid-word.
  - `EvenGrid`: swatches and icon tiles laid out in full, even rows,
    with intrinsic sizing so it works in dialogs.
- Theme changes:
  - Outlined unselected chips.
  - The switch check icon in `primary`.
  - A firmer `ColorDot` ring when a swatch is close to the surface
    colour.
- `Motion` tokens are documented, with `travel`, `exit` and `move`
  added.

The remaining fixes are listed against the items above. Two review passes
of the renders came after the fixes: the first looked for regressions,
the second for what is left.

### Still open after round 3

- ✅ 12: the template pickers (Add page, Change template, Canvas background)
  and the cover sheet are bottom sheets with drag handles on tablets and
  desktops. Elsewhere those sizes use centred dialogs (New notebook,
  Export, Folder). → All of them go through the shared `showDialogOrSheet`
  (centred dialog from 720 dp wide, sheet with drag handle on phones).
- ✅ Progress dialogs have no Cancel (also item 17 of round 2).
  Convert-to-text errors only offer Close, with no Try again (it would
  need to re-run recognition). → Every progress dialog has Cancel (see
  "Library and dialogs, round 4"); a failed conversion offers Try again.
- ✅ Stacked dialog actions are end-aligned at their own widths, so they
  look ragged (Change template on phones). Full-width stacked buttons
  would need a custom actions layout. → `DialogActions` in every
  `AppDialog`: a row when they fit, else full width, primary on top.
- ✅ New-notebook sheet on phones at 1.3×: the preview takes most of the
  screen, leaving about one row of templates. On phones the preview
  should collapse. → The strip scrolls away with the form (88 dp at
  large text).
- ✅ The phone library shows both the "New…" tile and the "New" FAB. → Tile on wide
  screens, FAB on phones (never both).
- ✅ The FAB still shows over the empty Favourites and empty search states,
  which offer no create action of their own. → ⊕ shows only in the library
  and its folders, not while searching or when the empty state offers New.
- ✅ Selection checkmarks on covers: unselected rings are low-contrast on
  light covers, the style differs between light and dark, and targets
  are 28 dp. → A dark ring on white in both themes; the whole cover is the
  target.
- ✅ Editor search on phones: stepping to a match pans the page sideways.
  → Panning is per axis (an axis already showing the match never moves);
  matches land below the measured bar (with its list); phones fold the
  list when stepping.
- ✅ Lasso selection handles in dark mode are dark and filled on light
  paper. They should follow the paper, as the canvas hint now
  does. → Ink blue on paper white in both themes (selection, crop and,
  now, text boxes).
- ✅ The image crop bar overlaps the fit button on phones. → The Fit button
  is gone; the bar now keeps clear of the measured chrome (it sat on the
  phone toolbar above a tall image).
- ✅ The page submenu opens over its parent on phones (a drill-in or a sheet
  would suit phones better). → Phones drill into Page and View in place
  of the ⋯ menu, with a ‹ back row.
- ✅ The handwriting language picker is a `SimpleDialog`: no Cancel, and no
  hint that it scrolls. → A task sheet with ✕, opened at the current
  language, with an always-shown thin scrollbar.
- ✅ The paused recorder shows no "Paused" label, and Resume is a mic icon.
  → "Paused" replaces the level meter; Resume is a play icon.
- ✅ Template grid on phones: 3 fixed columns leave a gutter on the right.
  Paper-colour chips wrap 3 + 1 (also item 19 of round 2). → The gallery
  picks the column count whose tiles come closest to the preferred size and
  stretches them to fill the width; paper colours and page formats are
  `EvenChoices` (one even row, or two even rows when they don't fit).

### Accessibility (round 3)

- ✅ Targets: compact menus are 44 dp high (fine for pointer, tight for
  touch). Icon buttons are 48 dp. Swatch and selection controls are listed
  in 21. → Decided: menus stay 44 dp on tablets and desktops and 48 dp on
  phones (`Targets.menuRowHeight`). Rows are full-width bars, 44 dp meets
  Apple's minimum, and GoodNotes and Notewise use the same on iPad.
- ✅ Contrast: see 11. Body subtitles (`onSurfaceVariant`) are 5.6:1 in
  light and 7.4:1 in dark. The page pill's "1 / 1" in light is borderline.
  → The library and dialogs were checked again in round 4: dark chips,
  progress tracks and the FAB are fixed. The page pill is editor chrome
  and is routed there ➡️.
- Semantics: icon-only buttons have tooltips, which double as labels. The
  selection bar on phones is icon-only.

### Routed ➡️

- feat/text: ✅ the text format bar overflows on phones (Delete and Done are
  clipped) → two rows on phones, every control visible; text touches the
  box border; colour swatches are 22 dp.
- ✅ feat/pen3: dark ink swatches and colour underlines vanish on the dark
  toolbar (needs the `ColorDot` ring or the same rule); the phone tool
  switcher has uneven margins; the narrow bottom toolbar is clipped at the
  right edge. (Checked in `toolbar_*` and `editor_narrow_paged`: all fixed.)

---

## Round 2 — library, settings, documents (`feat/uxlib`)

Scope: library (grid/list, folders, search, trash, menus), new-notebook flow,
cover and template pickers, page overview, PDF import / export progress,
dialogs, settings. Editor chrome and the pen toolbar are owned elsewhere
(see "Routed to other areas" at the end).

Method: golden screenshots with real fonts (`test/screenshots/`, run with
`--dart-define=SCREENSHOTS=true`, output in `app/build/screenshots/`) at
phone portrait 390×844 @2x, tablet portrait 800×1280, tablet landscape
1280×800 and desktop 1440×900, light and dark, plus 1.3× text scale.
Compared against GoodNotes 6 and Notewise:

- **GoodNotes 6** — library grid of covers with title + date, a "New…" tile,
  a *Select* mode (move / duplicate / share / trash many), a full-screen
  "Create notebook" sheet with a big live cover + paper preview, cover and
  paper galleries and a size/orientation row; page overview ("Thumbnails")
  with a select mode and a bottom action bar, drag to reorder, an "add page"
  tile; settings as grouped lists with leading icons.
- **Notewise** — calm, dense grid; page count and last edit under each
  cover; create dialog with cover / template / size side by side and a
  live preview; templates grouped by category; clear progress for imports.

Status: ✅ fixed in `feat/uxlib` · ⬜ open · ➡️ routed to another area.

Screens covered by `test/screenshots/` (`library_*`, `flows_*`,
`overview_*`): library (grid, list, folder, search, trash, empty states,
selection), new-notebook sheet/dialog, template picker, cover sheet, rename /
folder / move / confirm / progress dialogs, page overview (+ selection),
settings — at the four sizes, light and dark, and at 1.3× text.

## P0 — broken or clearly unpolished

1. ✅ **New-notebook sheet overflows on tablet/desktop.** At 1280×800 and
   1440×900 the sheet runs off the bottom (Import PDF cut off); the paper row
   scrolls sideways with no hint; there is no live preview of what will be
   created (cover is a 84 px sliver, paper is a separate row). → Rebuilt as a
   responsive "Create" sheet/dialog: big live preview (cover + first page
   side by side), title, kind, then Cover / Paper tabs with full galleries,
   size + orientation chips, paper colour; dialog on wide screens, full
   bottom sheet on phones, sticky actions.
2. ✅ **Text scale 1.3× overflows** (folder tiles in the library at phone and
   tablet: fixed 64 px row extent). Settings "System" segment wraps mid-word.
   → Folder tiles size from the text scale; segmented labels never wrap.
3. ✅ **PDF import / export progress is a bare spinner** with no stage, no
   page count, no percentage: a 300-page import or export looks hung. →
   `runWithProgress` gained determinate progress (stage + "Page 12 of 300" +
   bar); exporter reports per page; import reports reading / creating pages.
4. ✅ **Page overview has no multi-select** (GoodNotes/Notewise both do): you
   can only act on one page at a time through a tiny "···" next to the
   number; the current page is only a 2 px border; no drag affordance; no
   "add page" tile; the bookmarks segmented control crowds the phone app bar.
   → Selection mode (tap to toggle, select all, bottom bar: bookmark,
   duplicate, delete), page-number chips, current-page badge, bookmark
   ribbons, lift + drop indicator while reordering, "Add page" tile,
   bookmarks filter chip. (Moved to `features/documents/overview/`; the
   editor's `page_overview.dart` re-exports it.)

## P1 — hierarchy, consistency, discoverability

5. ✅ **Card metadata is thin**: "09:52" alone — no "Today", no page count,
   kind only for canvases. → "Today 09:52 · 12 pages", "Yesterday",
   "3 Oct"; canvases say "Canvas".
6. ✅ **Dialogs are inconsistent**: rename is a bare 230 px field; folder
   dialog wraps 14 dots into a ragged second row; destructive confirmations
   have no icon; move dialog is a plain indented list. → `ui/app_dialogs.dart`
   (`confirmAction` with a tinted icon for destructive actions,
   `DialogBody` standard 400 px width), rename prompt with a disabled
   confirm while empty, folder dialog with a live folder preview and two
   even swatch rows, move dialog with tinted folder rows, a "Current" chip
   and chevrons.
7. ✅ **Template picker**: one flat wrap (labels small), size chips and
   orientation separate, no category grouping, no preview of the chosen
   page at its real shape. → Grouped sections (Basic, Ruled, Grid & dots,
   Special), larger tiles with a check badge, size + orientation in one row,
   sticky action bar.
8. ✅ **Settings grouping**: Input mixes stylus and gestures; gesture rows
   have no description; dropdown for stylus button is small and
   mouse-oriented; no leading icons (GoodNotes/Android settings use them);
   theme is a plain segmented control. → Sections "Appearance", "Stylus",
   "Gestures", "Editor" (toolbar position), "Sync", "About"; rows with
   leading icons and descriptions; theme as live light/dark/system
   previews; segmented control for the side button. (Since merged: Stylus,
   Gestures and Editor are one "Writing" section.)
9. ✅ **Empty states**: search-empty art is a saturated blue disc that reads as
   a button; "No results" offers no way out. → Softer art, "Clear search"
   action; folder-empty offers "New notebook here".
10. ✅ **Cover sheet** "Apply" floats alone at the bottom right; no Cancel; the
    preview doesn't show the title. → Uses the same cover colours and preview
    as the create flow, with Cancel / Apply.

## P2 — refinement

11. ✅ Trashed covers are 60 % opacity grey slabs: hard to recognise. → Keep
    the cover, desaturate it, show "Deleted 3 Oct".
12. ✅ Library grid had no *Select* mode for bulk move/trash (GoodNotes
    "Select"). → `LibrarySelection` + a floating action bar: select all,
    favourite, move, trash (with Undo); restore / delete forever in the
    Trash. Esc / back ends it; leaving the folder clears it.
13. ✅ No "New…" tile in the grid (GoodNotes). → `NewNotebookTile` first in the
    grid of the library root and folders (not in favourites, trash, search,
    selection mode or list layout); the FAB stays.
14. ✅ Settings on wide screens could use a two-pane layout (category list +
    detail) like GoodNotes on iPad. → Dropped: five short sections read
    better in one centred column on every screen.
15. ✅ Motion: shared-element transition from cover to editor (GoodNotes
    "opens" the notebook). → `NotebookOpenRoute`: the tapped cover grows
    into the screen, fades into the paper and the editor fades in; back
    shrinks it into the cover (wherever it is now), else fades.
16. ✅ Folder colours only; GoodNotes allows folder icons/emoji. → Won't do:
    folders keep colour only (icons were added, then removed in SIMPLIFY #43).
17. ✅ Long PDF imports/exports can't be cancelled (the progress dialog has
    no Cancel; needs cancellation in `PdfImporter` / `NotebookExporter`).
    → `runWithSteps(…, cancellable: true)` for import, insert, relink and
    export; a cancelled import discards its copy, an export saves nothing.
18. ✅ No export options sheet (page range, PNG resolution, flatten
    template) like GoodNotes' export dialog. → `ExportSheet` (dialog / bottom
    sheet): format, pages or range, templates & PDF backgrounds (PNGs at 288 dpi).
19. ✅ Paper-colour chips wrap to two rows on phones in the template picker.
    → Even rows (`EvenChoices`): four in a row when they fit, else 2 × 2.
20. ✅ Typing a search ends selection mode (selection is scoped to the
    place, search included); keep it if the selected notebooks match.
    → The place is the section and folder only: searching keeps selection
    mode and the selected notebooks that still match.
21. ✅ Template picker had one flat set of 10 templates. → Categories (Basic,
    Writing, Planners, Paper, My templates) as chips, search, planners with
    dates ("Add 31 pages"), an Import tile and per-template menu (rename,
    delete) for My templates; image templates fix the page size. Checked in
    `templates_screenshot_test.dart` (phone and tablet).
22. ✅ The template picker puts paper colour and size below the (now long)
    gallery; a side-by-side layout on wide screens would keep them in view.
    → On tablets and desktops the picker is a dialog with the gallery on
    the left and an options column on the right (preview, planner dates,
    paper colour, size, orientation), each scrolling on its own. Phones keep
    the stacked sheet. Checked in `templates_screenshot_test.dart` (phone,
    tablet portrait / landscape, desktop; light and dark).

## Accessibility notes

- Touch targets: card "More" buttons were 28 px → 36 px, and the card
  title now opens/selects too; page-overview "···" sits in a 40 px row and
  the whole tile is the target in selection mode.
- Semantics: cards announce title + date + page count; selection state is
  exposed (`selected`) on page tiles, covers, templates, kind cards and
  theme previews; the progress dialog is a live region with a value.
- Contrast: subtitle grey `#66666E` on `#F9F9F7` = 5.6:1 ✓; dark
  `#9F9FA9` on `#131316` = 7.4:1 ✓. Selected sidebar item in light uses
  `secondaryContainer` with dark text ✓.

## Routed to other areas ➡️

From `test/screenshots/editor_screenshot_test.dart` (the editor agents'
renders, reviewed next to the library):

Status of these in `feat/editorux2` (✅ done there):

- ✅ **Page overview batch delete**: `DocumentCommands.deleteMany` deletes the
  selection as one step with one Undo.
- ✅ **Canvas opens at the origin's top-left**: canvases reopen where they
  were left, else centred on their content (at most 100 %).
- ✅ **Title bar**: start-aligned on every size, with the folder as a
  subtitle (tap to rename). A title dropdown (move, export) is still open.
- ✅ **Fit width on landscape tablets**: page zoom *Automatic* keeps ≥ 55 % of
  the page visible (A4 on 1 280 × 800 now shows most of the page); *Fit
  width* and *Fit page* in the menu (Shift+2 / Shift+1), per notebook.
- ✅ **Toolbar**: groups (recessed width track, tonal disc for the selected
  slot, ≥ 40 px targets), optional tool names; the phone toolbar is one row —
  the active tool opens a tool switcher next to its quick controls.
- ✅ **Phone page pill** covered part of the page above the toolbar: it now
  peeks in while pages move and fades away.
- ✅ **Discoverability**: empty-canvas hint, a one-time pen side-button
  tip, repeated undos counted in the HUD, Escape closes
  chrome menus.
- ✅ Keyboard: chrome buttons are reachable with Tab but there is no
  "skip to canvas" or toolbar arrow-key navigation yet. → Arrow keys move
  along the toolbar, and Escape from any chrome control goes back to the
  page.
- ✅ **Motion**: opening a notebook animates from its cover (container
  transform in `NotebookOpenRoute`, see 15); reduced motion → plain fade.
- ➡️ **Export**: entry points should offer options (see 18); progress is
  already shown through `exportFlow`.
