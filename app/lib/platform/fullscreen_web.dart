import 'dart:js_interop';

import 'package:web/web.dart' as web;

/// Enters or leaves the browser's fullscreen mode. Returns whether the page
/// is full screen afterwards (browsers may refuse without a user gesture).
Future<bool> setFullscreen(bool on) async {
  final document = web.document;
  try {
    if (on && document.fullscreenElement == null) {
      await document.documentElement?.requestFullscreen().toDart;
    } else if (!on && document.fullscreenElement != null) {
      await document.exitFullscreen().toDart;
    }
  } catch (_) {
    return false;
  }
  return document.fullscreenElement != null;
}
