import 'dart:math' as math;

import 'package:len/ink/lab/replay_run.dart';
import 'package:len/ink/render/stroke_renderer.dart';

import 'metric.dart';
import 'outline_geometry.dart';
import 'temporal_metrics.dart';

/// Per-frame cost of the live stroke against its length, for the longest
/// contact of a replay.
class FrameCost {
  FrameCost(this.points, this.micros, this.subpaths);
  final int points;
  final double micros;
  final int subpaths;
}

/// The live-outline cost of every frame of the longest contact in [r].
List<FrameCost> frameCosts(ReplayResult r) {
  final runs = contactRuns(r);
  if (runs.isEmpty) return const [];
  final run = runs.reduce((a, b) => a.frames.length >= b.frames.length ? a : b);
  return [
    for (final f in run.frames)
      FrameCost(
        f.points.length,
        f.build.inMicroseconds.toDouble(),
        outlineOf(
          f.points,
          tool: r.pen.tool,
          width: r.pen.width,
          style: r.style,
          complete: false,
        ).moves,
      ),
  ];
}

double _median(Iterable<double> v) {
  final s = v.toList()..sort();
  return s.isEmpty ? double.nan : s[s.length ~/ 2];
}

/// (g) Performance: building the live stroke each frame must cost about
/// the same at the end of a long stroke as at its start (O(1) per frame,
/// not O(length)), and committing at pen-up must stay cheap.
///
/// `perf.flatness` = median frame cost over the last fifth of the frames ÷
/// over the first fifth (after warm-up). Times are this machine's (JIT
/// tests); a tablet is several times slower.
List<Metric> performance(ReplayResult r) {
  final costs = frameCosts(r);
  if (costs.length < 20) return const [];
  final fifth = costs.length ~/ 5;
  final early = _median(costs.skip(5).take(fifth).map((c) => c.micros));
  final late = _median(costs.skip(costs.length - fifth).map((c) => c.micros));
  final commits = <(int, double)>[];
  for (final f in r.frames) {
    for (final s in f.committed) {
      // As the app does: the committed stroke's outline (handed over by the
      // live builder at pen-up when it drew the stroke).
      final watch = Stopwatch()..start();
      StrokeRenderer.pathOf(s);
      commits.add((s.points.length, (f.commitTime + watch.elapsed).inMicroseconds / 1000));
    }
  }
  // The longest third of the strokes (cost must not grow with length), as
  // a median: one garbage-collection pause is not the commit's cost.
  commits.sort((a, b) => b.$1.compareTo(a.$1));
  final longest = commits.take(math.max(1, commits.length ~/ 3)).map((c) => c.$2);
  final commit = longest.isEmpty ? 0.0 : _median(longest);
  return [
    Metric(
      'perf.flatness',
      late / math.max(early, 1),
      limit: 2,
      unit: '×',
      note:
          'live outline: ${early.round()} µs early → ${late.round()} µs at '
          '${costs.last.points} points',
    ),
    Metric('perf.frameCost', late, limit: 1000, unit: ' µs', note: 'median live build, last fifth'),
    Metric(
      'perf.commit',
      commit,
      limit: 8,
      unit: ' ms',
      note: 'pen-up handling + committed outline (median, longest third of the strokes)',
    ),
    Metric(
      'perf.subpaths',
      costs.last.subpaths.toDouble(),
      limit: 64,
      note: 'sub-paths in the last live outline (the GPU re-tessellates all every frame)',
    ),
  ];
}
