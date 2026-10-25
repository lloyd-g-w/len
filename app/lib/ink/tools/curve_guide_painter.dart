import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../viewport.dart';
import 'curve_drawing.dart';

/// Paints [CurveDrawing.guide] over a curve being drawn, in the look of a
/// selected curve's handles (`SelectionPainter`): small knobs on the
/// points placed (square ones on corners), a larger ring on the first once
/// a tap there closes the curve, and tangents, if any, as arms ending in
/// solid dots.
class CurveGuidePainter extends CustomPainter {
  CurveGuidePainter({
    required this.guide,
    required this.viewport,
    required this.accent,
    required this.handleFill,
    this.handleScale = 1,
  }) : super(repaint: Listenable.merge([guide, viewport]));

  final ValueListenable<CurveGuide?> guide;
  final ViewportController viewport;
  final Color accent;
  final Color handleFill;

  /// How much larger than with a pointer the knobs are drawn (touch).
  final double handleScale;

  @override
  void paint(Canvas canvas, Size size) {
    final g = guide.value;
    if (g == null) return;
    final k = handleScale;
    final halo = Paint()
      ..color = handleFill
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;
    final ring = Paint()
      ..color = accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final arm = Paint()
      ..color = accent
      ..strokeWidth = 1;
    final fill = Paint()..color = handleFill;
    final solid = Paint()..color = accent;
    for (final paint in [halo, arm]) {
      for (final t in g.tangents) {
        canvas.drawLine(viewport.toScreen(t.anchor), viewport.toScreen(t.handle), paint);
      }
    }
    for (final (i, a) in g.anchors.indexed) {
      final at = viewport.toScreen(a);
      final r = (i == 0 && g.closes ? 6.5 : 4) * k;
      if (g.corners.contains(i)) {
        // A corner: a square knob.
        final square = Rect.fromCenter(center: at, width: 2 * r, height: 2 * r);
        canvas
          ..drawRect(square, fill)
          ..drawRect(square, ring);
        continue;
      }
      canvas
        ..drawCircle(at, r, fill)
        ..drawCircle(at, r, ring);
    }
    for (final t in g.tangents) {
      final at = viewport.toScreen(t.handle);
      canvas
        ..drawCircle(at, 5 * k, fill)
        ..drawCircle(at, 3.5 * k, solid);
    }
  }

  @override
  bool shouldRepaint(CurveGuidePainter old) =>
      old.guide != guide ||
      old.viewport != viewport ||
      old.accent != accent ||
      old.handleFill != handleFill ||
      old.handleScale != handleScale;
}
