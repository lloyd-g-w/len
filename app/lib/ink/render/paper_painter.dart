import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../../domain/paper.dart';
import '../../domain/paper_pattern.dart';
import '../viewport.dart';

/// Colours around the paper. The paper itself and its pattern come from
/// [PaperColor]; paper keeps its colour in dark mode, like real paper.
class PaperColors {
  const PaperColors({
    this.margin = const Color(0x66E86A6A),
    this.desk = const Color(0xFFE9EAEE),
    this.shadow = const Color(0x33000000),
  });

  /// The red margin line of ruled paper.
  final Color margin;

  /// Background around pages.
  final Color desk;
  final Color shadow;
}

/// Draws paper sheets and their templates in world coordinates, for any
/// target: the editor, thumbnails and raster export.
abstract final class PaperRenderer {
  /// Below this on-screen pitch a pattern is hidden (it would be noise).
  static const double minScreenSpacing = 7;

  /// Whether [style]'s pattern is legible at [scale] device pixels per unit.
  static bool patternVisible(PaperStyle style, double scale) {
    // Staves are dense by design; dots are counted per area, not per line.
    final threshold = switch (style) {
      PaperStyle.music => minScreenSpacing / 2,
      PaperStyle.dotted => minScreenSpacing * 2,
      _ => minScreenSpacing,
    };
    return style.spacing * scale >= threshold;
  }

  /// Fills [page] with the paper colour, with a soft drop shadow.
  static void paintSheet(
    Canvas canvas,
    Rect page,
    PaperColor color, {
    required double scale,
    PaperColors colors = const PaperColors(),
    bool shadow = true,
  }) {
    if (shadow) {
      canvas.drawRect(
        page.shift(Offset(0, 2 / scale)),
        Paint()
          ..color = colors.shadow
          ..maskFilter = MaskFilter.blur(BlurStyle.normal, 6 / scale),
      );
    }
    canvas.drawRect(page, Paint()..color = color.paper);
  }

  /// Draws the template [style] within [area] (world units). The canvas
  /// must already map world units to device pixels at [scale]. Patterns too
  /// dense to read are skipped unless [always] (miniature previews).
  static void paintPattern(
    Canvas canvas,
    PaperStyle style,
    PaperColor color,
    Rect area, {
    Rect? page,
    required double scale,
    PaperColors colors = const PaperColors(),
    bool always = false,
  }) {
    if (style == PaperStyle.blank) return;
    if (!always && !patternVisible(style, scale)) return;
    final pattern = PaperPattern.of(style, area, page: page);
    if (pattern.isEmpty) return;
    // One device pixel in world units (thinner in miniatures).
    final px = (always ? math.min(1.0, 0.5 + scale) : 1) / scale;
    for (final weight in PatternWeight.values) {
      final points = <Offset>[
        for (final l in pattern.lines)
          if (l.weight == weight) ...[l.a, l.b],
      ];
      if (points.isEmpty) continue;
      final paint = Paint()
        ..color = switch (weight) {
          PatternWeight.margin => colors.margin,
          _ => color.pattern,
        }
        ..strokeWidth = switch (weight) {
          PatternWeight.normal => px,
          PatternWeight.heavy => 1.6 * px,
          PatternWeight.margin => 1.5 * px,
        };
      canvas.drawPoints(ui.PointMode.lines, points, paint);
    }
    if (pattern.dots.isNotEmpty) {
      final radius = math.max(1.0, 1.4 * math.min(1.0, scale)) * px;
      canvas.drawPoints(
        ui.PointMode.points,
        pattern.dots,
        Paint()
          ..color = color.pattern
          ..strokeWidth = radius * 2
          ..strokeCap = StrokeCap.round,
      );
    }
  }
}

/// Paints the paper background and its pattern for the visible area only,
/// so an infinite canvas costs the same as a single page.
class PaperPainter extends CustomPainter {
  PaperPainter({
    required this.viewport,
    required this.style,
    this.paperColor = PaperColor.white,
    this.page,
    this.colors = const PaperColors(),
  }) : super(repaint: viewport);

  final ViewportController viewport;
  final PaperStyle style;
  final PaperColor paperColor;

  /// Page rectangle in world units, or null for an infinite canvas.
  final Rect? page;
  final PaperColors colors;

  @override
  void paint(Canvas canvas, Size size) {
    final visible = viewport.visibleWorldFor(size);
    final scale = viewport.scale;
    if (page == null) canvas.drawRect(Offset.zero & size, Paint()..color = paperColor.paper);
    if (page != null) canvas.drawRect(Offset.zero & size, Paint()..color = colors.desk);
    canvas
      ..save()
      ..translate(viewport.offset.dx, viewport.offset.dy)
      ..scale(scale);
    final area = page == null ? visible : visible.intersect(page!);
    if (page != null) {
      PaperRenderer.paintSheet(canvas, page!, paperColor, scale: scale, colors: colors);
    }
    if (!area.isEmpty) {
      canvas.clipRect(area);
      PaperRenderer.paintPattern(
        canvas,
        style,
        paperColor,
        area,
        page: page,
        scale: scale,
        colors: colors,
      );
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(PaperPainter old) =>
      old.viewport != viewport ||
      old.style != style ||
      old.paperColor != paperColor ||
      old.page != page ||
      old.colors != colors;
}
