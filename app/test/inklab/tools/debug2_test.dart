import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/ink/lab/recording_codec.dart';
import 'package:len/ink/lab/replay_run.dart';
import 'package:len/ink/render/stroke_outline.dart';
import 'package:len/ink/render/stroke_renderer.dart';
import 'package:len/ink/render/stroke_shaper.dart';

import '../metrics/outline_geometry.dart';
import '../metrics/raster.dart';
import '../metrics/temporal_metrics.dart';

final String _case = const String.fromEnvironment('CASE', defaultValue: 'lines');
final double _st = double.parse(const String.fromEnvironment('ST', defaultValue: '1'));

void main() {
  test('debug temporal', () {
    final rec = RecordingCodec.decode(
      File('test/inklab/recordings/$_case.leninput').readAsBytesSync(),
    );
    final r = ReplayResult.run(rec, pen: rec.meta.pen.copyWith(streamline: _st));
    final dpr = r.recording.meta.devicePixelRatio;

    final zone = (r.pen.width * r.viewScale + 1) * dpr;
    final reach = r.pen.width * r.viewScale * dpr + 1.5 * dpr;
    for (final run in contactRuns(r)) {
      final toPx = physical(r, run.frames.first);
      Coverage? prev;
      PolygonSink? prevSink;
      for (var i = 0; i < run.frames.length; i++) {
        final pts = run.frames[i].points;
        final sink = outlineOf(
          pts,
          tool: r.pen.tool,
          width: r.pen.width,
          style: r.style,
          complete: false,
          map: toPx,
        );
        final cov = rasterize(
          sink.contours,
          boundsOf(sink.contours),
          subRows: int.parse(const String.fromEnvironment("SUB", defaultValue: "16")),
        );
        if (prev != null && prevSink != null) {
          final prevPts = run.frames[i - 1].points;
          final tip = toPx(Offset(prevPts.last.x, prevPts.last.y));
          final fresh = [for (final p in pts.skip(prevPts.length - 1)) toPx(Offset(p.x, p.y))];
          final changed = changedPixels(prev, cov, nearPolyline(fresh, reach), 0.2);
          final out = changed.where((p) => (p - tip).distance > zone).toList();
          if (out.isNotEmpty) {
            final spec = StrokeRenderer.specFor(r.pen.tool, r.pen.width, r.style);
            StrokeShaper shape(int n) {
              final s = StrokeShaper(StrokeOutline.paramsOf(pts, spec));
              StrokeOutline.feed(s, pts.sublist(0, n), spec, null);
              s.update();
              return s;
            }

            final sa = shape(prevPts.length), sb = shape(pts.length);
            var same = true;
            for (var i = 0; i < prevPts.length; i++) {
              if (prevPts[i] != pts[i]) same = false;
            }
            final px = out.first / dpr;
            var near = -1;
            var nd = 1e9;
            for (var i = 0; i < sb.length; i++) {
              final q = run.frames.first.toScreen(sb.x[i], sb.y[i]);
              final d = (q - px).distance;
              if (d < nd) {
                nd = d;
                near = i;
              }
            }
            // ignore: avoid_print
            print(
              'prefix same $same; changed pixel nearest sample $near at ${nd.toStringAsFixed(2)} px, r=${sb.r[near] * run.frames.first.viewScale}',
            );
            // ignore: avoid_print
            print(
              'scale ${run.frames.first.viewScale} n ${sa.length}->${sb.length} start ${sa.startSample}->${sb.startSample} '
              'final ${sa.finalCount}->${sb.finalCount} corners ${sa.corners} -> ${sb.corners} ',
            );
            for (var i = 0; i < math.min(sa.length, sb.length); i++) {
              final d = math.sqrt(math.pow(sa.x[i] - sb.x[i], 2) + math.pow(sa.y[i] - sb.y[i], 2));
              final dr = sa.r[i] - sb.r[i];
              if (d > 0.01 || dr.abs() > 0.01) {
                // ignore: avoid_print
                print('  i=$i d=${d.toStringAsFixed(3)} dr=${dr.toStringAsFixed(3)}');
              }
            }
            // ignore: avoid_print
            print(
              'frame ${run.frames[i].index} pts ${prevPts.length}->${pts.length} '
              'moves ${prevSink.moves}->${sink.moves} verbs ${prevSink.verbs}->${sink.verbs} '
              'changed ${out.map((p) => '(${(p / dpr).dx.toStringAsFixed(1)},${(p / dpr).dy.toStringAsFixed(1)}) d=${((p - tip).distance / dpr).toStringAsFixed(1)} '
                  'cov ${prev!.at(p.dx.floor(), p.dy.floor()).toStringAsFixed(2)}->${cov.at(p.dx.floor(), p.dy.floor()).toStringAsFixed(2)}').join(' ')} '
              'tip ${(tip / dpr)}',
            );
          }
        }
        prev = cov;
        prevSink = sink;
      }
    }
  });
}
