import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../ink/navigation/viewport_animator.dart';
import '../keyboard_navigation.dart';
import 'document_controller.dart';
import 'document_layout.dart';
import 'page_fit.dart';

/// Keyboard navigation of a paged notebook: ← / → and Page Up / Down turn
/// pages, ↑ / ↓ scroll (turn pages in single-page flow), Home / End go to
/// the first / last page, `+` / `-` zoom (also with Ctrl/⌘), `0` (also
/// with Ctrl/⌘) is the automatic page zoom, Shift+1 the whole page, Shift+2 the page width.
/// Single keys are wrapped in [unlessTyping].
Map<ShortcutActivator, VoidCallback> documentShortcuts(
  DocumentController doc,
  ViewportAnimator animator,
  VoidCallback Function(VoidCallback action) unlessTyping,
) {
  void turn(int by) => doc.scrollToPage(doc.currentPage + by);
  void scroll(int by) => doc.flow == PageFlow.single
      ? turn(by)
      : KeyboardNavigation.scroll(animator, Offset(0, by.toDouble()));
  void zoom(double factor) => animator.zoomTo(doc.viewport.scale * factor);
  return {
    for (final key in [LogicalKeyboardKey.pageDown, LogicalKeyboardKey.arrowRight])
      SingleActivator(key): unlessTyping(() => turn(1)),
    for (final key in [LogicalKeyboardKey.pageUp, LogicalKeyboardKey.arrowLeft])
      SingleActivator(key): unlessTyping(() => turn(-1)),
    const SingleActivator(LogicalKeyboardKey.arrowDown): unlessTyping(() => scroll(1)),
    const SingleActivator(LogicalKeyboardKey.arrowUp): unlessTyping(() => scroll(-1)),
    const SingleActivator(LogicalKeyboardKey.home): unlessTyping(() => doc.scrollToPage(0)),
    const SingleActivator(LogicalKeyboardKey.end): unlessTyping(
      () => doc.scrollToPage(doc.pages.length - 1),
    ),
    for (final (keys, factor) in [
      (_zoomInKeys, KeyboardNavigation.zoomStep),
      (_zoomOutKeys, 1 / KeyboardNavigation.zoomStep),
    ])
      for (final key in keys) ...{
        SingleActivator(key): unlessTyping(() => zoom(factor)),
        // `+` is Shift+= on many layouts.
        SingleActivator(key, shift: true): unlessTyping(() => zoom(factor)),
        SingleActivator(key, control: true): () => zoom(factor),
        SingleActivator(key, meta: true): () => zoom(factor),
      },
    const SingleActivator(LogicalKeyboardKey.digit0): unlessTyping(() => doc.setFit(PageFit.auto)),
    const SingleActivator(LogicalKeyboardKey.digit0, control: true): () => doc.setFit(PageFit.auto),
    const SingleActivator(LogicalKeyboardKey.digit0, meta: true): () => doc.setFit(PageFit.auto),
    const SingleActivator(LogicalKeyboardKey.digit1, shift: true): unlessTyping(
      () => doc.setFit(PageFit.page),
    ),
    const SingleActivator(LogicalKeyboardKey.digit2, shift: true): unlessTyping(
      () => doc.setFit(PageFit.width),
    ),
  };
}

final _zoomInKeys = [
  LogicalKeyboardKey.equal,
  LogicalKeyboardKey.add,
  LogicalKeyboardKey.numpadAdd,
];
final _zoomOutKeys = [LogicalKeyboardKey.minus, LogicalKeyboardKey.numpadSubtract];
