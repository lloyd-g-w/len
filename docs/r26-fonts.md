### Imported fonts

Looked at: Settings → Fonts on phone and tablet, light and dark, 1× and 2× text, empty, with a
font not on this device and a 48-character name (rendered and looked at); Remove (confirm,
Undo, sync); the font picker with 40 imported fonts and long names (phone, tablet); missing
fonts on the canvas, in the picker and in PDF export (TrueType embedded as a subset, CFF and
missing files as an image of the box: `user_fonts_ui_test`). Settings wraps long names, reads
the name and not the pangram, and keeps its rows at 2×; the empty state is the import row.

**R26-F1 P2 · Fonts brought by a Len file, or not fetched at launch, stayed "Missing" until Len restarted.** ✅
- *What:* `UserFontLibrary` (`ink/fonts/user_font_library.dart`) re-read the library only at
  launch and when sync brought a font record. Importing a notebook or backup that carries a font
  wrote it to the database but not to the in-memory library: its text showed in Sans, the picker
  said "Missing font", until a restart. A font whose file could not be fetched at launch
  (offline, say) stayed "Not on this device yet" for the session.
- *Fix:* the library refreshes when a Len file is imported (`LenArchives` notifies) and tries
  the fonts not loaded yet again after each sync that worked and each change sync brings
  (`user_fonts_test`: the Len files case now checks the library; "a font whose file couldn't be
  had is tried again after a sync that worked").

**R26-F2 P2 · Settings → Fonts showed a font that isn't on this device with a Sans sample, as if it were the font.** ✅
- *What:* `features/settings/font_settings.dart` drew each font's pangram through
  `fontSample`, which falls back to Inter while the file isn't here (not synced yet, offline):
  the row looked fine but showed the wrong typeface, without a word (the picker says "Not on
  this device yet"). It also listened only to the library, so a sample drawn before the file
  loaded stayed in Sans; and screen readers read the pangram after every font's name.
- *Fix:* such a row says "Not on this device yet" and has no sample; the section rebuilds on
  `TextFonts.changes`; the sample is left out of semantics (`font_settings_test`).

**R26-F8 P3 · With many fonts the picker opened at Sans, the current font out of sight.** ✅
The font menu (`features/editor/tools/text/font_menus.dart`, through `showMenuBelow`) is a
plain popup menu: with 40 fonts it fills a phone's height and opens at its top, so the checked
font — the last one, say — was 2 100 dp down, and nothing showed which was current. `MenuRow`
(`ui/menus.dart`) now scrolls a checked row into view when its menu opens (any long menu with a
check benefits; short ones don't move) (`user_fonts_ui_test`: "with many fonts the picker
opens scrolled to the current one").

**R26-F9 P3 · Remove didn't say the font goes from every device.** ✅
`FontImport.remove` asked "Text in this font is shown in Sans until you import it again"; the
removal syncs, so other devices lose it too. Now "… shown in Sans on all your devices until you
import it again"; Remove → confirm → Undo had no test and now has one (`font_settings_test`).
(Also on this branch: "TrueType" and "OpenType" added to `copy_rules_test`'s names, which
R26-F4's message tripped.)

**R26-F10 P3 · Fonts are listed by plain text order: "Font 10" before "Font 2".** ⬜
`FontRepository.list` sorts `ORDER BY name COLLATE NOCASE` (Settings and the picker). Families
with numbers ("Source Serif 4", "Font 2 / 10") sort oddly. *Proposal:* a natural order (digit
runs compared as numbers) in Dart after the query.

**R26-F11 P3 · Text in a missing font keeps its box's frame from the real font.** ⬜
A box's rect was measured in its font on the device that wrote it; where the font is missing
the text is laid out in Sans in that width (`ElementRenderer._drawText`, not clipped), wraps
differently (Sans is wider than a hand font such as Caveat) and may run past the frame's bottom and
its selection outline. It is right again once the file
arrives; editing it there saves the Sans height. *Proposal:* accept (the fallback is said in
the picker), or re-measure missing-font boxes for display only. Owner's call.

### RTF paste

Looked at besides F3 and F6 (probes, `textFromRtf`): unbalanced braces, extra closing braces,
100 000 nested groups, truncated and bad `\'hh`, out-of-range and lone-surrogate `\u`, `\uc`
past the text, `\bin` with a huge count, huge, zero and negative `\fs` (sizes clamp), undefined
`\f` / `\cf`, fields (the result is kept, the instruction dropped), objects and shapes (their
results only), NULs, unclosed tables and 200 000 table rows (1.2 s in a debug test). None
throws or pastes junk; a number of more than ten digits leaves the rest as text, harmless.

**R26-F3 P2 · RTF in Greek, Turkish, Hebrew, Arabic, Baltic, Vietnamese, Thai or East Asian code pages pasted as gibberish.** ✅
- *What:* `domain/text/rtf_code_pages.dart` decoded `\'hh` bytes only for code pages 1250, 1251
  and 1252 and read every other as Latin-1. WordPad writes text its font's charset covers as
  bytes of that charset (`\fcharset161` Greek: `\'e1\'e2\'e3`), so a Greek line pasted as
  "áâã", Hebrew or Arabic as accented Latin, and Japanese / Chinese / Korean (double-byte, also
  unmapped charsets 128 / 129 / 134 / 136) as control characters — worse than the plain text
  the clipboard also holds.
- *Fix:* tables for 874, 1253–1258, Mac Roman, 437 and 850 (`rtf_code_page_tables.dart`,
  generated from Python's codecs); text in a double-byte code page makes `textFromRtf` give up,
  so the plain text pastes instead (Word's `\u` with double-byte fallbacks still reads)
  (`rtf_text_test`: "\'hh in Greek, Turkish, …", "East Asian double-byte text is not read").

**R26-F4 P3 · Importing a font already there said "Added"; a refused file's reason hid behind Details.** ✅
`features/fonts/font_import.dart`: the same file again said "Added “Caveat”" (nothing was
added), and a file that is no font said "Couldn’t import “x.otf”" with the reason only under
Details. Now "“Caveat” is already in your fonts" and "“notes.otf” isn’t a TrueType or OpenType
font" (`NotAFontException`); Details stays for files the engine refuses (`font_import_test`).

### Paragraph spacing

Looked at: the format bar and its menu (phone at 2×, tablet at 1× and 2×), the Text options at
2× (rendered); undo, flow across pages, PDF, HTML copy and right-to-left text are covered by
`paragraph_spacing_test`, `paragraph_spacing_ui_test`, `pdf_text_export_test` and
`rtl_text_golden_test`, read and run; no new findings there.

**R26-F12 P3 · On phones at 2× text the ⋯'s spacing rows are cut: "No paragraph s…", "Small paragrap…".** ⬜
`TextFormatBar`'s docked ⋯ lists the four spacings as "No paragraph spacing", "Small paragraph
spacing", … (beside Insert table… and Delete text box); at 2× text they truncate to the
first word. *Proposal:* with R26-T17's "Table…", one row "Paragraph spacing" with the current
one as its caption, opening the four-choice menu the tablet's button shows.

**R26-F5 P3 · At large text the Text options cut "Paragraph spacing" to "Paragraph".** ✅
`ParagraphSpacingRow` and `FontMenuRow` (`features/editor/tools/text/`) were fixed at a menu
row's height, so a label that wraps at 2× lost its second line. They are now at least that high.
The format bar's size number (the other auditor's "24" wrapping, phones and tablets alike at 2×)
no longer wraps either: at least 28 wide, one line, tabular figures (`text_controls_large_text_test`;
six text goldens moved by the figures).

**R26-F6 P3 · Pasting RTF with a large picture froze Len for about a second.** ✅
`textFromRtf` trimmed trailing NULs with `RegExp(r'\x00+$')`, which tries every position of
the string: with WordPad's hex for a 10 MB picture (20 MB of text) that took 0.7 s on the UI
thread, and the tokenizer copied text a character at a time. A loop trims the NULs and text runs
are copied whole: 0.07 s (`rtf_text_test`: "a large picture is skipped about as fast as its text
is read", relative to reading the text once).

**R26-F7 P3 · The lasso's style panel set text boxes' font and size but not their paragraph spacing.** ✅
`features/editor/tools/selection_style_panel.dart` had Font and Size for selected text boxes;
spacing could only be set one box at a time while editing. It now has the Text options' row
("Mixed" when the boxes differ), one undo step, boxes resized
(`paragraph_spacing_ui_test`: "the lasso's style panel spaces the selected boxes…";
`text_lasso_style.png` updated).

Counts: 12 findings (0 P1, 3 P2, 9 P3); fixed: 9 (F1–F3 P2; F4–F9 P3); open: 3 (F10–F12 P3).

Owner decisions for TODO Next:
- R26-F11: text in a missing font — accept that it may overflow its frame until the file
  arrives, or lay such boxes out again for display.
- R26-F12 (with R26-T17): the phone ⋯ of a text box — one "Paragraph spacing" row opening its
  menu, as "Table…" would.
