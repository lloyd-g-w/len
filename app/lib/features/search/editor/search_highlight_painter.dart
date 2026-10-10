import 'package:flutter/material.dart';

import 'editor_search_controller.dart';
import 'editor_search_host.dart';

/// Paints search matches over the editor's surface: every match on
/// screen in marker yellow, the current one in the accent colour with an
/// outline.
class SearchHighlightPainter extends CustomPainter {
  SearchHighlightPainter({
    required this.controller,
    required this.host,
    required this.matchColor,
    required this.currentColor,
  }) : super(repaint: Listenable.merge([controller, host.changes]));

  final EditorSearchController controller;
  final EditorSearchHost host;
  final Color matchColor;
  final Color currentColor;

  /// Most matches painted per frame (the rest are off screen in practice).
  static const int _maxPainted = 400;

  @override
  void paint(Canvas canvas, Size size) {
    if (!controller.isOpen) return;
    final screen = Offset.zero & size;
    final fill = Paint()..color = matchColor.withValues(alpha: 0.35);
    final currentFill = Paint()..color = currentColor.withValues(alpha: 0.22);
    final outline = Paint()
      ..color = currentColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final current = controller.currentMatch;
    var painted = 0;
    for (final match in controller.matches) {
      final transform = host.transformOf(match.surfaceId);
      if (transform == null) continue;
      final isCurrent = identical(match, current);
      for (final (:rect, :rotation) in controller.rectsOf(match)) {
        final onScreen = Rect.fromLTWH(
          rect.left * transform.scale + transform.offset.dx,
          rect.top * transform.scale + transform.offset.dy,
          rect.width * transform.scale,
          rect.height * transform.scale,
        );
        if (!onScreen.inflate(onScreen.longestSide).overlaps(screen)) continue;
        canvas.save();
        if (rotation != 0) {
          canvas
            ..translate(onScreen.center.dx, onScreen.center.dy)
            ..rotate(rotation)
            ..translate(-onScreen.center.dx, -onScreen.center.dy);
        }
        final shape = RRect.fromRectAndRadius(onScreen.inflate(2), const Radius.circular(3));
        canvas.drawRRect(shape, isCurrent ? currentFill : fill);
        if (isCurrent) canvas.drawRRect(shape.inflate(1), outline);
        canvas.restore();
        if (++painted > _maxPainted) return;
      }
    }
  }

  @override
  bool shouldRepaint(SearchHighlightPainter old) =>
      old.controller != controller ||
      old.host != host ||
      old.matchColor != matchColor ||
      old.currentColor != currentColor;
}
