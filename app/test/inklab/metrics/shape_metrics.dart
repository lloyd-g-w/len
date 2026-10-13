import 'dart:math' as math;
import 'dart:ui';

import 'package:len/domain/stroke.dart';
import 'package:len/ink/input/stroke_sampler.dart';
import 'package:len/ink/lab/replay_run.dart';
import 'package:len/ink/render/hooks.dart';
import 'package:len/ink/render/stroke_outline.dart';
import 'package:len/ink/render/stroke_renderer.dart';

import 'metric.dart';
import 'outline_geometry.dart';
import 'polyline_index.dart';
import 'smoothing.dart';
import 'truth.dart';

/// A committed stroke paired with the truth it should match.
class StrokePair {
  StrokePair(this.stroke, this.truth, this.line, this.scale);
  final Stroke stroke;
  final Truth truth;

  /// Its centre line on screen (null for a dot).
  final ScreenLine? line;
  final double scale;

  /// The engine's hook rules for this stroke, in screen px.
  HookFinder get hooks {
    final spec = StrokeRenderer.specFor(stroke.tool, stroke.width, stroke.style);
    final h = StrokeOutline.paramsOf(stroke.points, spec).hooks;
    return HookFinder.lengths(
      maxStart: h.maxStart * scale,
      maxEnd: h.maxEnd * scale,
      body: h.body * scale,
      local: h.local * scale,
    );
  }

  /// The ink radius (screen px) the true device [pressure] (normalised
  /// 0..1, as the truth holds it) gives: through the input's pressure
  /// curve (`StrokeSampler.strokePressure`), then the pen's width.
  double radiusFor(double pressure) =>
      StrokeRenderer.specFor(
        stroke.tool,
        stroke.width,
        stroke.style,
      ).radiusFor(StrokeSampler.strokePressure(pressure)) *
      scale;

  late final PolylineIndex truthIndex = PolylineIndex(truth.path, cell: 3);
  late final PolylineIndex lineIndex = PolylineIndex(line!.c, cell: 3);

  /// Truth pressure nearest to screen point [p].
  double truthPressureAt(Offset p) {
    final seg = truthIndex.nearest(p).segment;
    return truth.pressure[math.min(seg, truth.pressure.length - 1)];
  }
}

/// Pairs committed strokes with truths in order (strays are left over).
List<StrokePair> pairStrokes(ReplayResult replay, List<Truth> truths) {
  final strokes = replay.strokes;
  return [
    for (var i = 0; i < math.min(strokes.length, truths.length); i++)
      StrokePair(
        strokes[i],
        truths[i],
        truths[i].isTap ? null : _line(replay, strokes[i]),
        replay.frameOf(strokes[i]).viewScale,
      ),
  ];
}

ScreenLine? _line(ReplayResult replay, Stroke s) {
  final view = replay.frameOf(s);
  final line = centerlineOf(
    s.points,
    tool: s.tool,
    width: s.width,
    style: s.style,
    complete: true,
    scale: view.viewScale,
    offset: view.viewOffset,
  );
  return line == null || line.c.length < 3 ? null : line;
}

