import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/render/outline_sink.dart';
import 'package:len/ink/render/stroke_outline.dart';

import 'support/handwriting.dart';

/// Records outline segments and measures how smoothly they join.
class RecordingSink implements OutlineSink {
  Offset _current = Offset.zero, _start = Offset.zero;
  Offset? _inTangent, _firstTangent;

  /// Largest angle (radians) between the end tangent of one segment and the
  /// start tangent of the next (closing joins included).
  double worstJoin = 0;
  String worstAt = '';
  String _last = '';

  /// Largest gap between a segment's start and the previous end.
  double worstGap = 0;

  /// Points along the outline (8 per cubic, every 0.1 rad on arcs).
  final List<Offset> points = [];

  void _join(Offset tangent) {
    final previous = _inTangent;
    if (previous == null) {
      _firstTangent = tangent;
      return;
    }
    final cross = previous.dx * tangent.dy - previous.dy * tangent.dx;
    final dot = previous.dx * tangent.dx + previous.dy * tangent.dy;
    final angle = math.atan2(cross, dot).abs();
    if (angle > worstJoin) {
      worstJoin = angle;
      worstAt = '$_last → $_current';
    }
  }

  @override
  void moveTo(double x, double y) {
    _current = _start = Offset(x, y);
    _inTangent = _firstTangent = null;
  }

  @override
  void lineTo(double x, double y) {
    final to = Offset(x, y);
    _join(to - _current);
    _inTangent = to - _current;
    _current = to;
    _last = 'line';
    points.add(to);
  }

  @override
  void cubicTo(double x1, double y1, double x2, double y2, double x3, double y3) {
    final p0 = _current, p1 = Offset(x1, y1), p2 = Offset(x2, y2), p3 = Offset(x3, y3);
    final t0 = p1 != p0 ? p1 - p0 : p2 - p0;
    final t1 = p3 != p2 ? p3 - p2 : p3 - p1;
    if (t0.distance > 1e-9) _join(t0);
    if (t1.distance > 1e-9) _inTangent = t1;
    for (var i = 1; i <= 8; i++) {
      final t = i / 8, s = 1 - t;
      points.add(p0 * (s * s * s) + p1 * (3 * s * s * t) + p2 * (3 * s * t * t) + p3 * (t * t * t));
    }
    _current = p3;
    _last = 'cubic $p0 $p1 $p2 $p3';
  }

  @override
  void arc(double cx, double cy, double radius, double start, double sweep) {
    final from = Offset(cx + radius * math.cos(start), cy + radius * math.sin(start));
    worstGap = math.max(worstGap, (from - _current).distance);
    Offset tangentAt(double a) => Offset(-math.sin(a), math.cos(a)) * sweep.sign;
    _join(tangentAt(start));
    final end = start + sweep;
    for (var a = 0.1; a < sweep.abs(); a += 0.1) {
      final t = start + a * sweep.sign;
      points.add(Offset(cx + radius * math.cos(t), cy + radius * math.sin(t)));
    }
    _current = Offset(cx + radius * math.cos(end), cy + radius * math.sin(end));
    _inTangent = tangentAt(end);
    _last = 'arc c=($cx, $cy) r=$radius $start $sweep';
  }

  @override
  void close() {
    worstGap = math.max(worstGap, (_start - _current).distance);
    final first = _firstTangent;
    if (first != null) _join(first);
  }
}

RecordingSink outline(List<StrokePoint> points, OutlineSpec spec) {
  final sink = RecordingSink();
  StrokeOutline.emit(sink, points, spec);
  return sink;
}

const ballpoint = OutlineSpec(width: 2, thinning: 0.25, streamline: 0.4);
const stabilised = OutlineSpec(width: 2, thinning: 0.25, streamline: 1);

double degrees(double radians) => radians * 180 / math.pi;

