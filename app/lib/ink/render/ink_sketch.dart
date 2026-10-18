import 'dart:typed_data';
import 'dart:ui';

import '../../data/versions/work_slices.dart';
import '../../domain/stroke.dart';
import 'content_painter.dart';
import 'stroke_renderer.dart';

/// Records ink for a small picture (a version's thumbnail of a canvas of
/// tens of thousands of strokes) in slices of work: as
/// [ContentPainter.paint] with `sketchThin` draws it, but with each
/// stroke's points thinned to [tolerance] pixels and runs of opaque thin
/// strokes of one colour and width drawn in one call, as hairlines where
/// under a pixel wide. A canvas's thumbnail of 50,000 strokes records in
/// ~80 ms (sliced) and rasterises in ~6 ms, not ~60 ms as sketched paths.
abstract final class InkSketch {
  /// Points closer than this (pixels) to the last one kept are left out.
  static const double tolerance = 0.5;

  /// Strokes drawn between looks at the clock.
  static const _sliceCheck = 64;

  /// Draws [strokes] in their draw order ([Stroke.drawOrder]) onto
  /// [canvas] (world units, [pixelScale] pixels per unit), yielding
  /// through [slices]; only those meeting [within] if given (a zoomed-in
  /// part). Stops early, returning false, once [cancelled].
  static Future<bool> draw(
    Canvas canvas,
    List<Stroke> strokes, {
    required double pixelScale,
    required WorkSlices slices,
    Rect? within,
    bool Function()? cancelled,
  }) async {
    final ink = await _inDrawOrder(strokes, slices);
    final run = _Run(canvas, pixelScale);
    for (var i = 0; i < ink.length; i++) {
      if (i % _sliceCheck == 0) {
        await slices.yieldIfDue();
        if (cancelled?.call() ?? false) return false;
      }
      final s = ink[i];
      if (within != null && !s.bounds.overlaps(within)) continue;
      if (s.fill != null) {
        run.flush();
        StrokeRenderer.drawFill(canvas, s);
      }
      if (s.width * pixelScale >= ContentPainter.hairline || s.points.length < 2) {
        run.flush();
        StrokeRenderer.draw(canvas, s);
      } else {
        run.add(s);
      }
    }
    run.flush();
    return true;
  }

  /// [strokes] sorted by [Stroke.drawOrder]: as they are when already in
  /// order (a version's strokes usually are), checked in slices.
  static Future<List<Stroke>> _inDrawOrder(List<Stroke> strokes, WorkSlices slices) async {
    for (var i = 1; i < strokes.length; i++) {
      if (i % 4096 == 0) await slices.yieldIfDue();
      if (Stroke.drawOrder(strokes[i - 1], strokes[i]) > 0) {
        return strokes.toList()..sort(Stroke.drawOrder);
      }
    }
    return strokes;
  }
}

/// Consecutive thin strokes of one paint, as line segments for one
/// [Canvas.drawRawPoints]; translucent ones are drawn alone as a path (so
/// their overlaps show as they do drawn one by one).
class _Run {
  _Run(this.canvas, this.pixelScale)
    : _tol2 = (InkSketch.tolerance / pixelScale) * (InkSketch.tolerance / pixelScale);

  final Canvas canvas;
  final double pixelScale;

  /// The squared distance (world units) under which points are left out.
  final double _tol2;
  Float32List _xy = Float32List(4096);
  int _n = 0;
  int? _color;
  double _width = 0;

  void add(Stroke s) {
    if ((s.color >>> 24) != 0xFF || s.style.opacity < 1) {
      flush();
      canvas.drawPath(_path(s), _lines(StrokeRenderer.paintFor(s.color, s.style), s.width));
      return;
    }
    if (_color != s.color || _width != s.width) {
      flush();
      _color = s.color;
      _width = s.width;
    }
    final points = s.points;
    var px = points.first.x;
    var py = points.first.y;
    final last = points.length - 1;
    var segments = 0;
    for (var i = 1; i <= last; i++) {
      final p = points[i];
      final dx = p.x - px;
      final dy = p.y - py;
      // Close points are left out; the last only when it adds nothing.
      if (dx * dx + dy * dy < _tol2 && (i < last || segments > 0)) continue;
      _segment(px, py, p.x, p.y);
      segments++;
      px = p.x;
      py = p.y;
    }
  }

  void _segment(double x0, double y0, double x1, double y1) {
    if (_n + 4 > _xy.length) _xy = Float32List(_xy.length * 2)..setRange(0, _n, _xy);
    _xy
      ..[_n] = x0
      ..[_n + 1] = y0
      ..[_n + 2] = x1
      ..[_n + 3] = y1;
    _n += 4;
  }

  Path _path(Stroke s) {
    final points = s.points;
    final path = Path()..moveTo(points.first.x, points.first.y);
    var px = points.first.x;
    var py = points.first.y;
    for (var i = 1; i < points.length; i++) {
      final p = points[i];
      final dx = p.x - px;
      final dy = p.y - py;
      if (dx * dx + dy * dy < _tol2 && i < points.length - 1) continue;
      path.lineTo(p.x, p.y);
      px = p.x;
      py = p.y;
    }
    return path;
  }

  static Paint _lines(Paint paint, double width) => paint
    ..style = PaintingStyle.stroke
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  void flush() {
    final color = _color;
    if (_n == 0 || color == null) return;
    final pixels = _width * pixelScale;
    final paint = Paint()..isAntiAlias = true;
    if (pixels < 1) {
      // Under a pixel wide: a hairline as faint as the ink is thin, which
      // rasterises many times faster than lines of their own width and
      // darkens a pixel about as much as the ink covers of it.
      paint
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0
        ..color = Color(color).withValues(alpha: pixels);
    } else {
      _lines(paint..color = Color(color), _width);
    }
    canvas.drawRawPoints(PointMode.lines, Float32List.sublistView(_xy, 0, _n), paint);
    _n = 0;
  }
}