/// (a) Fidelity: how far the committed centre line strays from the true
/// path (both directions, so loops that shrink count too), and how far
/// its width strays from the true pressure's width.
List<Metric> fidelity(List<StrokePair> pairs, double streamline) {
  final dev = Worst(), width = Worst();
  var sum = 0.0;
  var n = 0;
  for (final p in pairs) {
    final line = p.line;
    if (line == null) continue;
    for (final c in line.c) {
      final d = p.truthIndex.distance(c);
      dev.add(d, c);
      sum += d * d;
      n++;
    }
    final reach = line.r.reduce(math.max);
    // Raw samples include the pen-down/up flicks the engine trims (exact
    // truths do not): those may go undrawn (`HookFinder`'s reach).
    final hooks = p.hooks;
    final startReach = p.truth.exact ? reach : math.max(reach, hooks.maxStart);
    final endReach = p.truth.exact ? reach : math.max(reach, hooks.maxEnd);
    final along = arcLengths(p.truth.path);
    for (var i = 0; i < p.truth.path.length; i++) {
      if (along[i] < startReach || along.last - along[i] < endReach) continue;
      dev.add(p.lineIndex.distance(p.truth.path[i]), p.truth.path[i]);
    }
    // Width, away from the ends (pen-down/up ramps are shaped).
    // The truth point is the nearest one *along* the stroke (near the same
    // fraction of its length), not anywhere: a stroke crossing itself
    // passes the same spot twice with different pressures.
    final ends = 2 * p.stroke.width * p.scale;
    final window = 10 + 4 * reach;
    var k0 = 0;
    for (var i = 0; i < line.c.length; i++) {
      final s = i * line.step;
      final target = along.last * s / math.max(line.length, 1e-9);
      while (k0 < along.length - 1 && along[k0] < target - window) {
        k0++;
      }
      while (k0 > 0 && along[k0 - 1] >= target - window) {
        k0--;
      }
      var best = double.infinity;
      var at = k0;
      for (var k = k0; k < along.length && along[k] <= target + window; k++) {
        final d = (p.truth.path[k] - line.c[i]).distance;
        if (d < best) (best, at) = (d, k);
      }
      if (s < ends || line.length - s < ends) continue;
      final truthR = p.radiusFor(p.truth.pressure[math.min(at, p.truth.pressure.length - 1)]);
      width.add((line.r[i] - truthR).abs() / truthR, line.c[i]);
    }
  }
  final exact = pairs.every((p) => p.truth.exact);
  final slack = exact ? 0.0 : 0.3; // raw samples carry jitter themselves
  return [
    Metric(
      'fidelity.hausdorff',
      dev.value,
      limit: byStabiliser(streamline, 0.5, 1.3, 3.5) + slack,
      unit: 'px',
      where: dev.where,
    ),
    Metric(
      'fidelity.rms',
      n == 0 ? double.nan : math.sqrt(sum / n),
      limit: byStabiliser(streamline, 0.2, 0.4, 1.0) + slack,
      unit: 'px',
    ),
    Metric(
      'fidelity.width',
      width.value * 100,
      limit: byStabiliser(streamline, 15, 25, 40),
      unit: '%',
      where: width.where,
    ),
  ];
}

/// (b) Detail: how far cusp tips and tight curves (radius < 6 px) of the
/// true path are from the centre line — over-smoothing pulls them in.
List<Metric> detail(List<StrokePair> pairs, double streamline) {
  final worst = Worst();
  var any = false;
  for (final p in pairs) {
    if (p.line == null) continue;
    var points = [...p.truth.cusps, ...tightPoints(p.truth.path, 6)];
    if (!p.truth.exact) {
      // Raw samples: the pen-down/up flicks the engine trims are tight too.
      final hooks = p.hooks;
      final along = arcLengths(p.truth.path);
      final index = PolylineIndex(p.truth.path, cell: 3);
      points = [
        for (final t in points)
          if (along[index.nearest(t).segment] >= hooks.maxStart &&
              along.last - along[index.nearest(t).segment] >= hooks.maxEnd)
            t,
      ];
    }
    for (final t in points) {
      any = true;
      worst.add(p.lineIndex.distance(t), t);
    }
  }
  if (!any) return const [];
  return [
    Metric(
      'detail.retraction',
      worst.value,
      limit: byStabiliser(streamline, 0.5, 1.3, 3.5),
      unit: 'px',
      where: worst.where,
    ),
  ];
}

/// Points of [path] whose radius of curvature (over ±1 px) is below [radius].
List<Offset> tightPoints(List<Offset> path, double radius) {
  final along = arcLengths(path);
  final out = <Offset>[];
  var j0 = 0, j1 = 0;
  for (var i = 0; i < path.length; i += 4) {
    while (j0 < i && along[i] - along[j0 + 1] >= 1) {
      j0++;
    }
    while (j1 < path.length - 1 && along[j1] - along[i] < 1) {
      j1++;
    }
    if (j0 >= i || j1 <= i) continue;
    final k = curvature(path[j0], path[i], path[j1]);
    if (k > 1 / radius) out.add(path[i]);
  }
  return out;
}
