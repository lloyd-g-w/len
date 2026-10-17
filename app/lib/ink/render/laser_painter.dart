import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../tools/laser.dart';
import '../viewport.dart';
import 'laser_ribbon.dart';
import 'laser_strokes.dart';

/// Paints the laser pointer: a soft glow with a bright core, as a dot under
/// the pointer and (in trail mode) a smooth trail that thins and fades with
/// age.
///
/// The trail's strokes are shaped by the pen's engine ([LaserStrokes]:
/// sampling, stabiliser, pressure, ends), incrementally. Cheap per frame:
/// the trail is two vertex meshes (glow and core) with per-vertex colours —
/// no blur filters, no layers — built in screen space along the strokes'
/// centre lines.
class LaserPainter extends CustomPainter {
  LaserPainter({required this.trail, required this.viewport})
    : super(repaint: Listenable.merge([trail, viewport]));

  final LaserTrail trail;
  final ViewportController viewport;

  /// Glow width relative to the core.
  static const double glowScale = 2.4;

  final LaserRibbon _glow = LaserRibbon.glow();
  final LaserRibbon _core = LaserRibbon.core();

  /// The trail's strokes, shaped by the pen's engine and kept between
  /// frames.
  final LaserStrokes _strokes = LaserStrokes();

  @override
  void paint(Canvas canvas, Size size) {
    final config = trail.config;
    final color = Color(config.color);
    if (config.mode == LaserMode.trail && trail.length > 1) {
      _glow.color = color;
      _core.color = color;
      final scale = viewport.scale, offset = viewport.toScreen(Offset.zero);
      _strokes
        ..sync(trail, scale)
        ..emit(
          _glow,
          _core,
          trail,
          glowScale: glowScale,
          scale: scale,
          ox: offset.dx,
          oy: offset.dy,
        );
      _glow.draw(canvas);
      _core.draw(canvas);
    }
    final head = trail.head;
    final alpha = trail.headAlpha;
    if (head == null || alpha <= 0) return;
    final radius = config.mode == LaserMode.dot ? config.size * 0.8 : config.size / 2;
    paintDot(canvas, viewport.toScreen(head), radius, color, alpha);
  }

  /// A glowing dot of core [radius] at [centre] with opacity [alpha].
  static void paintDot(Canvas canvas, Offset centre, double radius, Color color, double alpha) {
    final glowRadius = radius * glowScale * 1.25;
    canvas.drawCircle(
      centre,
      glowRadius,
      Paint()
        ..shader = ui.Gradient.radial(
          centre,
          glowRadius,
          [
            color.withValues(alpha: 0.55 * alpha),
            color.withValues(alpha: 0.18 * alpha),
            color.withValues(alpha: 0),
          ],
          const [0, 0.45, 1],
        ),
    );
    final hot = LaserRibbon.hotOf(color);
    final coreRadius = radius * 1.15;
    canvas.drawCircle(
      centre,
      coreRadius,
      Paint()
        ..shader = ui.Gradient.radial(
          centre,
          coreRadius,
          [
            hot.withValues(alpha: alpha),
            hot.withValues(alpha: alpha),
            color.withValues(alpha: alpha),
            color.withValues(alpha: 0),
          ],
          const [0, 0.2, 0.7, 1],
        ),
    );
  }

  @override
  bool shouldRepaint(LaserPainter old) => old.trail != trail || old.viewport != viewport;
}
