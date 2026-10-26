import 'dart:math' as math;
import 'dart:ui';

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

/// The minimap's blocks recorded once as a picture, in map pixels about the
/// world's origin, and replayed (translated) while the map stays at one
/// scale: a pan of the canvas or of the map redraws no block.
class MinimapBlocks {
  Picture? _picture;
  Object? _key;

  /// How many blocks the picture holds (for tests of the cost bound).
  int count = 0;

  /// The picture of [content]'s blocks at [scale] map pixels per world unit.
  Picture of(MinimapContent content, MinimapColors colors, double scale) {
    final key = (content, colors, scale);
    if (_picture case final picture? when _key == key) return picture;
    _picture?.dispose();
    _key = key;
    return _picture = _record(content, colors, scale);
  }

  Picture _record(MinimapContent content, MinimapColors colors, double scale) {
    final recorder = PictureRecorder();
    final canvas = Canvas(recorder);
    final side = content.cellSize * scale;
    // Blocks a few pixels wide read as soft tiles; tiny ones as dots.
    final inset = side > 6 ? side * 0.08 : 0.0;
    final radius = Radius.circular(math.min(side * 0.25, Radii.xs));
    final fill = Paint();
    for (final cell in content.cells) {
      final r = Rect.fromLTRB(
        cell.rect.left * scale,
        cell.rect.top * scale,
        cell.rect.right * scale,
        cell.rect.bottom * scale,
      ).deflate(inset);
      final shown = Rect.fromCenter(
        center: r.center,
        width: math.max(MinimapPainter.minBlock, r.width),
        height: math.max(MinimapPainter.minBlock, r.height),
      );
      final t = MinimapPainter.minAlpha + (1 - MinimapPainter.minAlpha) * cell.weight;
      fill.color = colors.ink.withValues(alpha: colors.ink.a * t);
      canvas.drawRRect(RRect.fromRectAndRadius(shown, radius), fill);
    }
    count = content.cells.length;
    return recorder.endRecording();
  }

  void dispose() {
    _picture?.dispose();
    _picture = null;
    _key = null;
  }
}

/// Draws a minimap: the content's blocks, the origin, and the visible area
/// as a frame (or, when it lies off the map, a mark on the edge toward it).
/// Its cost is bounded by the blocks ([MinimapContent] caps them), whatever
/// the canvas holds, and the blocks are replayed from [blocks] until the
/// map's scale changes.
class MinimapPainter extends CustomPainter {
  MinimapPainter({
    required this.content,
    required this.frame,
    required this.view,
    required this.colors,
    required super.repaint,
    MinimapBlocks? blocks,
  }) : blocks = blocks ?? MinimapBlocks();

  final MinimapContent content;

  /// The world area the map shows (read when painting: it animates).
  final Rect Function() frame;

  /// The visible world area (read when painting: it follows the view).
  final Rect Function() view;
  final MinimapColors colors;

  /// The cached blocks (owned by the map, which disposes them).
  final MinimapBlocks blocks;

  /// Smallest size a block or the view frame is drawn at, in map pixels,
  /// so a lone word on a vast canvas, or a close-up, still shows.
  static const double minBlock = 2;
  static const double minView = 6;

  /// Blocks this light at least, so faint content still reads.
  static const double minAlpha = 0.3;

  /// Size of the mark on the edge pointing at a view off the map.
  static const double edgeMark = 5;

  /// How many blocks the last paint drew (for tests of the cost bound).
  int get lastBlocks => blocks.count;

  @override
  void paint(Canvas canvas, Size size) {
    final map = MinimapProjection(frame(), size);
    canvas
      ..clipRect(Offset.zero & size)
      ..drawColor(colors.paper, BlendMode.src)
      ..save()
      ..translate(map.origin.dx, map.origin.dy)
      ..drawPicture(blocks.of(content, colors, map.scale))
      ..restore();
    _paintOrigin(canvas, map);
    _paintView(canvas, map, size);
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

  void _paintView(Canvas canvas, MinimapProjection map, Size size) {
    final r = map.rectToMap(view());
    final shown = Rect.fromCenter(
      center: r.center,
      width: math.max(minView, r.width),
      height: math.max(minView, r.height),
    );
    final bounds = Offset.zero & size;
    if (!shown.overlaps(bounds)) return _paintEdgeMark(canvas, bounds, shown.center);
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

  /// A small arrowhead on the map's edge, pointing at the view off it
  /// (at [target], map pixels).
  void _paintEdgeMark(Canvas canvas, Rect bounds, Offset target) {
    final inner = bounds.deflate(edgeMark + Gaps.xxs);
    final at = Offset(
      target.dx.clamp(inner.left, inner.right),
      target.dy.clamp(inner.top, inner.bottom),
    );
    final d = target - at;
    if (d.distance == 0) return;
    final ahead = d / d.distance * edgeMark;
    final side = Offset(-ahead.dy, ahead.dx) * 0.8;
    final tip = at + ahead;
    final back = at - ahead * 0.4;
    final path = Path()
      ..moveTo(tip.dx, tip.dy)
      ..lineTo(back.dx + side.dx, back.dy + side.dy)
      ..lineTo(back.dx - side.dx, back.dy - side.dy)
      ..close();
    canvas.drawPath(path, Paint()..color = colors.view);
  }

  @override
  bool shouldRepaint(MinimapPainter old) =>
      old.content != content || old.colors != colors || old.blocks != blocks;
}
