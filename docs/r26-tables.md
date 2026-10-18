## Round 26 — part T: tables in text boxes

*In progress.*

### Tables over pages

**R26-T1 P2 · A tap in a table cell of a box flowing over pages opened the chain at its end, not in that cell.** ✅
- *What:* a tap in a committed table edits the cell tapped (`TextHitTest.cellAt` →
  `TextEditSession.edit(caret:)`), but a box of a chain is opened as the whole chain
  (`_editChain`), which dropped the caret for the end of the tapped part: in a long table
  over two pages the caret went to the end of the text, not into the cell.
- *Fix:* `_editChain` maps the tapped offset into the whole text (`_startOf` the part plus
  the offset), on the first page and on the pages after
  (`text_flow_session_test`: a tap in a table cell of a chain edits that cell).

### Cells and blocks of cells

**R26-T2 P2 · Ctrl+V with a block of cells selected did nothing.** ✅
- *What:* a block selected (Shift+arrows, a drag) took Ctrl+C, Ctrl+X, Delete, but its
  keys (`TableKeys.range`) ignored Ctrl+V: copying a block and pasting it over another, as
  in any spreadsheet or word processor, silently did nothing.
- *Fix:* Ctrl+V (Ctrl+Shift+V plain) edits the block's top left cell and pastes there
  (`pasteIntoCells`): a table or tab-separated rows fill the cells from it on, one value
  replaces that cell; one undo step (`table_editor_test`: Ctrl+V with a block of cells
  selected pastes from its top left cell on).
