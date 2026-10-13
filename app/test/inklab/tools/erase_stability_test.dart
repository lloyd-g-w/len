// Does the rest of a stroke stay put when the pixel eraser cuts a hole in
// it? Opt-in (prints a table, asserts nothing; see INK_LAB.md, F12):
//
//   flutter test test/inklab/tools/erase_stability_test.dart \
//     --dart-define=INKLAB_TABLE=true [--dart-define=INKLAB_REAL=true]
//
// Every committed stroke of every recording (≥ 30 points) gets a 4 px
// eraser dab at its middle point (`StrokeSplitter`, as the pixel eraser
// cuts). The original and its fragments are rasterised at the device's
// pixel ratio; pixels farther from the dab than the eraser, 1.5 pen widths
// and 3 px whose coverage changes by > 20 % count as the ink moving.
@Tags(['inklab'])
library;

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/geometry/stroke_splitter.dart';
import 'package:len/ink/lab/recording_codec.dart';
import 'package:len/ink/lab/replay_run.dart';

import '../metrics/outline_geometry.dart';
import '../metrics/raster.dart';
import '../suite.dart';

const bool _enabled = bool.fromEnvironment('INKLAB_TABLE');

void main() {
  test(
    'erase stability',
    () {
      for (final file in recordingFiles()) {
        final recording = RecordingCodec.decode(file.readAsBytesSync());
        final dpr = recording.meta.devicePixelRatio;
        final replay = ReplayResult.run(recording);
        var ids = 0, strokes = 0, moved = 0, worstPixels = 0;
        var worstChange = 0.0, farthest = 0.0;
        for (final s in replay.strokes) {
          if (s.points.length < 30) continue;
          final frame = replay.frameOf(s);
          Offset map(Offset o) => frame.toScreen(o.dx, o.dy) * dpr;
          final mid = s.points[s.points.length ~/ 2].offset;
          const eraser = 4.0; // screen px
          final fragments = StrokeSplitter.erase(
            s,
            mid,
            mid,
            eraser / frame.viewScale,
            newId: () => 'f${ids++}',
          );
          if (fragments == null) continue;
          strokes++;
          List<Contour> outline(Iterable<Stroke> parts) => [
            for (final g in parts)
              ...outlineOf(
                g.points,
                tool: g.tool,
                width: g.width,
                style: g.style,
                complete: true,
                map: map,
              ).contours,
          ];
          final before = outline([s]);
          final bounds = boundsOf(before).inflate(4);
          final a = rasterize(before, bounds), b = rasterize(outline(fragments), bounds);
          final centre = map(mid);
          final keepOut = (eraser + 1.5 * s.width * frame.viewScale + 3) * dpr;
          var pixels = 0;
          for (var y = a.top; y < a.top + a.height; y++) {
            for (var x = a.left; x < a.left + a.width; x++) {
              final d = (Offset(x + 0.5, y + 0.5) - centre).distance;
              final change = (a.at(x, y) - b.at(x, y)).abs();
              if (d < keepOut || change <= 0.2) continue;
              pixels++;
              worstChange = math.max(worstChange, change);
              farthest = math.max(farthest, d / dpr);
            }
          }
          if (pixels > 0) moved++;
          worstPixels = math.max(worstPixels, pixels);
        }
        // ignore: avoid_print
        print(
          '${file.uri.pathSegments.last.padRight(26)} $moved of $strokes strokes move; worst '
          '$worstPixels px², ${(worstChange * 100).round()} %, up to '
          '${farthest.toStringAsFixed(0)} px from the cut',
        );
      }
    },
    skip: _enabled ? false : 'opt-in: --dart-define=INKLAB_TABLE=true',
    timeout: Timeout.none,
  );
}
