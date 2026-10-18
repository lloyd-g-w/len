import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../domain/text/user_font.dart';
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

  /// Picks a TTF or OTF file and adds it to the fonts; returns it, or null
  /// if cancelled or refused (the user has been told why).
  static Future<UserFont?> pick(BuildContext context) async {
    final file = await openFile(acceptedTypeGroups: _types);
    if (file == null || !context.mounted) return null;
    final services = AppScope.read(context);
    try {
      final font = await services.fonts.import(await file.readAsBytes());
      if (context.mounted) showMessage(context, 'Added “${font.name}”');
      return font;
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
