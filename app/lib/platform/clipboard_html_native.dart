import 'package:flutter/foundation.dart';
import 'package:pasteboard/pasteboard.dart';

import 'rich_clip.dart';

/// The clipboard's formatted text: its HTML, or (only when it has none)
/// its RTF; empty where the platform cannot tell.
Future<RichClip> readClipboardRich() async {
  final html = await _read('HTML', () => Pasteboard.html);
  if (html != null) return (html: html, rtf: null);
  return (html: null, rtf: await _read('RTF', () => Pasteboard.rtf));
}

Future<String?> _read(String kind, Future<String?> Function() read) async {
  try {
    final text = await read();
    return text == null || text.isEmpty ? null : text;
  } catch (e) {
    debugPrint('Clipboard $kind unavailable: $e');
    return null;
  }
}

/// The formatted text of a browser paste that just inserted [plain] into a
/// text field: web only.
RichClip? richPastedAs(String plain) => null;

/// Starts watching browser paste events: web only.
void watchClipboardPastes() {}

/// Answers the browser's copy and cut events with [copy] while [owner]
/// holds them (web only; a text field whose text differs from what it
/// copies). [copy] returns null to leave an event to the browser.
void claimFieldCopies(Object owner, ({String plain, String html})? Function(bool cut) copy) {}

/// Stops [owner]'s [claimFieldCopies] (if it still holds them).
void releaseFieldCopies(Object owner) {}
