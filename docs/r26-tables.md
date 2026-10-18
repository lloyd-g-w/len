## Round 26 — part T: tables in text boxes

Read the table code (model, edits, controller, keys, editor layer, menus, flow, PDF,
HTML / RTF, semantics) and probed each suspicion with widget and unit tests (throwaway
probes; the fixes' tests kept): every table command undone and redone, blocks of cells,
pastes, column drags, Backspace / Delete around a table, a heading or list item before
it, right-to-left boxes with Hebrew, Latin and number cells, a table over two pages in
continuous and one-page-at-a-time layouts, a 6 000-unit cell, 5 / 50 / 100 × 10 tables,
screen-reader traversal. Rendered the picker and the table menu (phone ⋯ and sheet,
tablet popover; light, dark, 2× text; keyboard focus) and the cell being edited, and
looked at them. Verdict: the model and the editing engine are sound (every command one
undo step, tables repaired after any edit, PDF and HTML faithful); the edges were not:
the picker lost its last column on touch screens, taps into a table over pages missed
their cell, pastes lost columns or did nothing, arrows in right-to-left tables went the
wrong way from numbers, and screen readers heard the text after a table first.

### Inserting a table

**R26-T4 P2 · On touch screens the size picker's last column was cut off and could not be picked.** ✅
- *What:* the picker padded itself (`Gaps.md`) inside the popover's own padding, leaving
  224 dp for a grid of 8 × 30 dp touch cells: the eighth column was painted past the
  grid's box, half of it, and taps there missed it (an Android tablet could pick at most
  7 columns from the grid). The phone sheet had the same doubled margin.
