import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/render/outline_sink.dart';
import 'package:len/ink/render/stroke_outline.dart';

import 'support/property.dart';

/// Records an outline's contours and checks them as it goes.
class _Contours implements OutlineSink {
  final List<List<Offset>> closed = [];
  final List<String> problems = [];
  List<Offset>? _open;
  Offset? _at;

  void _point(String what, double x, double y) {
    if (!x.isFinite || !y.isFinite) problems.add('$what: not finite ($x, $y)');
    _open?.add(Offset(x, y));
  }

  void _needOpen(String what) {
    if (_open == null) problems.add('$what without moveTo');
  }

  @override
  void moveTo(double x, double y) {
    if (_open != null) problems.add('moveTo inside an open contour');
    _open = [];
    _point('moveTo', x, y);
    _at = Offset(x, y);
  }

  @override
  void lineTo(double x, double y) {
    _needOpen('lineTo');
    _point('lineTo', x, y);
    _at = Offset(x, y);
  }

  @override
  void cubicTo(double x1, double y1, double x2, double y2, double x3, double y3) {
    _needOpen('cubicTo');
    final x0 = _at?.dx ?? x1, y0 = _at?.dy ?? y1;
    for (final c in [x1, y1, x2, y2]) {
      if (!c.isFinite) problems.add('cubic control not finite: $c');
    }
    // Points along the curve: a wild control point bulges it.
    for (final t in const [0.25, 0.5, 0.75]) {
      final u = 1 - t;
      double at(double a, double b, double c, double d) =>
          u * u * u * a + 3 * u * u * t * b + 3 * u * t * t * c + t * t * t * d;
      _point('cubic', at(x0, x1, x2, x3), at(y0, y1, y2, y3));
    }
    _point('cubicTo', x3, y3);
    _at = Offset(x3, y3);
  }

  @override
  void arc(double cx, double cy, double radius, double start, double sweep) {
    _needOpen('arc');
    if (!radius.isFinite || radius < 0) problems.add('arc radius $radius');
    if (!start.isFinite || !sweep.isFinite) problems.add('arc angles $start, $sweep');
    // The arc starts at the current point (within rounding).
    final from = Offset(cx + radius * math.cos(start), cy + radius * math.sin(start));
    if (_at case final at? when (at - from).distance > 1e-3 * math.max(1, radius) + 1e-6) {
      problems.add('arc starts at $from, pen at $at');
    }
    // Its extremes lie within the circle: bound by the circle's box.
    _point('arc', cx - radius, cy - radius);
    _point('arc', cx + radius, cy + radius);
    final end = start + sweep;
    _at = Offset(cx + radius * math.cos(end), cy + radius * math.sin(end));
    _open?.add(_at!);
  }

  @override
  void close() {
    _needOpen('close');
    if (_open case final c?) closed.add(c);
    _open = null;
  }

  /// Whether the sink ended with every contour closed.
  bool get allClosed => _open == null;
}

/// A random stroke: a walk of steps (some repeated points, some jumps,
/// some reversals) with pressure anywhere in 0..1, at any scale.
List<StrokePoint> _stroke(math.Random r) {
  final scale = Gens.oneOf([1e-3, 0.05, 1.0, 1.0, 1.0, 30.0])(r);
  final origin = Gens.oneOf([0.0, -5000.0, 1e5])(r);
  final n = Gens.oneOf([1, 2, 3, 5, 12, 40, 200])(r);
  var x = origin, y = origin, angle = r.nextDouble() * 2 * math.pi;
  final points = <StrokePoint>[];
  for (var i = 0; i < n; i++) {
    points.add(
      StrokePoint(
        x,
        y,
        Gens.anyOf([
          Gens.doubleIn(0, 1),
          Gens.oneOf([0.0, 1.0]),
        ])(r),
      ),
    );
    switch (r.nextInt(10)) {
      case 0: // Stay put (a still pen).
        break;
      case 1: // Turn back.
        angle += math.pi;
      case 2: // A sharp corner.
        angle += Gens.doubleIn(-2.5, 2.5)(r);
      default:
        angle += Gens.doubleIn(-0.3, 0.3)(r);
    }
    final step = scale * (r.nextInt(10) == 0 ? 20 : Gens.doubleIn(0.2, 3)(r));
    if (r.nextInt(10) != 0) {
      x += step * math.cos(angle);
      y += step * math.sin(angle);
    }
  }
  return points;
}

