### Imported fonts

*In progress.*

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

### RTF paste

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
