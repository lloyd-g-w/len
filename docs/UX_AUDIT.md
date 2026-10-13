# Len — UX/UI audit

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
(`ToolbarSlot.joined`). Still open: snapping the puck clear of ink on release.

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
Screenshot suites run as Android, so desktop renders still show touch copy.

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
→ ✅ Templates, moves, bookmarks (many as one step), added, duplicated and deleted pages are steps of the notebook-wide undo history (`PageEdits` → `PageModels.record`), so Ctrl+Z and ↶ take them back in order with ink. "Template changed on N pages · Undo"; snack-bar Undo goes through the same history (`PageModels.undoEdit`). Pages inserted from a PDF are one step too, and so is duplicating several pages in the overview.

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
→ ✅ Denial says "Allow microphone access for Len in system settings" (browser: site settings); a Settings button would need `permission_handler` (not added). Pause/resume wait for the recorder, ignore double taps, keep the real state and show a message on failure. No raw exceptions in copy (logged).

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
→ ✅ Solid seek track with a round thumb; Recordings uses an outline glyph; subtitle "4 recordings · 1 h 17 min", sizes moved into a row's menu; "…It downloads when you're online". Not done: lifting the recorder pill above Add page, trim into the overflow.

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

**P1-13 The floating selection bar covers cards.** `select_tablet*` (over card
titles), `select_phone*` (over the bottom row): the grid has no bottom padding
for it. *Fix:* pad the grid by the bar's height while selecting (as results
are padded for the FAB). *Files:* `features/library/selection/*`,
`library_content.dart`.

**P1-14 Phone FAB covers the last card's ⋯.** `library_phone_*`: the + sits on
the last card's caption and menu button. *Fix:* bottom padding = FAB + 16 dp in
grid and list (search already does). *Files:* `library_content.dart`.

**P1-15 Trash never empties itself, and restore loses the folder.**
`library_empty_state.dart:60` "stay here until you delete them forever"; no
purge anywhere. Restoring a notebook whose folder was deleted puts it at the
root (`data/notebook_repository.dart:141-147`) silently; Restore and Move show
no message (`library_actions.dart:182`, `selection/selection_actions.dart:41`).
*Fix:* purge after 30 days ("Deleted 3 Oct · 27 days left"); "Restored to
School" / "Moved 3 notebooks to Work · Undo". *Files:*
`features/library/library_actions.dart`, `library_controller.dart`,
`data/notebook_repository.dart`.

**P1-16 Deleting a folder doesn't say how much goes, and can't be undone.**
`library_actions.dart:225-231`: "Its subfolders are deleted too; notebooks
inside move to the trash." No counts and no Undo; restored notebooks lose
their folders. *Fix:* "Delete “School”? 2 subfolders and 14 notebooks go to
the trash." plus an Undo snack (folders are soft-deleted already). *Files:*
`features/library/library_actions.dart`, `library_controller.dart`.

**P2-16 Empty states disagree.** `empty_phone_light`, `empty_folder_phone`,
`empty_search_phone`, `s_library_favourites_empty*`, `s_library_trash_empty*`:
illustration vs grey disc; "New notebook" vs "New notebook here" (filled) vs
"Clear search" (outlined); the header caption says "Empty" above "This folder
is empty"; empty Favourites and Trash keep search and ⇅ active; the folder's
copy "drag notebooks onto this folder" can't be done on a phone. *Fix:* one
`EmptyState` (icon in a disc, title, one line, one filled action); no caption
and no search/⇅ while empty; touch copy "Move notebooks here from their ⋯
menu". *Files:* `features/library/library_empty_state.dart`,
`library_header.dart`.

**P2-17 First launch offers only "New notebook".** `library_empty_state.dart:92-97`:
no Import PDF, no hint that sync exists (a user with a server sees an empty
library). *Fix:* secondary actions "Import PDF…" and "Set up sync…" under the
primary. *Files:* `features/library/library_empty_state.dart`.

**P2-18 The phone folder header stacks breadcrumbs over ☰.** `empty_folder_phone.png`:
"Library ›" above "☰ Sketches"; ☰ inside a folder reads as "you're at the top".
*Fix:* in folders on phones, ← (up one level) replaces ☰; no breadcrumb row.
*Files:* `features/library/library_header.dart`.

