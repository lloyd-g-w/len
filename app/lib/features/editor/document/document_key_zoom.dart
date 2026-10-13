import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'document_controller.dart';
import 'page_fit.dart';

/// How much one zoom step by keyboard changes a paged notebook's zoom.
const double documentZoomStep = 1.25;

/// Keyboard zoom of a paged notebook, like a canvas's: `+` / `-` (also with
/// Ctrl/⌘) zoom about the middle of the view, Ctrl/⌘+0 goes back to the
/// automatic fit (plain `0` is bound with the other fits). Single keys are
/// wrapped in [unlessTyping].
Map<ShortcutActivator, VoidCallback> documentZoomShortcuts(
  DocumentController doc,
  VoidCallback Function(VoidCallback action) unlessTyping,
) {
  void zoom(double factor) {
    final view = doc.pageViewport;
    view.zoomAt(view.size.center(Offset.zero), factor);
  }

  void zoomIn() => zoom(documentZoomStep);
  void zoomOut() => zoom(1 / documentZoomStep);
  void fit() => doc.setFit(PageFit.auto);
  return {
    for (final key in [
      LogicalKeyboardKey.equal,
      LogicalKeyboardKey.add,
      LogicalKeyboardKey.numpadAdd,
    ]) ...{
      SingleActivator(key): unlessTyping(zoomIn),
      SingleActivator(key, control: true): zoomIn,
      SingleActivator(key, meta: true): zoomIn,
      // `+` is Shift+= on many layouts.
      SingleActivator(key, shift: true): unlessTyping(zoomIn),
    },
    for (final key in [LogicalKeyboardKey.minus, LogicalKeyboardKey.numpadSubtract]) ...{
      SingleActivator(key): unlessTyping(zoomOut),
      SingleActivator(key, control: true): zoomOut,
      SingleActivator(key, meta: true): zoomOut,
    },
    const SingleActivator(LogicalKeyboardKey.digit0, control: true): fit,
    const SingleActivator(LogicalKeyboardKey.digit0, meta: true): fit,
  };
}
