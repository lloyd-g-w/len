// The low-latency overlay with flat ends (`WetInkEnds`): on Flutter's own
// live line, every frame, the overlay's flat-end rules draw what Flutter's
// live ink draws. (The overlay metrics with flat ends, against the ink
// Flutter will show: flat_ends_suite_test.dart.)
@Tags(['inklab'])
library;

import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/lab/replay_run.dart';
import 'package:len/ink/lab/wet_ink_ends.dart';
import 'package:len/ink/lab/wet_ink_model.dart';
import 'package:len/ink/pen/pen_ends.dart';
import 'package:len/ink/render/growable.dart';
import 'package:len/ink/render/ribbon_emitter.dart';
import 'package:len/ink/render/stroke_outline.dart';
import 'package:len/ink/render/stroke_renderer.dart';

import 'metrics/outline_geometry.dart';
import 'metrics/overlay_metrics.dart';
import 'metrics/raster.dart';
import 'metrics/temporal_metrics.dart';
import 'sim/cases.dart';

const _flat = PenEnds(style: StrokeEnds.flat);

void main() {
  for (final name in ['hooks', 'cursive', 'fast_loops']) {
    for (final st in [0.0, 1.0]) {
      test(
        'flat ends: on Flutter\'s line the overlay\'s rules draw Flutter\'s tip ($name@$st)',
        () {
          final c = simCases.firstWhere((c) => c.name == name);
          final r = ReplayResult.run(
            c.record(defaultPen.copyWith(streamline: st)).recording,
            ends: _flat,
          );
          final (gap, ghost) = _worstAgainstFlutter(r);
          expect(gap, 0);
          expect(ghost, lessThanOrEqualTo(1));
        },
      );
    }
  }
}

/// Over every live frame, the most physical pixels around the tip that
/// Flutter's live outline covers and the overlay's pieces (hulls, cuts and
/// sweeps from `WetInkEnds` on Flutter's own live line) do not, and the
/// other way round.
(int, int) _worstAgainstFlutter(ReplayResult r) {
  final spec = StrokeRenderer.specFor(r.pen.width, r.style);
  var worstGap = 0, worstGhost = 0;
  for (final f in r.frames) {
    if (f.points.length < 12) continue;
    final line = StrokeOutline.centerline(f.points, spec, complete: false)!;
    final n = line.live;
    if (n < 6) continue;
    final toPx = physical(r, f);
    final flutter = outlineOf(
      f.points,
      tool: r.pen.tool,
      width: r.pen.width,
      style: r.style,
      complete: false,
      map: toPx,
    ).contours;
    final x = DoubleBuffer(), y = DoubleBuffer();
    for (var i = 0; i < n; i++) {
      x.add(line.x[i]);
      y.add(line.y[i]);
    }
    final rr = [for (var i = 0; i < n; i++) line.r[i]];
    final ends = WetInkEnds.of(
      x,
      y,
      rr,
      [
        for (final k in line.corners)
          if (k < n - 1) k,
      ],
      n,
      first: 0,
      step: line.step,
      start: true,
      reach: RibbonEmitter.endReachFor(spec.width, line.step),
    );
    final overlay = [
      for (var i = 1; i < n; i++)
        for (final p in segmentPolygons(
          WetSegment(
            Offset(x[i - 1], y[i - 1]),
            Offset(x[i], y[i]),
            rr[i - 1],
            rr[i],
            cuts: [
              for (final k in ends.cuts)
                if (k.piece == i - 1) k.line,
            ],
            sweeps: [
              for (final s in ends.sweeps)
                if (s.piece == i - 1) (s.a, s.b),
            ],
          ),
        ))
          [for (final q in p) toPx(q)],
    ];
    final window = Rect.fromCircle(center: toPx(Offset(x[n - 1], y[n - 1])), radius: 40);
    final cf = Coverage.around(window)..fill(flutter);
    final co = Coverage.around(window)..fill(overlay);
    var gap = 0, ghost = 0;
    for (var py = window.top.floor(); py <= window.bottom.ceil(); py++) {
      for (var px = window.left.floor(); px <= window.right.ceil(); px++) {
        final d = cf.at(px, py) - co.at(px, py);
        if (d > 0.5) gap++;
        if (d < -0.5) ghost++;
      }
    }
    if (gap > worstGap) worstGap = gap;
    if (ghost > worstGhost) worstGhost = ghost;
  }
  return (worstGap, worstGhost);
}
