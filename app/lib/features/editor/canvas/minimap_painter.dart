import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../../../ui/app_theme.dart';
import 'minimap_geometry.dart';

/// Colours of the minimap: they sit on the canvas's paper.
@immutable
class MinimapColors {
  const MinimapColors({required this.paper, required this.ink, required this.view});

  final Color paper;

  /// Blocks of content (denser: stronger).
  final Color ink;

  /// The frame of the visible area.
  final Color view;

  @override
  bool operator ==(Object other) =>
      other is MinimapColors && other.paper == paper && other.ink == ink && other.view == view;

  @override
  int get hashCode => Object.hash(paper, ink, view);
}

/// Draws a minimap: the content's blocks, the origin, and the visible area
/// as a frame. Its cost is bounded by the blocks ([MinimapContent] caps
/// them), whatever the canvas holds.
class MinimapPainter extends CustomPainter {
  MinimapPainter({
    required this.content,
    required this.frame,
    required this.view,
    required this.colors,
    required super.repaint,
  });

  final MinimapContent content;

  /// The world area the map shows (read when painting: it animates).
  final Rect Function() frame;

  /// The visible world area (read when painting: it follows the view).
  final Rect Function() view;
  final MinimapColors colors;

  /// Smallest size a block or the view frame is drawn at, in map pixels,
  /// so a lone word on a vast canvas, or a close-up, still shows.
  static const double minBlock = 2;
  static const double minView = 6;

  /// Blocks this light at least, so faint content still reads.
  static const double minAlpha = 0.3;

  /// How many blocks the last paint drew (for tests of the cost bound).
  int lastBlocks = 0;

  @override
  void paint(Canvas canvas, Size size) {
    final map = MinimapProjection(frame(), size);
    canvas
      ..clipRect(Offset.zero & size)
      ..drawColor(colors.paper, BlendMode.src);
    _paintBlocks(canvas, map, size);
    _paintOrigin(canvas, map);
    _paintView(canvas, map);
  }

  void _paintBlocks(Canvas canvas, MinimapProjection map, Size size) {
    final side = content.cellSize * map.scale;
    // Blocks a few pixels wide read as soft tiles; tiny ones as dots.
    final inset = side > 6 ? side * 0.08 : 0.0;
    final radius = Radius.circular(math.min(side * 0.25, Radii.xs));
    final fill = Paint();
    final bounds = Offset.zero & size;
    var drawn = 0;
    for (final cell in content.cells) {
      final r = map.rectToMap(cell.rect).deflate(inset);
      final shown = Rect.fromCenter(
        center: r.center,
        width: math.max(minBlock, r.width),
        height: math.max(minBlock, r.height),
      );
      if (!shown.overlaps(bounds)) continue;
      final t = minAlpha + (1 - minAlpha) * cell.weight;
      fill.color = colors.ink.withValues(alpha: colors.ink.a * t);
      canvas.drawRRect(RRect.fromRectAndRadius(shown, radius), fill);
      drawn++;
    }
    lastBlocks = drawn;
  }

  /// A small cross where the canvas starts ("Back to start").
  void _paintOrigin(Canvas canvas, MinimapProjection map) {
    final o = map.toMap(Offset.zero);
    const arm = Gaps.xs;
    final cross = Paint()
      ..color = colors.ink.withValues(alpha: colors.ink.a * 0.5)
      ..strokeWidth = Hairline.width;
    canvas
      ..drawLine(o - const Offset(arm, 0), o + const Offset(arm, 0), cross)
      ..drawLine(o - const Offset(0, arm), o + const Offset(0, arm), cross);
  }

  void _paintView(Canvas canvas, MinimapProjection map) {
    final r = map.rectToMap(view());
    final shown = Rect.fromCenter(
      center: r.center,
      width: math.max(minView, r.width),
      height: math.max(minView, r.height),
    );
    final rrect = RRect.fromRectAndRadius(shown, const Radius.circular(Radii.xs));
    canvas
      ..drawRRect(rrect, Paint()..color = colors.view.withValues(alpha: 0.12))
      ..drawRRect(
        rrect.deflate(Hairline.width * 0.75),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = Hairline.width * 1.5
          ..color = colors.view,
      );
  }

  @override
  bool shouldRepaint(MinimapPainter old) => old.content != content || old.colors != colors;
}
