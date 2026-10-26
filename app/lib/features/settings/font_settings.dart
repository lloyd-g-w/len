import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../ink/fonts/text_fonts.dart';
import '../../ink/fonts/user_font_library.dart';
import '../editor/tools/text/font_menus.dart';
import '../fonts/font_import.dart';
import 'settings_section.dart';

/// Fonts: the user's own fonts for text boxes (each with a sample in
/// itself, or "Not on this device yet" while its file isn't here, and
/// Remove) and "Import font…" (TTF or OTF; synced, in backups).
class FontSettings extends StatelessWidget {
  const FontSettings({super.key, required this.fonts});

  final UserFontLibrary fonts;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    // (A font's file loads after the library lists it.)
    listenable: Listenable.merge([fonts, TextFonts.changes]),
    builder: (context, _) => SettingsSection(
      title: 'Fonts',
      description: 'Fonts you import can be used in text boxes on all your devices',
      children: [
        for (final font in fonts.fonts)
          SettingsTile(
            icon: Symbols.text_fields_rounded,
            title: font.name,
            subtitle: TextFonts.isShown(font.font) ? null : 'Not on this device yet',
            trailing: IconButton(
              tooltip: 'Remove “${font.name}”',
              icon: const Icon(Symbols.delete_rounded),
              onPressed: () => unawaited(FontImport.remove(context, font)),
            ),
            below: TextFonts.isShown(font.font)
                ? ExcludeSemantics(
                    child: Text(
                      'The quick brown fox jumps over the lazy dog',
                      overflow: TextOverflow.ellipsis,
                      style: fontSample(font.font),
                    ),
                  )
                : null,
          ),
        SettingsTile(
          icon: Symbols.upload_file_rounded,
          title: 'Import font…',
          subtitle: 'A .ttf or .otf font file',
          onTap: () => unawaited(FontImport.pick(context)),
        ),
      ],
    ),
  );
}
