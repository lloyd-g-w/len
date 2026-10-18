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
