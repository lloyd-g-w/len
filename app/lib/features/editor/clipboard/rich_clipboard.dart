import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:pasteboard/pasteboard.dart';

/// Puts [text] and its formatted version [html] (`htmlFromTexts`) on the
/// system clipboard as one entry, so other apps keep the formatting
/// (through the vendored `pasteboard`'s `write`); where that fails (macOS,
/// iOS, an old browser) the plain text alone, the usual way. Whether the
/// clipboard holds it; never an error.
Future<bool> writeRichClipboard(String text, String html) async {
  try {
    if (await Pasteboard.write(text: text, html: html)) return true;
  } on Object catch (e) {
    debugPrint('Copying formatted text to the system clipboard failed: $e');
  }
  try {
    await Clipboard.setData(ClipboardData(text: text));
    return true;
  } on Object catch (e) {
    debugPrint('Copying text to the system clipboard failed: $e');
    return false;
  }
}