OutlineSpec _spec(math.Random r) {
  // Pens are at least 0.5 wide (PenDefaults.minWidth); a dot is never
  // narrower than 0.25.
  final width = Gens.oneOf([0.5, 1.0, 2.0, 6.0, 24.0, 80.0])(r);
  final tapered = r.nextBool();
  return OutlineSpec(
    width: width,
    thinning: Gens.oneOf([0.0, 0.3, 0.7, 1.0])(r),
    streamline: Gens.oneOf([0.0, 0.25, 0.5, 1.0])(r),
    flatCaps: r.nextInt(4) == 0,
    unit: r.nextBool() ? 0 : Gens.doubleIn(0.01, 5)(r),
    taperStart: tapered ? width * Gens.doubleIn(0, 6)(r) : 0,
    taperEnd: tapered ? width * Gens.doubleIn(0, 6)(r) : 0,
    startPhase: r.nextInt(4) == 0 ? Gens.doubleIn(0.01, 1)(r) : 0,
    cutEnd: r.nextInt(4) == 0,
  );
}

typedef _Case = ({List<StrokePoint> points, OutlineSpec spec, bool complete});

_Case _case(math.Random r) => (points: _stroke(r), spec: _spec(r), complete: r.nextInt(3) != 0);

String _describe(_Case c) =>
    'complete: ${c.complete}, width ${c.spec.width}, thinning ${c.spec.thinning}, '
    'streamline ${c.spec.streamline}, flat ${c.spec.flatCaps}, unit ${c.spec.unit}, '
    'taper ${c.spec.taperStart}/${c.spec.taperEnd}, phase ${c.spec.startPhase}, '
    'cutEnd ${c.spec.cutEnd}\n${c.points}';

void main() {
  test('outlines are closed, finite and within the stroke’s reach, for any input', () async {
    await forAll(_case, describe: _describe, runs: 1200, (c) {
      final sink = _Contours();
      StrokeOutline.emit(sink, c.points, c.spec, complete: c.complete);
      expect(sink.problems, isEmpty);
      expect(sink.allClosed, isTrue, reason: 'an open contour at the end');
      expect(sink.closed, isNotEmpty, reason: 'a stroke always leaves ink');
      // Ink never reaches further from the points than the widest pen
      // radius (the width), plus a little where the resampled curve rounds
      // a sharp turn between far-apart points: never a spike.
      var gap = 0.0;
      for (var i = 1; i < c.points.length; i++) {
        gap = math.max(gap, (c.points[i].offset - c.points[i - 1].offset).distance);
      }
      final xs = c.points.map((p) => p.x), ys = c.points.map((p) => p.y);
      final precision = 1e-6 * xs.followedBy(ys).map((v) => v.abs()).reduce(math.max);
      final box = Rect.fromLTRB(
        xs.reduce(math.min),
        ys.reduce(math.min),
        xs.reduce(math.max),
        ys.reduce(math.max),
      ).inflate(c.spec.width + 0.05 * gap + precision);
      for (final contour in sink.closed) {
        expect(contour, isNotEmpty);
        for (final p in contour) {
          expect(box.inflate(1e-9).contains(p), isTrue, reason: '$p outside $box');
        }
      }
    });
  });

  test('the same input always gives the same outline', () async {
    await forAll(_case, describe: _describe, runs: 100, seed: 5000, (c) {
      String outline() {
        final path = StrokeOutline.build(c.points, c.spec, complete: c.complete);
        return '${path.getBounds()}';
      }

      expect(outline(), outline());
    });
  });

  test('the path a painter gets has finite, non-empty bounds', () async {
    await forAll(_case, describe: _describe, runs: 200, seed: 9000, (c) {
      final bounds = StrokeOutline.build(c.points, c.spec, complete: c.complete).getBounds();
      expect(bounds.isFinite, isTrue, reason: '$bounds');
      expect(bounds.isEmpty, isFalse, reason: '$bounds');
    });
  });
}
