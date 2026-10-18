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
