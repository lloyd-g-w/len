import 'package:flutter/foundation.dart';
import 'package:pasteboard/pasteboard.dart';

/// The clipboard's HTML, or null (none, or the platform cannot tell).
Future<String?> readClipboardHtml() async {
  try {
    final html = await Pasteboard.html;
    return html == null || html.isEmpty ? null : html;
  } catch (e) {
    debugPrint('Clipboard HTML unavailable: $e');
    return null;
  }
}

/// The HTML of a browser paste that just inserted [plain] into a text
/// field: web only.
String? htmlPastedAs(String plain) => null;

/// Starts watching browser paste events: web only.
void watchClipboardPastes() {}