void main() {
  final hw = Handwriting(seed: 3);
  final writing = [
    hw.cursive(const Offset(0, 30), [e, l, l, e, u, e, l, e]),
    hw.oval(const Offset(10, 60), 4, 4.5),
    hw.letterS(const Offset(30, 60), 9),
    hw.line(const Offset(0, 90), const Offset(60, 70)),
  ];

  test('outlines join tangentially everywhere (no facets or kinks)', () {
    for (final width in [1.5, 2.5, 4.0, 12.0]) {
      final spec = OutlineSpec(width: width, thinning: 0.6, streamline: 0.4);
      for (final stroke in writing) {
        final sink = outline(stroke, spec);
        expect(degrees(sink.worstJoin), lessThan(1.0), reason: 'width $width ${sink.worstAt}');
        expect(sink.worstGap, lessThan(1e-6), reason: 'width $width');
      }
    }
  });

  test('with the stabiliser up, a jittery straight line gets smooth, straight edges', () {
    // 240 Hz samples of a steady 180 units/s line with 0.2 units of jitter.
    final rng = math.Random(11);
    double noise() => (rng.nextDouble() + rng.nextDouble() + rng.nextDouble() - 1.5) * 0.4;
    final points = [for (var x = 0.0; x <= 80; x += 0.75) StrokePoint(x + noise(), noise(), 0.5)];
    final path = StrokeOutline.build(points, stabilised);
    for (final upper in [true, false]) {
      // The visible edge: where the filled area ends, found by bisection.
      final side = [for (var x = 6.0; x <= 74; x += 0.5) Offset(x, _edgeY(path, x, upper: upper))];
      // No bumps: the edge's radius of curvature (through points 2 units
      // apart) stays above ~6 units — a gentle drift, invisible at normal
      // zoom. (Smoothing harder would round off small handwriting.)
      expect(_maxCurvature(side, 2), lessThan(0.16));
      expect(_maxResidual(side), lessThan(0.35));
    }
  });

  test('at stabiliser 0 the ink follows the raw pen path', () {
    // A zigzag with 1-unit teeth: any smoothing would flatten them.
    final points = [for (var i = 0; i <= 40; i++) StrokePoint(i * 1.0, i.isEven ? 0 : 1, 0.5)];
    const raw = OutlineSpec(width: 1, thinning: 0.25, streamline: 0);
    final path = StrokeOutline.build(points, raw);
    for (var i = 2; i < 38; i++) {
      // The pen's own sample is inside the ink; the far side of the zigzag
      // isn't covered (the teeth survive).
      expect(path.contains(Offset(i.toDouble(), i.isEven ? 0 : 1)), isTrue);
      expect(path.contains(Offset(i.toDouble(), i.isEven ? 1.2 : -0.2)), isFalse);
    }
  });

  test('small cursive loops keep their size', () {
    // A clean circle of radius 3 (an "o" in small handwriting).
    final circle = [
      for (var i = 0; i <= 240; i++)
        StrokePoint(
          3 * math.cos(i / 240 * 2.2 * math.pi),
          3 * math.sin(i / 240 * 2.2 * math.pi),
          0.5,
        ),
    ];
    final sink = outline(circle, ballpoint);
    // Away from the stroke's overlapping ends.
    final radii = [
      for (final p in sink.points)
        if (p.direction > 0.6 && p.direction < 2.6 || p.direction < -0.6) p.distance,
    ];
    final inner = radii.where((r) => r < 3).fold<double>(9, math.min);
    final outer = radii.where((r) => r > 3).fold<double>(0, math.max);
    expect(outer, closeTo(4, 0.1));
    expect(inner, closeTo(2, 0.1));
  });

  test('a hairpin turn leaves no hole at its apex', () {
    final hairpin = [
      for (var x = 0.0; x <= 30; x += 0.7) StrokePoint(x, 0, 0.5),
      for (var x = 30.0; x >= 0; x -= 0.7) StrokePoint(x, 1.2, 0.5),
    ];
    const spec = OutlineSpec(width: 6, thinning: 0, streamline: 0.4);
    final path = StrokeOutline.build(hairpin, spec);
    for (var x = 20.0; x <= 31; x += 0.25) {
      for (var y = -1.5; y <= 2.7; y += 0.25) {
        expect(path.contains(Offset(x, y)), isTrue, reason: '($x, $y)');
      }
    }
  });

  test('with the stabiliser off, the stroke being drawn reaches the pen (no lag)', () {
    final points = [for (var i = 0; i <= 60; i++) StrokePoint(i * 1.5, 10 * math.sin(i / 8), 0.5)];
    final sink = RecordingSink();
    const spec = OutlineSpec(width: 2, thinning: 0.25, streamline: 0);
    StrokeOutline.emit(sink, points, spec, complete: false);
    final tip = points.last.offset;
    final reach = sink.points.map((p) => (p - tip).distance).reduce(math.min);
    expect(reach, lessThan(1.05), reason: 'outline passes within a radius of the pen');
  });

  test('random scribbles always build finite outlines', () {
    final rng = math.Random(1);
    for (var n = 0; n < 300; n++) {
      final count = 1 + rng.nextInt(40);
      var p = Offset.zero;
      final points = <StrokePoint>[];
      for (var i = 0; i < count; i++) {
        if (rng.nextDouble() > 0.2) p += Offset(rng.nextDouble() - 0.5, rng.nextDouble() - 0.5) * 6;
        points.add(StrokePoint(p.dx, p.dy, rng.nextDouble()));
      }
      final spec = OutlineSpec(
        width: 0.2 + rng.nextDouble() * 30,
        thinning: rng.nextDouble(),
        streamline: rng.nextDouble(),
        flatCaps: rng.nextBool(),
      );
      final bounds = StrokeOutline.build(points, spec).getBounds();
      expect(bounds.isFinite, isTrue, reason: '$n');
      expect(bounds.isEmpty, isFalse, reason: '$n');
    }
  });

  test('building a 1000-point stroke stays fast', () {
    final long = [
      for (var i = 0; i < 1000; i++)
        StrokePoint(
          i * 0.8 + 3 * math.sin(i / 9),
          12 * math.sin(i / 14) + 0.15 * math.sin(i * 2.3),
          0.5 + 0.2 * math.sin(i / 30),
        ),
    ];
    for (var i = 0; i < 20; i++) {
      StrokeOutline.build(long, ballpoint, complete: false);
    }
    final watch = Stopwatch()..start();
    const runs = 50;
    for (var i = 0; i < runs; i++) {
      StrokeOutline.build(long, ballpoint, complete: false);
    }
    final ms = watch.elapsedMicroseconds / runs / 1000;
    // ignore: avoid_print
    print('1000-point outline: ${ms.toStringAsFixed(2)} ms');
    expect(ms, lessThan(4));
  });
}

