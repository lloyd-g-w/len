# Len — UX/UI audit (library, settings, documents)

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

## P0 — broken or clearly unpolished

1. ⬜ **New-notebook sheet overflows on tablet/desktop.** At 1280×800 and
   1440×900 the sheet runs off the bottom (Import PDF cut off); the paper row
   scrolls sideways with no hint; there is no live preview of what will be
   created (cover is a 84 px sliver, paper is a separate row). → Rebuilt as a
   responsive "Create" sheet/dialog: big live preview (cover + first page
   side by side), title, kind, then Cover / Paper tabs with full galleries,
   size + orientation chips, paper colour; dialog on wide screens, full
   bottom sheet on phones, sticky actions.
2. ⬜ **Text scale 1.3× overflows** (folder tiles in the library at phone and
   tablet: fixed 64 px row extent). Settings "System" segment wraps mid-word.
   → Folder tiles size from the text scale; segmented labels never wrap.
3. ⬜ **PDF import / export progress is a bare spinner** with no stage, no
   page count, no percentage: a 300-page import or export looks hung. →
   `runWithProgress` gained determinate progress (stage + "Page 12 of 300" +
   bar); exporter reports per page; import reports reading / creating pages.
4. ⬜ **Page overview has no multi-select** (GoodNotes/Notewise both do): you
   can only act on one page at a time through a tiny "···" next to the
   number; the current page is only a 2 px border; no drag affordance; no
   "add page" tile; the bookmarks segmented control crowds the phone app bar.
   → Selection mode (tap to toggle, select all, bottom bar: bookmark,
   duplicate, delete), page-number chips, current-page badge, lift + drop
   indicator while reordering, "Add page" tile, compact filter chips.

## P1 — hierarchy, consistency, discoverability

5. ⬜ **Card metadata is thin**: "09:52" alone — no "Today", no page count,
   kind only for canvases. → "Today 09:52 · 12 pages", "Yesterday",
   "3 Oct"; canvases say "Canvas".
6. ⬜ **Dialogs are inconsistent**: rename is a bare 230 px field; folder
   dialog wraps 14 dots into a ragged second row; destructive confirmations
   have no icon; move dialog is a plain indented list with a disabled
   "Library" row and Cancel only. → Shared `AppDialog` (icon header, width,
   actions), folder dialog with live folder preview and an even swatch grid,
   destructive dialogs with an error-tinted icon, move dialog with folder
   rows that show their path depth with guides and a "Move here" button.
7. ⬜ **Template picker**: one flat wrap (labels small), size chips and
   orientation separate, no category grouping, no preview of the chosen
   page at its real shape. → Grouped sections (Basic, Ruled, Grid & dots,
   Special), larger tiles with a check badge, size + orientation in one row,
   sticky action bar.
8. ⬜ **Settings grouping**: Input mixes stylus and gestures; gesture rows
   have no description; dropdown for stylus button is small and
   mouse-oriented; no leading icons (GoodNotes/Android settings use them).
   → Sections "Appearance", "Stylus", "Gestures", "Sync", "About"; rows with
   leading icons and descriptions; segmented control for the side button.
9. ⬜ **Empty states**: search-empty art is a saturated blue disc that reads as
   a button; "No results" offers no way out. → Softer art, "Clear search"
   action; folder-empty offers "New notebook here".
10. ⬜ **Cover sheet** "Apply" floats alone at the bottom right; no Cancel; the
    preview doesn't show the title. → Uses the same cover gallery and preview
    as the create flow, with Cancel / Apply.

## P2 — refinement

11. ⬜ Trashed covers are 60 % opacity grey slabs: hard to recognise. → Keep
    the cover, desaturate it, show "Deleted 3 Oct".
12. ⬜ Library grid has no *Select* mode for bulk move/trash (GoodNotes
    "Select"). Needs controller support for multi-selection; planned next.
13. ⬜ No "New…" tile in the grid (GoodNotes). The FAB covers it; revisit
    after selection mode.
14. ⬜ Settings on wide screens could use a two-pane layout (category list +
    detail) like GoodNotes on iPad; the single 680 px column is fine for now.
15. ⬜ Motion: shared-element transition from cover to editor (GoodNotes
    "opens" the notebook). Needs the editor route (other agent).
16. ⬜ Folder colours only; GoodNotes allows folder icons/emoji.

## Accessibility notes

- Touch targets: card "More" buttons were 28 px → now 40 px hit area on
  touch platforms; page-overview "···" 32 px → whole tile is the target in
  selection mode, menu button 40 px.
- Semantics: covers announce title + kind + date; selection state is exposed
  (`selected`) on page tiles and swatches; progress dialog is a live region.
- Contrast: subtitle grey `#66666E` on `#F9F9F7` = 5.6:1 ✓; dark
  `#9F9FA9` on `#131316` = 7.4:1 ✓. Selected sidebar item in light uses
  `secondaryContainer` with dark text ✓.

## Routed to other areas ➡️

- **Editor chrome** (`features/editor/**`): the page overview is opened from
  the editor's "All pages" button; batch delete in the overview calls the
  single-page delete per page (each shows its own Undo snack bar, the last
  one wins). `DocumentCommands` should offer a `deleteMany` with one undo
  (the overview already accepts an optional `OverviewHandlers.deleteMany`).
- **Editor chrome**: opening a notebook should animate from its cover
  (Hero on `NotebookCover`, tag `cover-<id>`, already set in the library).
- **Editor chrome**: export entry points should show the new determinate
  progress (they do automatically through `exportFlow`).
- **Pen toolbar**: not audited here.
