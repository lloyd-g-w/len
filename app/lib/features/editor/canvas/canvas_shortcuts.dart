import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../keyboard_navigation.dart';
import 'canvas_navigation.dart';

/// Shows or hides the canvas's minimap.
const SingleActivator minimapShortcut = SingleActivator(LogicalKeyboardKey.keyM, shift: true);

/// Keyboard navigation of a canvas: the arrows move around, `+` / `-` zoom
/// in steps (also with Ctrl/⌘), `0` is 100 %, Shift+1 fits the content,
/// Home goes back to the start, Shift+M shows or hides the minimap
/// ([toggleMinimap]). Single keys are wrapped in [unlessTyping].
Map<ShortcutActivator, VoidCallback> canvasShortcuts(
  CanvasNavigation nav,
  VoidCallback Function(VoidCallback action) unlessTyping, {
  VoidCallback? toggleMinimap,
}) {
  final zoomIn = unlessTyping(nav.zoomIn);
  final zoomOut = unlessTyping(nav.zoomOut);
  final actualSize = unlessTyping(() => nav.zoomTo(1));
  return {
    for (final key in [
      LogicalKeyboardKey.equal,
      LogicalKeyboardKey.add,
      LogicalKeyboardKey.numpadAdd,
    ]) ...{
      SingleActivator(key): zoomIn,
      SingleActivator(key, control: true): nav.zoomIn,
      SingleActivator(key, meta: true): nav.zoomIn,
      // `+` is Shift+= on many layouts.
      SingleActivator(key, shift: true): zoomIn,
    },
    for (final key in [LogicalKeyboardKey.minus, LogicalKeyboardKey.numpadSubtract]) ...{
      SingleActivator(key): zoomOut,
      SingleActivator(key, control: true): nav.zoomOut,
      SingleActivator(key, meta: true): nav.zoomOut,
    },
    const SingleActivator(LogicalKeyboardKey.digit0): actualSize,
    const SingleActivator(LogicalKeyboardKey.digit0, control: true): () => nav.zoomTo(1),
    const SingleActivator(LogicalKeyboardKey.digit0, meta: true): () => nav.zoomTo(1),
    const SingleActivator(LogicalKeyboardKey.digit1, shift: true): unlessTyping(nav.fitContent),
    const SingleActivator(LogicalKeyboardKey.home): unlessTyping(nav.goToOrigin),
    if (toggleMinimap != null) minimapShortcut: unlessTyping(toggleMinimap),
    for (final (key, direction) in KeyboardNavigation.arrows)
      SingleActivator(key): unlessTyping(() => KeyboardNavigation.scroll(nav.animator, direction)),
  };
}