- *Fix:* the picker no longer pads itself (as the other popovers' contents); the grid is
  whole (`table_editor_test`: the size picker shows its whole grid).

**R26-T5 P3 · The size picker's grid could not be used from the keyboard or a screen reader.** ✅
Only three preset buttons (2 × 2, 3 × 3, 4 × 3) were reachable; the grid was a bare
`GestureDetector` with no semantics. The grid now takes the focus when the picker opens
(a focus ring in the accent when the keyboard is used), arrows size the table, Enter
inserts it; screen readers read it as "Table size", its value "2 × 3", a tap inserts it
(`table_editor_test`: the size picker takes the keyboard). The unused
`TableSpec.maxPickerRows` went.

**R26-T6 P3 · A table inserted at the end of a heading or list item was followed by an empty heading or bullet.** ✅
`insertTable` gave the line it adds after the table the style of the line the table went
into: after "Title" (a heading) the next thing typed was a heading, after a list item an
empty bullet showed. A line the table adds is now plain text; a heading or item split by
the table goes on below it (`text_table_test`: the line a table adds after it is plain
text).

### Cells and blocks of cells

**R26-T2 P2 · Ctrl+V with a block of cells selected did nothing.** ✅
- *What:* a block selected (Shift+arrows, a drag) took Ctrl+C, Ctrl+X, Delete, but its
  keys (`TableKeys.range`) ignored Ctrl+V: copying a block and pasting it over another, as
  in any spreadsheet or word processor, silently did nothing.
- *Fix:* Ctrl+V (Ctrl+Shift+V plain) edits the block's top left cell and pastes there
  (`pasteIntoCells`): a table or tab-separated rows fill the cells from it on, one value
  replaces that cell; one undo step (`table_editor_test`: Ctrl+V with a block of cells
  selected pastes from its top left cell on).

**R26-T3 P2 · Rows pasted into a cell lost the columns past the table's last.** ✅
- *What:* `pasteGrid` added rows for a taller paste but dropped every cell past the last
  column: three columns from a spreadsheet pasted into a new 2-column table lost the third,
  silently (only undo brought nothing back of it).
- *Fix:* it adds columns too, up to `TableSpec.maxColumns` (12; only cells past that are
  dropped, as a pasted HTML table's are) (`table_editor_test`: rows of tab-separated text
  pasted into a cell fill cells, adding rows and columns).

**R26-T8 P3 · With several rows selected the menu still said "Delete row".** ✅ A block of
cells deletes all its rows (or columns) as one step, but the rows read "Delete row" and
"Delete column". They now say "Delete rows" / "Delete columns" when the block spans
several (`table_editor_test`: with a block of rows selected the menu deletes rows).

**R26-T9 P3 · A column border dragged back where it was made an undo step that did nothing.** ✅
`commitWidths` ran at every drag's end; now only when the widths changed
(`table_editor_test`: dragging a column border resizes it, one undo step).

**R26-T12 P3 · Typing, Tab or Enter with a block of cells selected does nothing.** ⬜
`TableKeys.range` handles copy, cut, paste (R26-T2), Delete, arrows, Esc and formatting;
a typed letter is dropped, Tab moves the focus out of the box to the next control (the
format bar), Enter is ignored. *Proposal:* as spreadsheets do: a typed character replaces
the block's top left cell and edits it (its typing run starting there); Tab / Enter edit
the block's top left cell (Shift+Tab: its last cell).

### Right to left

**R26-T11 P2 · In a right-to-left table, ← and → went to the wrong cell from a number or Latin word.** ✅
- *What:* at a cell's edge an arrow went to the next or previous cell in reading order,
  chosen by the arrow's direction *in the cell's text*: in a Hebrew or Arabic table a cell
  holding "12" or "PDF" runs left to right, so → at its right end went to the next cell,
  which is on the left (← likewise to the right): the caret jumped against the arrow.
  Shift+arrows (by the table's direction) were right.
- *Fix:* the arrow picks the cell on its side of the table (`TableKeys._sideways`), the
  edge still by the cell's text (`table_editor_test`: in a right-to-left table arrows go
  to the cell on their side, numbers too).

**R26-T7 P3 · A right-to-left table copied to another app came out left to right.** ✅
In a Hebrew or Arabic box the first column is on the right (`TableLayout`, by the box's
direction), but the HTML copy (`htmlFromText`) wrote a plain `<table>`: Word or Docs put
the first column on the left, mirroring the table. A right-to-left box's table is now
written `<table dir="rtl">` (`table_clipboard_test`: a right-to-left box writes its table
right to left).

### Tables over pages

**R26-T1 P2 · A tap in a table cell of a box flowing over pages opened the chain at its end, not in that cell.** ✅
- *What:* a tap in a committed table edits the cell tapped (`TextHitTest.cellAt` →
  `TextEditSession.edit(caret:)`), but a box of a chain is opened as the whole chain
  (`_editChain`), which dropped the caret for the end of the tapped part: in a long table
  over two pages the caret went to the end of the text, not into the cell.
- *Fix:* `_editChain` maps the tapped offset into the whole text (`_startOf` the part plus
  the offset), on the first page and on the pages after
  (`text_flow_session_test`: a tap in a table cell of a chain edits that cell).

**R26-T13 P2 · In one-page-at-a-time layouts a column added to (or removed from) half of a split table splits it in two.** ⬜
- *What:* with pages shown one at a time a box of a chain is edited alone
  (`_Flow.alone`). Adding or deleting a column in the part of a table on one page changes
  only that part; `TextFlow.join` joins parts with as many columns only, so the stored
  text becomes two tables (page 1: 2 columns, page 2: 3; probe:
  `TextTable(…c: 2…), TextTable(…c: 3, k: true)`). Column widths dragged and the header
  row toggled on a continued part are silently reverted (`join` keeps the first part's
  spec). Continuous layouts edit the whole chain and are fine.
- *Proposal (owner decision):* either (a) edit a chain whose table crosses the page as
  a whole even when pages show one at a time (the head's page is activated, as the
  continuous layout does), or (b) carry the edited part's widths and header back to the
  table's other parts on commit (`_commitAlone`, like `_carryFirstLine`) and disable the
  column commands (insert / delete column) in a table that goes on over a page edited
  alone, with a hint ("Show pages together to change columns").

**R26-T14 P2 · A row taller than a page runs off the page.** ⬜ `TextFlowLayout.split`
cuts between lines, and a table row is one line: a cell holding a few thousand words
(probe: a 6 012-unit row, 700 units of room) makes a part as tall as the row, far past
the page's bottom margin and edge. Plain paragraphs split line by line. *Proposal:* split a row taller than the room between its cells' lines (each
cell cut at the same height, the row continued as a `continued` table with the rest of
each cell), or at least clip the part at the page's edge and say "This row is taller than
a page" when it is edited.

**R26-T15 P3 · A table's header row is not repeated on the pages it continues on.** ⬜
By design (`TableSpec.hasHeaderRow` is false for a continued part), unlike Word / Docs'
"repeat header row". *Owner decision:* repeat the header (bold, read-only copy drawn
above the continued rows, not in the text) or keep as is.

### Screen readers

**R26-T10 P2 · Screen readers read the text after a table before the table.** ✅
- *What:* a box with a table was one node labelled with all its text outside tables
  (`TextTableSemantics.textOutside`), the table's nodes after it: "Shopping. Total is
  fine." and only then the rows, though "Total is fine" stands below the table.
- *Fix:* the box's node reads the text before its first table; after each table a node
  (where that text is laid out) reads the text up to the next table
  (`table_semantics_test`: the text after the table is read after it).

**R26-T16 P3 · While a table is edited, screen readers get only the cell being edited.** ⬜
`TextBoxSemantics` leaves the edited box out; `TableEditorLayer` paints the other cells
(`_TablesPainter`) without nodes, and its field is named "Row r, column c" but not as a
header. A screen-reader user on a touch tablet cannot reach another cell except by
leaving the box. *Proposal:* the layer gives each painted cell a node (`SemanticsRole.cell`
/ `columnHeader`, its text) whose tap action enters it, as `TextTableSemantics` does for
committed boxes.

### Phone and touch

**R26-T17 P3 · On phones the text ⋯ in a table holds 13 rows.** ⬜ The docked bar has no
table button, so its ⋯ gains the 8 table commands, above the 4 paragraph spacings and
Delete text box (the whole 844-dp screen; at 2× text the rows truncate, "Insert column
l…", "Small paragrap…"). *Proposal:* one row "Table…" opening the table menu from ⋯ (as
Version history… holds its commands), keeping ⋯ at 6 rows.

**R26-T18 P3 · Column borders are 16 dp grips on touch screens too.** ⬜
`TableEditorLayer._grip` is 16 screen px for mouse, stylus and finger alike, invisible,
and there only while a cell is edited: with a finger they are hard to hit, and nothing
says they are there. *Proposal:* `Targets`-sized grips on touch (24 dp, still clear of
the cell text's padding), and a short accent tick on each border of the edited row as
the handle.

### Large tables

**R26-T19 P3 · Every keystroke in a cell lays out every cell of the box, twice or more.** ⬜
`setCell` → `_relayout` builds a new `TextPlan` (a `TableLayout` per table, a
`TextBoxLayout` per cell), the layer lays the box out again, and the session measures it
for the page. Debug-mode probe, 10 keystrokes: 5 × 10 cells 0.8 s, 50 × 10 1.9 s,
100 × 10 3.4 s (about 2.5 ms per extra row per keystroke, before release-mode speed-up).
Comfortable to 50 rows; a 200-row table will lag. *Proposal:* keep cell layouts across
plans keyed by the cell's data and width (only the edited cell changes per keystroke).

Counts: 19 findings (0 P1, 8 P2, 11 P3); fixed: 11 (T1–T11: 6 P2, 5 P3); open: 8
(T13, T14 P2; T12, T15–T19 P3).

Owner decisions for TODO Next:
- R26-T13: a split table in one-page-at-a-time layouts — edit the chain as a whole there
  too, or carry widths / header back and disable column commands on a split part.
- R26-T15: repeat a table's header row on the pages it continues on, or not.