/// Largest distance of [points] from their least-squares line.
/// The y of the filled region's upper/lower boundary at [x].
double _edgeY(Path path, double x, {required bool upper}) {
  var inside = 0.0, outside = upper ? -20.0 : 20.0;
  for (var i = 0; i < 40; i++) {
    final mid = (inside + outside) / 2;
    if (path.contains(Offset(x, mid))) {
      inside = mid;
    } else {
      outside = mid;
    }
  }
  return inside;
}

double _maxResidual(List<Offset> points) {
  final n = points.length;
  final mx = points.fold<double>(0, (s, p) => s + p.dx) / n;
  final my = points.fold<double>(0, (s, p) => s + p.dy) / n;
  var sxx = 0.0, sxy = 0.0;
  for (final p in points) {
    sxx += (p.dx - mx) * (p.dx - mx);
    sxy += (p.dx - mx) * (p.dy - my);
  }
  final slope = sxy / sxx;
  final norm = math.sqrt(1 + slope * slope);
  return points.fold<double>(
    0,
    (m, p) => math.max(m, ((p.dy - my) - slope * (p.dx - mx)).abs() / norm),
  );
}

/// Largest Menger curvature of [points] (sorted by x) over triples about
/// [spacing] apart.
double _maxCurvature(List<Offset> points, double spacing) {
  final picked = <Offset>[points.first];
  for (final p in points) {
    if (p.dx - picked.last.dx >= spacing) picked.add(p);
  }
  var worst = 0.0;
  for (var i = 1; i + 1 < picked.length; i++) {
    final a = picked[i - 1], b = picked[i], c = picked[i + 1];
    final cross = (b - a).dx * (c - a).dy - (b - a).dy * (c - a).dx;
    final k = 2 * cross.abs() / ((b - a).distance * (c - b).distance * (c - a).distance);
    worst = math.max(worst, k);
  }
  return worst;
}
