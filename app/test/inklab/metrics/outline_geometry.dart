import 'dart:math' as math;
import 'dart:ui';

import 'package:len/domain/stroke.dart';
import 'package:len/ink/render/outline_sink.dart';
import 'package:len/ink/render/stroke_outline.dart';
import 'package:len/ink/render/stroke_renderer.dart';

/// A closed polygon (x0, y0, x1, y1, …).
typedef Contour = List<Offset>;

/// Records an outline as polygons, arcs and curves flattened finely
/// enough for [tolerance] (in the units after [map]).
class PolygonSink implements OutlineSink {
  PolygonSink({this.map = _identity, this.tolerance = 0.02});

  final Offset Function(Offset) map;
  final double tolerance;
  final List<Contour> contours = [];
  Contour? _current;
  Offset _at = Offset.zero;

  static Offset _identity(Offset o) => o;

  /// Number of `moveTo`s (sub-paths) — a proxy for path complexity.
  int moves = 0;

  /// Number of segments of every kind (path verbs).
  int verbs = 0;

  @override
  void moveTo(double x, double y) {
    moves++;
    verbs++;
    _at = Offset(x, y);
    _current = [map(_at)];
    contours.add(_current!);
  }

  @override
  void lineTo(double x, double y) {
    verbs++;
    _at = Offset(x, y);
    _current!.add(map(_at));
  }

  @override
  void cubicTo(double x1, double y1, double x2, double y2, double x3, double y3) {
    verbs++;
    final p0 = _at;
    for (var i = 1; i <= 16; i++) {
      final t = i / 16, u = 1 - t;
      final x = u * u * u * p0.dx + 3 * u * u * t * x1 + 3 * u * t * t * x2 + t * t * t * x3;
      final y = u * u * u * p0.dy + 3 * u * u * t * y1 + 3 * u * t * t * y2 + t * t * t * y3;
      _current!.add(map(Offset(x, y)));
    }
    _at = Offset(x3, y3);
  }

  @override
  void arc(double cx, double cy, double radius, double start, double sweep) {
    verbs++;
    final scaled = (map(Offset(radius, 0)) - map(Offset.zero)).distance;
    final step = scaled <= tolerance ? math.pi / 2 : 2 * math.acos(1 - tolerance / scaled);
    final n = math.max(1, (sweep.abs() / step).ceil());
    // An arc starts with a line from the current point to its start.
    for (var i = 0; i <= n; i++) {
      final a = start + sweep * i / n;
      _at = Offset(cx + radius * math.cos(a), cy + radius * math.sin(a));
      _current!.add(map(_at));
    }
  }

  @override
  void close() {}
}

/// The outline of [points] drawn with [tool], [width], [style], mapped by
/// [map] (e.g. world → physical px).
PolygonSink outlineOf(
  List<StrokePoint> points, {
  required InkTool tool,
  required double width,
  required StrokeStyle style,
  required bool complete,
  Offset Function(Offset)? map,
  double tolerance = 0.02,
}) {
  final sink = PolygonSink(map: map ?? PolygonSink._identity, tolerance: tolerance);
  StrokeRenderer.emitOutline(
    sink,
    points,
    tool: tool,
    width: width,
    style: style,
    complete: complete,
  );
  return sink;
}

/// A stroke's smoothed centre line in screen units: positions, radii and
/// the sample indices of detected corners.
class ScreenLine {
  ScreenLine(this.c, this.r, this.corners, this.step);
  final List<Offset> c;
  final List<double> r;
  final List<int> corners;

  /// Sample spacing (screen units).
  final double step;

  double get length => step * (c.length - 1);
}

/// The centre line the outline of [points] is built from, mapped to the
/// screen by [scale] and [offset] (null for no points).
ScreenLine? centerlineOf(
  List<StrokePoint> points, {
  required InkTool tool,
  required double width,
  required StrokeStyle style,
  required bool complete,
  double scale = 1,
  Offset offset = Offset.zero,
}) {
  final line = StrokeOutline.centerline(
    points,
    StrokeRenderer.specFor(tool, width, style),
    complete: complete,
  );
  if (line == null) return null;
  return ScreenLine(
    [for (var i = 0; i < line.length; i++) Offset(line.x[i], line.y[i]) * scale + offset],
    [for (var i = 0; i < line.length; i++) line.r[i] * scale],
    line.corners,
    line.step * scale,
  );
}
