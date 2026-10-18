import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../ink/fonts/user_font_library.dart';
import '../editor/tools/text/font_menus.dart';
import '../fonts/font_import.dart';
import 'settings_section.dart';

/// Fonts: the user's own fonts for text boxes (each named in itself, with
/// Remove) and "Import font…" (TTF or OTF; synced, in backups).
class FontSettings extends StatelessWidget {
  const FontSettings({super.key, required this.fonts});

  final UserFontLibrary fonts;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: fonts,
    builder: (context, _) => SettingsSection(
      title: 'Fonts',
      description: 'Fonts you import can be used in text boxes on all your devices',
      children: [
        for (final font in fonts.fonts)
          SettingsTile(
            icon: Symbols.text_fields_sharp,
            title: font.name,
            trailing: IconButton(
              tooltip: 'Remove “${font.name}”',
              icon: const Icon(Symbols.delete_sharp),
              onPressed: () => unawaited(FontImport.remove(context, font)),
            ),
            below: Text(
              'The quick brown fox jumps over the lazy dog',
              overflow: TextOverflow.ellipsis,
              style: fontSample(font.font),
            ),
          ),
        SettingsTile(
          icon: Symbols.upload_file_sharp,
          title: 'Import font…',
          subtitle: 'A TrueType or OpenType file (.ttf, .otf)',
          onTap: () => unawaited(FontImport.pick(context)),
        ),
      ],
    ),
  );
}
