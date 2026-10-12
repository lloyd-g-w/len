# Len — UX/UI audit

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
- ⬜ A parked pane gives no hint in portrait (e.g. its recording runs unseen; the first
  pane only learns of it when it tries to record).
- ⬜ A selection or a text box being edited in one pane hides those items in the other
  view of the same notebook until it ends.

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
12. 🟡 **Dialog headers differ.** Some have a tinted icon and a centred
    title, others are left-aligned, and the progress dialog has a bare
    hourglass. Template sheets disagree on footers: "Change template" has
    no Cancel, and the primary labels and icons vary. → Tinted
    `DialogIcon` for confirmations and progress; every sheet has Cancel
    plus one filled primary.
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
20. 🟡 Menus sit flush against the screen edge (no 8 dp margin). → Popup
    menus keep 8 dp; tall chrome menus now clear the system bars by 8 dp
    (`menuReservedPadding`). Open: Flutter's `MenuAnchor` still places a menu
    that meets the left or right edge flush against it (the phone "⋯" menu).
21. ✅ Colour dots (40 dp) and selection
    checkboxes (28 dp) are under 48 dp on phones. → `EvenGrid(touchTargets:)`
    gives swatch cells 48 dp on phones (visuals unchanged, the whole
    cell takes taps); the checkmark never was a target (the whole cover is).
22. 🟡 The playback bar truncates the title (title and time share one row);
    ✅ the paused recorder shows "Paused" in place of the level meter and
    Resume is a play icon.
23. ✅ List view shows the favourite star twice (cover badge plus column).
24. ⬜ A missing PDF background renders as a silently blank page (should be
    a placeholder with a "Relink…" action).
25. ⬜ Canvases can't be exported (no entry point).
26. ⬜ Desktop: folder cards and the notebook grid end at different right
    edges, and titles are limited to one line.
27. ⬜ Bookmark colour differs between the editor (orange), the overview
    (brown or peach) and the app bar (primary).

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
- Progress dialogs have no Cancel (also item 17 of round 2).
  Convert-to-text errors only offer Close, with no Try again (it would
  need to re-run recognition).
- Stacked dialog actions are end-aligned at their own widths, so they
  look ragged (Change template on phones). Full-width stacked buttons
  would need a custom actions layout. (✅ for the template picker: full-width
  buttons on phones, primary on top; other dialogs still open.)
- New-notebook sheet on phones at 1.3×: the preview takes most of the
  screen, leaving about one row of templates. On phones the preview
  should collapse.
- The phone library shows both the "New…" tile and the "New" FAB.
- The FAB still shows over the empty Favourites and empty search states,
  which offer no create action of their own.
- ✅ Selection checkmarks on covers: unselected rings are low-contrast on
  light covers, the style differs between light and dark, and targets
  are 28 dp. → A dark ring on white in both themes; the whole cover is the
  target.
- Editor search on phones: stepping to a match pans the page sideways.
- Lasso selection handles in dark mode are dark and filled on light
  paper. They should follow the paper, as the canvas hint now
  does.
- The image crop bar overlaps the fit button on phones.
- The page submenu opens over its parent on phones (a drill-in or a sheet
  would suit phones better).
- The handwriting language picker is a `SimpleDialog`: no Cancel, and no
  hint that it scrolls.
- ✅ The paused recorder shows no "Paused" label, and Resume is a mic icon.
  → "Paused" replaces the level meter; Resume is a play icon.
- ✅ Template grid on phones: 3 fixed columns leave a gutter on the right.
  Paper-colour chips wrap 3 + 1 (also item 19 of round 2). → The gallery
  picks the column count whose tiles come closest to the preferred size and
  stretches them to fill the width; paper colours and page formats are
  `EvenChoices` (one even row, or two even rows when they don't fit).

### Accessibility (round 3)

- Targets: compact menus are 44 dp high (fine for pointer, tight for
  touch). Icon buttons are 48 dp. Swatch and selection controls are listed
  in 21.
- Contrast: see 11. Body subtitles (`onSurfaceVariant`) are 5.6:1 in
  light and 7.4:1 in dark. The page pill's "1 / 1" in light is borderline.
- Semantics: icon-only buttons have tooltips, which double as labels. The
  selection bar on phones is icon-only.

### Routed ➡️

- feat/text: the text format bar overflows on phones (Delete and Done are
  clipped); text touches the box border; colour swatches are 22 dp.
- feat/pen3: dark ink swatches and colour underlines vanish on the dark
  toolbar (needs the `ColorDot` ring or the same rule); the phone tool
  switcher has uneven margins; the narrow bottom toolbar is clipped at the
  right edge.

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
   previews; segmented control for the side button.
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
    detail) like GoodNotes on iPad. → From 1040 px: section list with icons
    on the left, the selected section on the right; one column below.
    ✅ The detail pane no longer repeats the section's title and icon (the
    selected entry names it; `SettingsSection.untitled`).
15. ✅ Motion: shared-element transition from cover to editor (GoodNotes
    "opens" the notebook). → `NotebookOpenRoute`: the tapped cover grows
    into the screen, fades into the paper and the editor fades in; back
    shrinks it into the cover (wherever it is now), else fades.
16. ✅ Folder colours only; GoodNotes allows folder icons/emoji. → Won't do:
    folders keep colour only (icons were added, then removed in SIMPLIFY #43).
17. ⬜ Long PDF imports/exports can't be cancelled (the progress dialog has
    no Cancel; needs cancellation in `PdfImporter` / `NotebookExporter`).
18. ✅ No export options sheet (page range, PNG resolution, flatten
    template) like GoodNotes' export dialog. → `ExportSheet` (dialog / bottom
    sheet): format, pages or range, templates & PDF backgrounds, PNG resolution.
19. ✅ Paper-colour chips wrap to two rows on phones in the template picker.
    → Even rows (`EvenChoices`): four in a row when they fit, else 2 × 2.
20. ⬜ Typing a search ends selection mode (selection is scoped to the
    place, search included); keep it if the selected notebooks match.
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
- ⬜ Keyboard: chrome buttons are reachable with Tab but there is no
  "skip to canvas" or toolbar arrow-key navigation yet.
- ✅ **Motion**: opening a notebook animates from its cover (container
  transform in `NotebookOpenRoute`, see 15); reduced motion → plain fade.
- ➡️ **Export**: entry points should offer options (see 18); progress is
  already shown through `exportFlow`.
