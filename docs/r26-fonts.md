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