**P2-19 Three ways to start a notebook on wide screens.** `desktop_folder`,
`large_library_tablet`: the "New…" tile, ⊕▾ and, in the sheet, "Import PDF…".
The tile's label "New…" is vague and low-contrast in dark. *Fix:* label the
tile "New notebook"; keep ⊕▾ for the other kinds. *Files:*
`features/library/new_notebook_tile.dart`.
*Done (fix/a11y-tools):* contrast: in dark mode the tile has the firmer
`outline` edge (its face is close to the background).

**P2-20 The ⇅ View menu has no group labels.** `s_library_view_menu*`: sort,
layout and Select… run together with a ragged icon column; the current sort
isn't shown in the header. *Fix:* "Sort by" / "Show as" `SectionLabel`s, the
leading slot always reserved; caption "7 notebooks · by name" when not the
default. *Files:* `features/library/library_header.dart`, `library_menus.dart`.

**P2-21 List view.** `desktop_list.png`, `s_library_list*`: an outline star on
every row (the grid only marks favourites) and the star and ⋯ sit 1300 px from
the title on desktop. *Fix:* stars only on favourites (hover shows the toggle);
cap the list at 960 dp or add a "Edited" column. *Files:*
`features/library/notebook_list_tile.dart`.

**P2-22 Search results mix two layouts.** `s_library_search*`, `desktop_search.png`:
title matches are big grid cards, content matches list rows, and every row
says "1 match". *Fix:* sections "Notebooks" and "Pages" as rows; omit "1
match". *Files:* `features/search/library_search_results.dart`.

**P2-23 Small touch targets on cards and folders.** `notebook_card.dart:199`
(`height: Targets.touchFirst ? 36 : 28`) and the folder ⋯
(`folder_tile.dart:133`, about 32 dp wide). *Fix:* 48-dp hit area with the same
visual; tooltip "More" on both (not "Folder options"). *Files:*
`features/library/notebook_card.dart`, `folder_tile.dart`.

**P2-24 Covers flash flat colours, then thumbnails.** On loading, notebooks
show their cover colour before their thumbnail. *Fix:* neutral placeholder and
a `Motion.fast` cross-fade. *Files:* `features/library/thumbnails/*`.

### Dialogs, sheets and settings

**P1-17 Sheets and dialogs still disagree on their footer and close controls.**
`folder_dialog_phone` (full-width Save, no Cancel) vs `s_dialog_cover*` (✕ +
Cancel + Apply) vs `export_phone_*` (Cancel + Export) vs rename (no ✕) vs move
(✕, no footer) vs the new-notebook sheet (no drag handle, unlike the others).
REDESIGN §5 says: task sheets have ✕ and a footer of Cancel + one filled
primary; Confirms have no ✕. *Fix:* apply that in `SheetActions` /
`SheetHeader` everywhere; pickers that commit on tap (move) keep only ✕.
*Files:* `ui/sheet_parts.dart`, `ui/dialog_or_sheet.dart`,
`features/library/dialogs/*`, `features/library/new_notebook_sheet.dart`.

**P1-18 Ten cover colours wrap 9 + 1.** `desktop_cover_sheet.png`,
`dialog_cover_light/dark.png`: Sand alone on a second row with empty space
below, while the new-notebook form fits all ten in one row. *Fix:* the same
`EvenGrid` row as the new-notebook form (10 × 1 wide, 5 × 2 on phones).
*Files:* `features/library/dialogs/cover_sheet.dart`, `cover_picker.dart`.

