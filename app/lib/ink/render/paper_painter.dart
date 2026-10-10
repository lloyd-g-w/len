import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../../domain/paper.dart';
import '../viewport.dart';

/// Colours used to draw paper. Paper stays light in dark mode, like real
/// paper, so ink colours look the same everywhere.
class PaperColors {
  const PaperColors({
    this.paper = const Color(0xFFFFFDF8),
    this.pattern = const Color(0xFFD9DEE7),
    this.margin = const Color(0x55E86A6A),
    this.desk = const Color(0xFFE9EAEE),
    this.shadow = const Color(0x33000000),
  });

  final Color paper;
  final Color pattern;
  final Color margin;

  /// Background around pages.
  final Color desk;
  final Color shadow;
}

/// Paints the paper background and its pattern for the visible area only,
/// so an infinite canvas costs the same as a single page.
class PaperPainter extends CustomPainter {
  PaperPainter({
    required this.viewport,
    required this.style,
    this.page,
    this.colors = const PaperColors(),
  }) : super(repaint: viewport);

  final ViewportController viewport;
  final PaperStyle style;

  /// Page rectangle in world units, or null for an infinite canvas.
  final Rect? page;
  final PaperColors colors;

  /// Pattern spacing in world units.
  static const double spacing = 32;

  /// Below this on-screen spacing the pattern is hidden (it would be noise).
  static const double _minScreenSpacing = 7;

  @override
  void paint(Canvas canvas, Size size) {
    final screen = Offset.zero & size;
    final page = this.page;
    Rect area; // Screen-space area covered by paper.
    if (page == null) {
      area = screen;
      canvas.drawRect(area, Paint()..color = colors.paper);
    } else {
      area = Rect.fromPoints(viewport.toScreen(page.topLeft), viewport.toScreen(page.bottomRight));
      canvas
        ..drawRect(screen, Paint()..color = colors.desk)
        ..drawRect(
          area.shift(const Offset(0, 2)),
          Paint()
            ..color = colors.shadow
            ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
        )
        ..drawRect(area, Paint()..color = colors.paper);
    }

    final visible = area.intersect(screen);
    if (visible.isEmpty || style == PaperStyle.blank) return;
    if (spacing * viewport.scale < _minScreenSpacing) return;

    canvas
      ..save()
      ..clipRect(visible);
    switch (style) {
      case PaperStyle.lined:
        _drawLines(canvas, visible, horizontal: true, vertical: false);
        if (page != null) _drawMargin(canvas, visible, page);
      case PaperStyle.grid:
        _drawLines(canvas, visible, horizontal: true, vertical: true);
      case PaperStyle.dotted:
        _drawDots(canvas, visible);
      case PaperStyle.blank:
        break;
    }
    canvas.restore();
  }

  /// World-aligned line positions within the screen interval [from, to]
  /// along one axis, as screen coordinates.
  Iterable<double> _ticks(double from, double to, double origin) sync* {
    final step = spacing * viewport.scale;
    final firstWorld = ((from - origin) / viewport.scale / spacing).ceil() * spacing;
    for (var s = firstWorld * viewport.scale + origin; s <= to; s += step) {
      yield s;
    }
  }

  void _drawLines(Canvas canvas, Rect area, {required bool horizontal, required bool vertical}) {
    final paint = Paint()
      ..color = colors.pattern
      ..strokeWidth = 1;
    if (horizontal) {
      for (final y in _ticks(area.top, area.bottom, viewport.offset.dy)) {
        canvas.drawLine(Offset(area.left, y), Offset(area.right, y), paint);
      }
    }
    if (vertical) {
      for (final x in _ticks(area.left, area.right, viewport.offset.dx)) {
        canvas.drawLine(Offset(x, area.top), Offset(x, area.bottom), paint);
      }
    }
  }

  void _drawMargin(Canvas canvas, Rect area, Rect page) {
    final x = viewport.toScreen(Offset(page.left + spacing * 2.5, 0)).dx;
    if (x < area.left || x > area.right) return;
    canvas.drawLine(
      Offset(x, area.top),
      Offset(x, area.bottom),
      Paint()
        ..color = colors.margin
        ..strokeWidth = 1.5,
    );
  }

  void _drawDots(Canvas canvas, Rect area) {
    // Dots are counted per area, not per line: require a sparser grid.
    if (spacing * viewport.scale < 2 * _minScreenSpacing) return;
    final radius = math.max(1.0, 1.4 * math.min(1.0, viewport.scale));
    final points = <Offset>[
      for (final y in _ticks(area.top, area.bottom, viewport.offset.dy))
        for (final x in _ticks(area.left, area.right, viewport.offset.dx)) Offset(x, y),
    ];
    canvas.drawPoints(
      ui.PointMode.points,
      points,
      Paint()
        ..color = colors.pattern.withValues(alpha: 1)
        ..strokeWidth = radius * 2
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(PaperPainter old) =>
      old.viewport != viewport || old.style != style || old.page != page || old.colors != colors;
}
