import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:pasteboard/pasteboard.dart';

import '../../../ink/selection/ink_clipboard.dart';

/// Asks what kinds of content the system clipboard holds, without reading
/// it; null when that can't be told.
typedef ClipboardPeek = Future<Set<PasteboardKind>?> Function();

/// How long the canvas menu waits for the system clipboard's answer before
/// it offers Paste here anyway (an X11 clipboard owner may hang).
const pastePeekTimeout = Duration(milliseconds: 300);

/// Whether the canvas menu's Paste here has something to paste: ink copied
/// in Len ([own]), or an image, text or files on the system clipboard as
/// [peek] tells without reading it (`Pasteboard.peek`: no "pasted" notice
/// on Android 12+). Where the clipboard can't be peeked at (or doesn't
/// answer in [pastePeekTimeout]) the row stays: the tap reads it.
Future<bool> mayPaste(InkClipboard own, {ClipboardPeek? peek}) async {
  if (!own.isEmpty) return true;
  final Set<PasteboardKind>? kinds;
  try {
    kinds = await (peek ?? Pasteboard.peek)().timeout(pastePeekTimeout, onTimeout: () => null);
  } on Object catch (e) {
    debugPrint('Peeking at the clipboard failed: $e');
    return true;
  }
  return kinds == null || kinds.isNotEmpty;
}
