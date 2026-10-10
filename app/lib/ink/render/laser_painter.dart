import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../tools/laser.dart';
import '../viewport.dart';

/// Paints the laser pointer's trail: a glowing red line whose older parts
/// fade out.
class LaserPainter extends CustomPainter {
  LaserPainter({required this.trail, required this.viewport})
    : super(repaint: Listenable.merge([trail, viewport]));

  final LaserTrail trail;
  final ViewportController viewport;

  static const Color red = Color(0xFFFF2D2D);

  @override
  void paint(Canvas canvas, Size size) {
    final points = trail.points;
    if (points.isEmpty) return;
    final now = trail.now;
    final glow = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 12
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6);
    final core = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4;
    for (var i = 0; i < points.length; i++) {
      final p = points[i];
      final alpha = LaserTrail.fade(p.time, now);
      if (alpha <= 0) continue;
      final b = viewport.toScreen(p.world);
      final a = p.startsSegment ? b : viewport.toScreen(points[i - 1].world);
      glow.color = red.withValues(alpha: 0.55 * alpha);
      core.color = Color.lerp(red, const Color(0xFFFFFFFF), 0.35)!.withValues(alpha: alpha);
      canvas
        ..drawLine(a, b, glow)
        ..drawLine(a, b, core);
    }
  }

  @override
  bool shouldRepaint(LaserPainter old) => old.trail != trail || old.viewport != viewport;
}
