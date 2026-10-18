import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../domain/text/user_font.dart';
import '../../ink/fonts/user_font_library.dart';
import '../../ui/app_dialogs.dart';
import '../../ui/error_details.dart';
import '../../ui/messages.dart';

/// Importing and removing the user's own fonts for text boxes (the font
/// picker's "Import font…", Settings → Text).
abstract final class FontImport {
  static const _types = [
    XTypeGroup(
      label: 'Fonts',
      extensions: ['ttf', 'otf'],
      // Android pickers filter by MIME type; fonts come under many names.
      mimeTypes: [
        'font/ttf',
        'font/otf',
        'font/sfnt',
        'application/x-font-ttf',
        'application/x-font-otf',
        'application/font-sfnt',
        'application/vnd.ms-opentype',
        'application/octet-stream',
      ],
      uniformTypeIdentifiers: ['public.truetype-ttf-font', 'public.opentype-font'],
    ),
  ];

  /// Picks a TTF or OTF file ([file] instead: tests) and adds it to the
  /// fonts; returns it (also one already here), or null if cancelled or
  /// refused (the user has been told why).
  static Future<UserFont?> pick(BuildContext context, {XFile? file}) async {
    file ??= await openFile(acceptedTypeGroups: _types);
    if (file == null || !context.mounted) return null;
    final fonts = AppScope.read(context).fonts;
    final known = {for (final f in fonts.fonts) f.id};
    try {
      final font = await fonts.import(await file.readAsBytes());
      if (context.mounted) {
        showMessage(
          context,
          known.contains(font.id)
              ? '“${font.name}” is already in your fonts'
              : 'Added “${font.name}”',
        );
      }
      return font;
    } on NotAFontException {
      if (context.mounted) showMessage(context, '“${file.name}” isn’t a TrueType or OpenType font');
      return null;
    } on Exception catch (e) {
      if (context.mounted) {
        showMessage(
          context,
          'Couldn’t import “${file.name}”',
          action: SnackBarAction(
            label: 'Details',
            onPressed: () => unawaited(
              showErrorDetails(
                context,
                title: 'Import failed',
                details: e is FormatException ? e.message : '$e',
              ),
            ),
          ),
        );
      }
      return null;
    }
  }

  /// Removes [font] after asking; text using it is then shown in the
  /// default font. The message offers Undo.
  static Future<void> remove(BuildContext context, UserFont font) async {
    final confirmed = await confirmAction(
      context,
      title: 'Remove “${font.name}”?',
      message: 'Text in this font is shown in Sans until you import it again',
      confirmLabel: 'Remove',
      destructive: true,
    );
    if (!confirmed || !context.mounted) return;
    final fonts = AppScope.read(context).fonts;
    await fonts.remove(font);
    if (!context.mounted) return;
    showMessage(
      context,
      'Removed “${font.name}”',
      action: SnackBarAction(label: 'Undo', onPressed: () => unawaited(fonts.restore(font))),
    );
  }
}
