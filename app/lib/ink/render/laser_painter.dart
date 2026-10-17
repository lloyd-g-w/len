import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../tools/laser.dart';
import '../viewport.dart';
import 'catmull_rom.dart';
import 'laser_ribbon.dart';

/// Paints the laser pointer: a soft glow with a bright core, as a dot under
/// the pointer and (in trail mode) a smooth trail that thins and fades with
/// age.
///
/// Cheap per frame: the trail is two vertex meshes (glow and core) with
/// per-vertex colours — no blur filters, no layers — built in screen space
/// along a centripetal Catmull-Rom curve through the samples.
class LaserPainter extends CustomPainter {
  LaserPainter({required this.trail, required this.viewport})
    : super(repaint: Listenable.merge([trail, viewport]));

  final LaserTrail trail;
  final ViewportController viewport;

  /// Glow width relative to the core.
  static const double glowScale = 2.4;

  final LaserPaint _paint = LaserPaint();

  @override
  void paint(Canvas canvas, Size size) => _paint.paint(canvas, trail, viewport.toScreen);

  /// The core radius of [config]'s dot on screen.
  static double dotRadius(LaserConfig config) =>
      config.mode == LaserMode.dot ? config.size * 0.8 : config.size / 2;

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

/// Draws a laser: the meshes of its trail (kept between frames) and its
/// dot. Used by [LaserPainter] and for other devices' lasers.
class LaserPaint {
  final LaserRibbon _glow = LaserRibbon.glow();
  final LaserRibbon _core = LaserRibbon.core();

  /// Curve resolution (screen pixels between generated points).
  static const double _step = 4;

  /// Paints [trail] (this device's laser, or another's), its points put
  /// on the screen by [toScreen].
  void paint(Canvas canvas, LaserTrail trail, Offset Function(Offset world) toScreen) {
    final config = trail.config;
    final color = Color(config.color);
    if (config.mode == LaserMode.trail && trail.length > 1) {
      _glow.color = color;
      _core.color = color;
      _addTrail(trail, toScreen, config.size / 2);
      _glow.draw(canvas);
      _core.draw(canvas);
    }
    final head = trail.head;
    final alpha = trail.headAlpha;
    if (head == null || alpha <= 0) return;
    LaserPainter.paintDot(canvas, toScreen(head), LaserPainter.dotRadius(config), color, alpha);
  }

  /// Feeds every stroke of [trail] to the meshes.
  void _addTrail(LaserTrail trail, Offset Function(Offset) toScreen, double halfWidth) {
    final n = trail.length;
    var start = 0;
    for (var i = 1; i <= n; i++) {
      if (i < n && !trail.startsAt(i)) continue;
      _addStroke(trail, toScreen, start, i, halfWidth);
      start = i;
    }
  }

  void _addStroke(
    LaserTrail trail,
    Offset Function(Offset) toScreen,
    int from,
    int to,
    double halfWidth,
  ) {
    // Skip the expired head of the stroke (keep one point to fade from).
    while (from < to - 1 && trail.alphaAt(from + 1) <= 0) {
      from++;
    }
    if (to - from < 2) return;
    final xs = <double>[], ys = <double>[], alphas = <double>[];
    for (var i = from; i < to; i++) {
      final p = toScreen(trail.pointAt(i));
      xs.add(p.dx);
      ys.add(p.dy);
      alphas.add(trail.alphaAt(i));
    }
    final curve = CatmullRom.densify(xs, ys, alphas, _step);
    _glow.add(curve.x, curve.y, curve.r, halfWidth * LaserPainter.glowScale);
    _core.add(curve.x, curve.y, curve.r, halfWidth);
  }
}
