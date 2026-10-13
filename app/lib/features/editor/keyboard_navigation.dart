import 'package:flutter/services.dart';

import '../../ink/navigation/viewport_animator.dart';

/// Arrow-key scrolling and stepped zoom, shared by canvases and paged
/// notebooks. Each press glides; a held key's repeats chain into one
/// smooth scroll.
abstract final class KeyboardNavigation {
  /// An arrow press moves the view by this fraction of the screen.
  static const double arrowStep = 0.15;

  /// One `+` / `-` zoom step in paged notebooks (canvases step through
  /// round zoom levels).
  static const double zoomStep = 1.25;

  /// The arrow keys and where each moves the view (← shows what is to the
  /// left).
  static final List<(LogicalKeyboardKey, Offset)> arrows = [
    (LogicalKeyboardKey.arrowLeft, const Offset(-1, 0)),
    (LogicalKeyboardKey.arrowRight, const Offset(1, 0)),
    (LogicalKeyboardKey.arrowUp, const Offset(0, -1)),
    (LogicalKeyboardKey.arrowDown, const Offset(0, 1)),
  ];

  /// Scrolls one arrow step towards [direction] (unit axes).
  static void scroll(ViewportAnimator animator, Offset direction) {
    final v = animator.viewport;
    final step = Offset(direction.dx * v.size.width, direction.dy * v.size.height) * arrowStep;
    animator.animateTo(scale: v.scale, offset: v.offset - step);
  }
}
