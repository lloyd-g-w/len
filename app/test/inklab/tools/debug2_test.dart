import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/ink/lab/replay_run.dart';

import '../metrics/outline_geometry.dart';
import '../metrics/raster.dart';
import '../metrics/temporal_metrics.dart';
import '../sim/cases.dart';

final String _case = const String.fromEnvironment('CASE', defaultValue: 'lines');
final double _st = double.parse(const String.fromEnvironment('ST', defaultValue: '1'));

void main() {
  test('debug temporal', () {
    final c = simCases.firstWhere((c) => c.name == _case);
    final rec = c.record(defaultPen.copyWith(streamline: _st));
    final r = ReplayResult.run(rec.recording);
    final dpr = r.recording.meta.devicePixelRatio;
    final toPx = physical(r);
    final zone = (r.pen.width * r.viewScale + 1) * dpr;
    final reach = r.pen.width * r.viewScale * dpr + 1.5 * dpr;
    for (final run in contactRuns(r)) {
      Coverage? prev;
      PolygonSink? prevSink;
      for (var i = 0; i < run.frames.length; i++) {
        final pts = run.frames[i].points;
        final sink = outlineOf(pts,
            tool: r.pen.tool, width: r.pen.width, style: r.style, complete: false, map: toPx);
        final cov = rasterize(sink.contours, boundsOf(sink.contours), subRows: int.parse(const String.fromEnvironment("SUB", defaultValue: "16")));
        if (prev != null && prevSink != null) {
          final prevPts = run.frames[i - 1].points;
          final tip = toPx(Offset(prevPts.last.x, prevPts.last.y));
          final fresh = [for (final p in pts.skip(prevPts.length - 1)) toPx(Offset(p.x, p.y))];
          final changed = changedPixels(prev, cov, nearPolyline(fresh, reach), 0.2);
          final out = changed.where((p) => (p - tip).distance > zone).toList();
          if (out.isNotEmpty) {
            // ignore: avoid_print
            print('frame ${run.frames[i].index} pts ${prevPts.length}->${pts.length} '
                'moves ${prevSink.moves}->${sink.moves} verbs ${prevSink.verbs}->${sink.verbs} '
                'changed ${out.map((p) => '(${(p / dpr).dx.toStringAsFixed(1)},${(p / dpr).dy.toStringAsFixed(1)}) d=${((p - tip).distance / dpr).toStringAsFixed(1)} '
                    'cov ${prev!.at(p.dx.floor(), p.dy.floor()).toStringAsFixed(2)}->${cov.at(p.dx.floor(), p.dy.floor()).toStringAsFixed(2)}').join(' ')} '
                'tip ${(tip / dpr)}');
          }
        }
        prev = cov;
        prevSink = sink;
      }
    }
  });
}