**P1-19 The wide new-notebook dialog clips Portrait / Landscape.**
`desktop_new_sheet.png`, `new_desktop_*`, `large_new_tablet*`: the form scrolls
inside a short dialog and the orientation control is cut in half above the
footer, with no fade; at 1.3× "All templates…" breaks mid-word ("All tem /
plates…"). *Fix:* let the dialog grow to the window (max 720 dp tall) and add
`ScrollFade` above the footer; never break the tile label mid-word (wrap on
spaces, or "More…"). *Files:* `features/library/new_notebook_sheet.dart`,
`features/library/new_notebook/*`.

**P1-20 Template side panels clip and wrap.** `e_dialog_add_page_template_desktop_*`,
`e_dialog_canvas_background_desktop_dark`, `templates_*`: chips half cut at
the panel bottom with no scroll cue; the custom-colour button wraps alone
(6 + 1); two previews; spacing presets repeat the ruled templates. Searching
"grid" leaves the "Planners" chip selected; selected chips are barely visible
in dark. *Fix:* `ScrollFade` on the panel; Custom inline in the swatch row; one
preview; drop the presets (the slider plus the templates cover them); clear
the category on search; selected chips use `Surfaces.pressed` + a check.
*Files:* `features/documents/templates/paper_options.dart`,
`paper_option_rows.dart`, `template_chooser.dart`, `template_gallery.dart`.

**P1-21 Change template on phones: three stacked buttons eat a third of the sheet.**
`e_dialog_change_template_phone_*`: Apply to this page, Apply to all pages and
Cancel (plus ✕) leave 1.5 rows of templates. *Fix:* a "This page · All pages"
segmented control and one Apply; ✕ is Cancel. *Files:*
`features/documents/template_picker.dart`.

**P2-25 Settings copy and controls.** `settings_*`, `s_settings_*`:
- "Draw with" segments are shrunk to a smaller size than the others (`ShrinkToFit`).
- "Side button: While you hold the S Pen (or stylus) button" shows on desktops and the web.
- "Toolbar: Along the top; at the bottom on phones" describes Docked even when Floating is chosen.
- Handwriting "Not available here" is followed by a paragraph on how to use it.
- "Sync is off" is a grey pill that looks like a disabled field.
- On wide screens the "Settings" title scrolls away under an empty app bar.

*Fix:* two-row segments rather than shrunk text; the side-button row only
where a stylus can be (Android, or once seen); the toolbar subtitle follows the
choice; hide the how-to where recognition is unavailable; status as a plain row
with an icon; the title in the app bar on wide screens. *Files:*
`features/settings/*`.

**P2-26 Snack bars still collide.** `e_snack_saved_template_phone_*` (two lines
grow down over the bottom toolbar), `e_snack_stylus_detected_phone_*` (snack
and the side-button tip at once), `e_missing_planner_page_phone` (PDF notice
and snack at once). *Fix:* `MessageInsets` anchors the snack's bottom edge,
so it grows upward; queue tips behind snacks; shorten "Saved “Physics —
Mechanics, page 1” to My templates" → "Page saved as a template". *Files:*
`ui/messages.dart`, `chrome/editor_tips.dart`, `document/document_commands.dart`.

**P2-27 Export sheet polish.** `export_*_range`, `export_narrow_large_text_scrolled`,
`export_tablet_portrait_*`: the range error shows in the field and again in
the footer ("Check the page range", wraps on phones); disabled Export is grey
on grey in dark; content scrolls under the header with no divider; 800-dp
tablets get a bottom sheet while 1280 gets a dialog. *Fix:* error in the field
only, helper "e.g. 1–3, 5"; theme disabled colours; header divider when
scrolled; `showDialogOrSheet` threshold at 600 dp. *Files:*
`features/documents/export/export_sheet*.dart`, `ui/dialog_or_sheet.dart`.
*Done (fix/a11y-tools):* disabled filled buttons keep a readable label
(`onSurfaceVariant` on a 12 % plate, theme-wide) instead of 38 % grey.

**P2-28 Missing-PDF notice copy.** `e_missing_pdf_background_*`: "A PDF these
pages are drawn on isn't on this device" / "Relink…" is awkward and repeats
the hatched placeholder. *Fix:* "The PDF for these pages isn't on this
device." with "Locate file…" and "Try again". *Files:*
`chrome/missing_pdf_notice.dart`.

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
it releases the lock (ARCHITECTURE *Platforms*, *Tab handover*).

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

◐ **P1-25 A parked pane and the second pane's header are unclear.** `split_parked_portrait_*`:
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
- **A11Y-1 Small targets in the tablet library sidebar.** Sidebar rows are
  40 dp (42 with spacing), New folder 40, the footer's Settings and Sync
  40, the search field 40: under 44 on touch tablets. At 2× text the footer
  squeezes the Settings label away. *Fix:* rows and footer buttons
  `Targets.of(context, 40)` on touch; the footer stacks at large text.
  *Files:* `ui/sidebar_item.dart`, `features/library/library_sidebar.dart`,
  `library_header.dart`. (Allowed in `accessibility_test.dart` until fixed.)
- **A11Y-2 Settings segmented buttons shrink on phones.** `ShrinkToFit`
  scales "Draw with" and "Side button" down to fit 390 dp (to about 38 dp
  high, smaller text), more at large text. *Fix:* below a width, a menu or
  radio rows instead of a segmented button. *Files:* `ui/segment_label.dart`,
  `features/settings/writing_settings.dart`.
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
  at the end, so the footer moves clear (`fix/editor-chrome-r4`). A short
  document that can't scroll far enough still tucks it under a tall player.
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
