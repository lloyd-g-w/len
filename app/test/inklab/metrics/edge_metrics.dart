import 'dart:math' as math;
import 'dart:ui';

import 'package:len/ink/lab/replay_run.dart';

import 'metric.dart';
import 'outline_geometry.dart';
import 'raster.dart';
import 'shape_metrics.dart';
import 'smoothing.dart';
import 'truth.dart';

/// Zoom at which edge smoothness is judged.
const double zoom = 16;

/// (c) Smoothness: bumps on the outline's edges and in its width, and
/// facets (kinks) along the centre line, as they would look at 16× zoom.
///
/// Bumps are the residual of a local parabola fit (±1.5 px), facets the
/// residual of the turn per sample against its neighbours, so genuine
/// curvature counts for neither. Skipped: reversals (cusps), the ends, and
/// bends tighter than the fit window (a parabola cannot follow them).
List<Metric> smoothness(List<ScreenLine> lines) {
  final edge = Worst(), width = Worst(), facet = Worst();
  for (final line in lines) {
    final c = line.c, r = line.r;
    final m = math.max(2, (1.5 / line.step).ceil());
    final skip = <int>{
      for (final k in [...line.corners, ...reversals(line)])
        for (var j = k - m - 2; j <= k + m + 2; j++) j,
    };
    final endReach = (r.reduce(math.max) * 2 / line.step).ceil() + m;
    final kappa = _smoothCurvature(c, m);
    bool used(int i) =>
        i >= endReach &&
        i < c.length - endReach &&
        !skip.contains(i) &&
        kappa[i] * (1.5 + r[i]) < 0.5;
    final n = normals(c);
    for (final side in [1.0, -1.0]) {
      final ex = [for (var i = 0; i < c.length; i++) c[i].dx + side * r[i] * n[i].dx];
      final ey = [for (var i = 0; i < c.length; i++) c[i].dy + side * r[i] * n[i].dy];
      final sx = savitzkyGolay(ex, m), sy = savitzkyGolay(ey, m);
      for (var i = 1; i < c.length - 1; i++) {
        if (!used(i)) continue;
        final residual = (ex[i] - sx[i]) * n[i].dx + (ey[i] - sy[i]) * n[i].dy;
        edge.add(residual.abs() * zoom, c[i]);
      }
    }
    final sr = savitzkyGolay(r, m);
    final turns = [0.0, for (var i = 1; i < c.length - 1; i++) turn(c[i - 1], c[i], c[i + 1]), 0.0];
    final smoothTurns = savitzkyGolay(turns, m);
    for (var i = 1; i < c.length - 1; i++) {
      if (!used(i)) continue;
      width.add((r[i] - sr[i]).abs() * zoom, c[i]);
      facet.add((turns[i] - smoothTurns[i]).abs() * 180 / math.pi, c[i]);
    }
  }
  return [
    Metric('smooth.edgeBump16x', edge.value, limit: 1, unit: 'px', where: edge.where),
    Metric('smooth.widthBump16x', width.value, limit: 1, unit: 'px', where: width.where),
    Metric('smooth.facet', facet.value, limit: 5, unit: '°', where: facet.where),
  ];
}

/// Curvature of the parabola-smoothed line (±[m] samples) at each sample.
List<double> _smoothCurvature(List<Offset> c, int m) {
  final sx = savitzkyGolay([for (final p in c) p.dx], m);
  final sy = savitzkyGolay([for (final p in c) p.dy], m);
  final h = math.max(1, m ~/ 2);
  return [
    for (var i = 0; i < c.length; i++)
      i < h || i >= c.length - h
          ? 0.0
          : curvature(
              Offset(sx[i - h], sy[i - h]),
              Offset(sx[i], sy[i]),
              Offset(sx[i + h], sy[i + h]),
            ),
  ];
}

/// (f) Ends: no blob (an end wider than the body and than the true
/// pressure there asks for), no nub (ink beyond the
/// true path near an end: pen-down/up hooks), no stray strokes (bounces),
/// and dots (taps) of the right size.
List<Metric> ends(
  ReplayResult replay,
  List<StrokePair> pairs,
  List<Truth> truths,
  double streamline,
) {
  final blob = Worst(), nub = Worst(), dot = Worst();
  for (final p in pairs) {
    final line = p.line;
    if (line == null) {
      if (p.truth.isTap) _dotSize(replay, p, dot);
      continue;
    }
    final body = [
      for (var i = 0; i < line.c.length; i++)
        if (i * line.step > 3 * line.r[i] && line.length - i * line.step > 3 * line.r[i]) line.r[i],
    ]..sort();
    if (body.isEmpty) continue;
    final median = body[body.length ~/ 2];
    final reach = 3 * p.stroke.width * p.scale;
    for (var i = 0; i < line.c.length; i++) {
      final s = i * line.step;
      if (s > reach && line.length - s > reach) continue;
      // A blob is wider than both the body and what the hand pressed there
      // (a real pen lands harder than it writes on, often).
      final pressed = p.radiusFor(p.truthPressureAt(line.c[i]));
      blob.add(line.r[i] / math.max(median, pressed), line.c[i]);
      nub.add(p.truthIndex.distance(line.c[i]), line.c[i]);
    }
  }
  final slack = truths.every((t) => t.exact) ? 0.0 : 0.3;
  return [
    Metric('ends.blob', blob.value, limit: 1.1, unit: '×', where: blob.where),
    Metric(
      'ends.nub',
      nub.value,
      limit: byStabiliser(streamline, 0.6, 1.2, 2.2) + slack,
      unit: 'px',
      where: nub.where,
    ),
    Metric(
      'ends.stray',
      (replay.strokes.length - truths.length).abs().toDouble(),
      limit: 0,
      note: '${replay.strokes.length} strokes for ${truths.length} intended',
    ),
    if (truths.any((t) => t.isTap))
      Metric('ends.dotSize', dot.value * 100, limit: 30, unit: '%', where: dot.where),
  ];
}

/// Relative size error of a tap's dot against the true peak pressure.
void _dotSize(ReplayResult replay, StrokePair p, Worst worst) {
  final s = p.stroke;
  final sink = outlineOf(
    s.points,
    tool: s.tool,
    width: s.width,
    style: s.style,
    complete: true,
    map: (o) => replay.screenOf(s)(o.dx, o.dy),
  );
  final b = boundsOf(sink.contours);
  final r = (b.width + b.height) / 4;
  final truthR = p.radiusFor(p.truth.pressure.reduce(math.max));
  worst.add((r - truthR).abs() / truthR, b.center);
}

/// Centre lines of every committed stroke of [replay] (skipping dots).
List<ScreenLine> committedLines(ReplayResult replay) => [
  for (final s in replay.strokes)
    if (centerlineOf(
          s.points,
          tool: s.tool,
          width: s.width,
          style: s.style,
          complete: true,
          scale: replay.frameOf(s).viewScale,
          offset: replay.frameOf(s).viewOffset,
        )
        case final line? when line.c.length > 8)
      line,
];

/// Samples of [line] where it doubles back (turns by more than 90° over
/// ±1 px): genuine cusps, whose sharpness is not a facet.
List<int> reversals(ScreenLine line) {
  final k = math.max(1, (1 / line.step).ceil());
  final c = line.c;
  return [
    for (var i = k; i < c.length - k; i++)
      if (turn(c[i - k], c[i], c[i + k]).abs() > math.pi / 2) i,
  ];
}
