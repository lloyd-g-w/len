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

/// Answers the browser's copy and cut events with [copy] while [owner]
/// holds them (web only; a text field whose text differs from what it
/// copies). [copy] returns null to leave an event to the browser.
void claimFieldCopies(Object owner, ({String plain, String html})? Function(bool cut) copy) {}

/// Stops [owner]'s [claimFieldCopies] (if it still holds them).
void releaseFieldCopies(Object owner) {}
