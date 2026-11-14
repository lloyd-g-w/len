import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/app_theme.dart';
import '../../../ui/floating_panel.dart';
import 'area_capture.dart';

/// What became of a captured area, and what else to do with it: "Copied"
/// (or "Copying…" while it renders, "Couldn’t copy" if the clipboard took
/// nothing), then Save as PNG (Share on Android), Insert as image and Done.
class CaptureResultBar extends StatelessWidget {
  const CaptureResultBar({
    super.key,
    required this.result,
    required this.onSave,
    required this.onInsert,
    required this.onDone,
  });

  /// The capture's outcome; null while it renders.
  final CaptureResult? result;
  final VoidCallback? onSave;
  final VoidCallback? onInsert;
  final VoidCallback onDone;

  static const String copied = 'Copied as image';
  static const String copying = 'Copying…';
  static const String notCopied = 'Couldn’t copy the image';
  static const String nothing = 'Nothing to capture there';

  static bool get _shares => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// The save command's name: Android hands files to the share sheet.
  static String get saveLabel => _shares ? 'Share…' : 'Save as PNG…';
  static const String insertLabel = 'Insert as image';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final result = this.result;
    final (IconData icon, String status) = switch (result) {
      null => (Symbols.content_copy_rounded, copying),
      (shot: null, copied: _) => (Symbols.error_rounded, nothing),
      (shot: _, copied: true) => (Symbols.check_rounded, copied),
      (shot: _, copied: false) => (Symbols.error_rounded, notCopied),
    };
    return FloatingPanel(
      key: const ValueKey('capture-result'),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(width: Gaps.sm),
          Icon(icon, size: Glyphs.menu, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(width: Gaps.sm),
          Semantics(liveRegion: true, child: Text(status, style: theme.textTheme.bodyMedium)),
          const SizedBox(width: Gaps.sm),
          IconButton(
            tooltip: saveLabel,
            onPressed: onSave,
            icon: Icon(_shares ? Symbols.share_rounded : Symbols.download_rounded, size: Glyphs.bar),
          ),
          IconButton(
            tooltip: insertLabel,
            onPressed: onInsert,
            icon: const Icon(Symbols.add_photo_alternate_rounded, size: Glyphs.bar),
          ),
          IconButton(
            tooltip: 'Done',
            onPressed: onDone,
            icon: const Icon(Symbols.close_rounded, size: Glyphs.bar),
          ),
        ],
      ),
    );
  }
}
