# Len — UX/UI audit

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
| Eraser | On par, one gap | Whole stroke / partial / highlighter only / switch back; hover outline. **Missing:** scribble to erase |
| Lasso | **Better** | Tap or loop, move / resize / rotate, Style, convert to text, cut / copy across notebooks and pages, split-view drag |
| Shapes | On par, one gap | Hold to snap plus a Shape tool. **Missing:** fill |
| Text boxes | **Better** | Rich text, lists, checklists, rich paste from browsers / Word |
| Highlighter | On par | Behind ink, straight-line option. PDF text needs a finger (R7-1) |
| Undo / redo | On par | Buttons, two- / three-finger taps, keyboard |
| Library, folders, favourites, trash | On par | Nested folders, drag and drop, Undo everywhere |
| Recent notebooks / reopen last | **Missing** | R7-6, R7-7 |
| Tags | Removed: fine | Folders, favourites and full-text search cover it (SIMPLIFY #45). Don't bring tags back unless users ask |
| Search | On par | Titles, text, PDF text, handwriting (recognised on Android, synced to the rest) |
| Templates and planners | **Better** | Date-aware linked planners in 19 languages, custom templates |
| Page management | On par, one gap | Overview, reorder, multi-select. **Missing:** move / copy pages to another notebook (R7-9) |
| PDF study | On par | Text select, highlight, copy, links, outline, vector export. Pen-only selection missing (R7-1) |
| Audio | **Better** | Ink replay, trims, markers per burst of writing, crash recovery, background recording |
| Export / share | On par, one gap | PDF / PNG with ranges; not from the library (R7-8); no editable Len file |
| Sync | Different | Self-hosted only: great for the few with a server, absent for everyone else |
| Backup / data safety | **Missing** | No library backup; Android Auto Backup unconfigured (R7-12, R7-13) |
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
2. R7-12 Without sync, nothing says notes live on this device only, and there is no way to back them up.
3. R7-13 Android Auto Backup is on but unconfigured: it silently stops past 25 MB and would clone the sync identity.
4. R7-6 No recent notebooks: notebooks in folders are always 1–3 taps away.
5. R7-7 Nothing reopens where you were writing after the app is killed or restarted.
6. R7-9 Pages can't be moved or copied to another notebook.
7. R7-8 Export / share only exists inside the editor.
8. R7-2 On phones the one "previous tool" slot goes to the eraser that the S Pen button already gives.
9. R7-3 "Hold to snap" changes every pen stroke but lives in the Shapes options.
10. R7-14 Phones show no sync status anywhere outside the drawer; the editor never shows a failing sync.

### Writing

**R7-1 P1 · A pen can't select PDF text.** The text selection that Copy,
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

**R7-2 P1 · Phones: the only quick tool slot goes to the eraser the S Pen
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

**R7-3 P2 · "Hold to snap shapes" changes every pen stroke but lives in the
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

**R7-4 P2 · PDF "Highlight" uses whatever colour the highlighter last
had.** `PdfInteraction.highlightSelection` takes
`tools.configOf(InkTool.highlighter).color`
(`features/editor/pdf/pdf_interaction.dart:238-254`). The selection pill
has a single Highlight button (`features/editor/pdf/pdf_layer.dart:244-246`).
Students colour-code (definitions yellow, examples green), and changing
the colour means switching to the highlighter, changing its slot, and
selecting again. *Fix:* replace the button with the highlighter's quick
colours as swatches in the pill (2–3 dots, the current one first). A tap
highlights in that colour. One undo, as now.

**R7-5 P2 · The lasso's first-use tip covers the selection for 10 s.** The
tip stays for `visibleFor` (`features/editor/chrome/editor_tips.dart:45,
119`) even after the user has done what it says. In every
`e_convert_*`, `e_image_selected_*` and `e_shape_selected_*` render it sits
under the selection menu, above the bottom bar. *Fix:* dismiss
`EditorTip.lasso` when the first selection is made (listen to the
selection in `TipsController.followTools`) or the tool changes.
*Done (`fix/r7-pen`):* it goes with the first selection (ink, elements or
PDF text) or another tool, and isn't offered while something is selected.

### Organising and finding

**R7-6 P1 · No recent notebooks.** The library shows the current folder
only (`features/library/library_controller.dart:206-219`,
`folderOf(n) == _folderId`). A student with a folder per course opens the
drawer or folder, then the notebook, several times a day. On phones that
is 2–4 taps from launch. Sorting by "Last edited" helps only inside one
folder. *Fix:* at the Library root (not in folders, not while searching),
add a "Recent" strip above the folders: the last 6 notebooks opened or
edited across all folders, as covers in one sideways-scrolling row (the
`FolderRow.strip` pattern), hidden while fewer than 2 notebooks live in
folders. No setting, no new section in the sidebar.

**R7-7 P1 · Nothing reopens where you were writing.** `OpenNotebooks`
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

**R7-8 P1 · Export / share only exists inside the editor.** The notebook
menu offers Open, Rename, Favourite, Duplicate, Move, Cover, Select, Trash
(`features/library/library_menus.dart:12-23`). The editor's top bar has no
export either; it is in ⋯ (`chrome/editor_more_menu.dart:92`). "Send
yesterday's notes to a classmate" means opening the notebook, ⋯, Export.
*Fix:* add "Export…" to the notebook menu and the selection bar, running
`exportFlow` with all pages (the same sheet; several notebooks give one
PDF each through the share path).

**R7-9 P1 · Pages can't be moved or copied to another notebook.** The
overview's selection bar has Bookmark, Duplicate, Template, Export, Delete
(`features/documents/overview/page_commands.dart:8-33`). Nothing moves
pages between notebooks; lasso copy carries ink and elements but not the
page, its template or its PDF background. Splitting a term's notebook or
filing a page into the right course is impossible. *Fix:* "Move to…" and
"Copy to…" in the overview selection bar and the page menu, with the
notebook picker the link pickers already have (`editor/links/link_pickers.dart`)
plus "New notebook". Pages are appended; their backgrounds keep their blob
references. Moves are one Undo ("Moved 3 pages to “Physics” · Undo").

### Studying and PDFs

**R7-10 P2 · Lecture recordings are invisible outside the notebook.** Cards
and list rows show no sign of recordings (`features/library/notebook_card.dart`,
`notebook_list_tile.dart`). Recording titles aren't in the search index
(`data/search/*` indexes titles, folders, text boxes, PDF text,
handwriting). "Which lecture did I record?" means opening notebooks one by
one. *Fix:* a small mic glyph beside the page count on cards with
recordings ("12 pages · 2 recordings" in the list), and index recording
titles so a search for "Lecture 4" finds the notebook.

**R7-11 P2 · Export is two taps deep on every size.** Tablet and desktop
top bars have ← ⊞ title | tools | 🎤 ↶ ↷ ⋯ (`editor_tablet_light.png`;
nothing export-related in `chrome/editor_top_bar*.dart`). Sharing a page is
something students do daily. *Fix:* on wide bars (`ToolbarDock.inline`) add
a Share glyph (`Symbols.ios_share_sharp`) before ⋯ that opens the export
sheet. Phones keep it in ⋯.

### Delight and trust

**R7-12 P1 · Without sync, nothing says notes exist only on this device,
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

**R7-13 P1 · Android Auto Backup is on but unconfigured.**
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
not."

**R7-14 P2 · Phones show sync status only inside the drawer; the editor
never shows a failing sync.** `SyncStatusButton` is built only in the
sidebar (`features/library/library_sidebar.dart:145`). On phones the
sidebar is the drawer. `SyncAttention` speaks up only for a refused token
(`features/settings/sync_attention.dart:23-31`). A server that has been
unreachable for days goes unnoticed. *Fix:* on phones, show the cloud-alert
glyph in the library header while sync has failed for more than 15
minutes (tap: Settings → Sync). After 24 h of failures, show the
`SyncAttention` snack once ("Not synced since Monday · Settings").

**R7-15 P2 · ROADMAP still lists removed features.** "Customisable
toolbar … favourite pens … edit mode" and "synced favourite pens"
(`docs/ROADMAP.md:207-208,216`) were removed (SIMPLIFY #9, #10). *Done in
this branch:* the lines now describe the fixed toolbar.

### Missing features worth adding (value vs complexity; keep Len simple)

1. **Library backup and restore** (high value · M). Settings → Storage →
   "Back up…" writes one file (database + blobs, zipped) through the
   save / share path; "Restore from backup…" replaces the library after a
   confirmation, with a new device id. The same format exported per
   notebook ("Len notebook", from R7-8's Export) lets people hand editable
   notebooks to each other. Pairs with R7-13 for Android.
2. **Recent strip** (high · S): R7-6.
3. **Reopen where you left off** (high · S): R7-7.
4. **Move / copy pages to another notebook** (high · M): R7-9.
5. **Scribble to erase** (high · M; GoodNotes 6 has it). With the pen, a
   quick zigzag (≥ 3 sharp reversals within ~600 ms, small extent) over
   ink erases the strokes it crosses instead of drawing; one undo. It sits
   beside `HoldToStraighten` in `ink/input/`, with one switch in Pen →
   Feel next to hold to snap (R7-3). This is the biggest daily tap saving
   for writers without a side button (Windows pens, other styluses,
   fingers).
6. **Text-aware highlighter on PDFs** (high for students · M). A
   highlighter stroke whose length lies mostly over one or more lines of
   PDF text becomes the same snapped strokes `highlightSelection` makes
   (crisp, line-high, multi-line). With hold to snap off, nothing snaps.
   This removes R7-1's detour for the most common PDF action.
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
(R5-11, R5-16, R5-17, R5-20, R5-21, R5-22, R5-30) are not restated.
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

**R5-11 P2 · Zoom menu labels are 6 dp out of line.** `e_zoom_menu_*`: the
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

**R5-16 P2 · Search result rows are 36 dp tall on touch.** `_MatchTile`
(`features/search/editor/editor_search_bar.dart:259`): one line plus 8 dp
padding top and bottom. The "Page 3" label is `labelSmall` (bold overline)
pinned to the top, so it outweighs the snippet. *Fix:* rows at least
`Targets.menuRowHeight`; the location as `bodySmall`, aligned with the first
line's baseline. Add the search panel to `accessibility_test.dart`. *Files:*
`editor_search_bar.dart`.

**R5-17 P2 · Recording: paused looks like recording, and dark mode shouts.**
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

**R5-20 P2 · Text boxes have no inner padding.** `e_text_editing_*`,
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

**R5-22 P2 · The outline's header and list don't share an edge on tablets.**
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

**R5-25 P2 · The planner's "More options" is a Material `ExpansionTile`.**
`templates_*_planner`: its chevron, padding and type differ from Feel's
`OptionDisclosure` and the settings rows next to it. *Fix:* use
`OptionDisclosure` (moved to `ui/`) for both. *Files:*
`documents/templates/planner_options.dart:76`, `editor/pen/option_sections.dart`.

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

**R5-30 P2 · The accent marks plain states.** Accent is for primary buttons,
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

**R5-34 P2 · Dark mode: the HUD pill is light lavender.** `e_hud_phone_dark`,
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

Status: ⬜ open (all items).

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

🟡 **P2-15 Planner pages mix languages and fade their labels.** `paper_daily_tr*`,
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
