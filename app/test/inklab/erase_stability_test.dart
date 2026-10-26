// The pixel eraser leaves the rest of a stroke where it was (INK_LAB.md,
// F12). Every stroke of every committed recording (≥ 30 points) gets a
// 4 px eraser dab at a quarter, half and three quarters of its points as
// recorded, and at 40 % with the stabiliser at 0.4 and 1 (`StrokeSplitter`,
// as the pixel eraser cuts). The original and its fragments are rasterised at
// the device's pixel ratio; pixels whose coverage changes by more than
// [_maxChange] farther from the dab than the shaper's [_reach] count as
// the ink moving, and none may.
@Tags(['inklab'])
library;

import 'dart:io';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/geometry/stroke_splitter.dart';
import 'package:len/ink/lab/recording_codec.dart';
import 'package:len/ink/lab/replay_run.dart';
import 'package:len/ink/render/ribbon_emitter.dart';
import 'package:len/ink/render/stroke_outline.dart';
import 'package:len/ink/render/stroke_renderer.dart';

import 'metrics/outline_geometry.dart';
import 'metrics/raster.dart';
import 'suite.dart';

/// Eraser radius (screen px).
const double _eraser = 4;

/// Sub-scanlines per pixel row of the rasters.
const int _subRows = 32;

/// A coverage change that counts as the ink moving at [pxPerUnit] physical
/// px per world unit: more than one sub-scanline, an edge shifting by
/// 1/50 px and twice the outline's curve fitting tolerance (a fragment's
/// cubics start at other samples than the original's, each within the
/// tolerance of the same offset points; zoomed in 7×, as `real_spen_01`
/// was written, that is 0.06 px).
double _maxChange(Stroke s, double pxPerUnit) =>
    1 / _subRows + 0.02 + 2 * RibbonEmitter.toleranceFor(s.width) * pxPerUnit;

/// How far from the dab (screen px) the cut may change the ink: the eraser,
/// the ink's width beyond it, the reach of the shaper's position smoothing
/// and corners, the length of its radius smoothing (causal, so the width
/// settles from the cut on; ≈ 0.5 widths at stabiliser 0, 6.5 at 1), and
/// 3 px for the input points that shape the first spline segments.
double _reach(Stroke s, double viewScale) {
  final spec = StrokeRenderer.specFor(s.width, s.style);
  final p = StrokeOutline.paramsOf(s.points, spec);
  final shaper = (p.kernelK + p.fit + 2 * p.cornerK) * p.step + spec.radiusSigma;
  return _eraser + (1.5 * s.width + shaper) * viewScale + 3;
}

class _Moved {
  int strokes = 0, cuts = 0, moved = 0, pixels = 0;
  double change = 0, farthest = 0;
}

void main() {
  test('the pixel eraser leaves the rest of a stroke where it was', () {
    final files = [
      for (final f in Directory(recordingsDir).listSync())
        if (f is File && f.path.endsWith('.leninput')) f,
    ]..sort((a, b) => a.path.compareTo(b.path));
    final failures = <String>[];
    for (final file in files) {
      final recording = RecordingCodec.decode(file.readAsBytesSync());
      final dpr = recording.meta.devicePixelRatio;
      final replay = ReplayResult.run(recording);
      // A stored stabiliser (the shaper's: the laser's, older strokes) is
      // on raw samples, never on the pen's string-stabilised points.
      final raw = ReplayResult.run(recording, pen: recording.meta.pen.copyWith(streamline: 0));
      for (final streamline in [null, 0.4, 1.0]) {
        final m = _Moved();
        var ids = 0;
        final run = streamline == null ? replay : raw;
        for (final recorded in run.strokes) {
          if (recorded.points.length < 30) continue;
          final s = streamline == null
              ? recorded
              : recorded.withPoints(
                  recorded.points,
                  style: recorded.style.copyWith(streamline: streamline),
                );
          final frame = run.frameOf(s);
          Offset map(Offset o) => frame.toScreen(o.dx, o.dy) * dpr;
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
          final a = rasterize(before, bounds, subRows: _subRows);
          final reach = _reach(s, frame.viewScale) * dpr;
          final maxChange = _maxChange(s, frame.viewScale * dpr);
          m.strokes++;
          for (final at in streamline == null ? const [0.25, 0.5, 0.75] : const [0.4]) {
            final dab = s.points[(s.points.length * at).floor()].offset;
            final fragments = StrokeSplitter.erase(
              s,
              dab,
              dab,
              _eraser / frame.viewScale,
              newId: () => 'f${ids++}',
            );
            if (fragments == null) continue;
            m.cuts++;
            final b = rasterize(outline(fragments), bounds, subRows: _subRows);
            final centre = map(dab);
            var pixels = 0;
            for (var y = a.top; y < a.top + a.height; y++) {
              for (var x = a.left; x < a.left + a.width; x++) {
                final change = (a.at(x, y) - b.at(x, y)).abs();
                if (change <= maxChange) continue;
                final d = (Offset(x + 0.5, y + 0.5) - centre).distance;
                if (d < reach) continue;
                pixels++;
                m.change = math.max(m.change, change);
                m.farthest = math.max(m.farthest, d / dpr);
              }
            }
            if (pixels > 0) m.moved++;
            m.pixels = math.max(m.pixels, pixels);
          }
        }
        final name = '${file.uri.pathSegments.last} @${streamline ?? 'recorded'}';
        final line =
            '${name.padRight(34)} ${m.moved} of ${m.cuts} cuts (${m.strokes} strokes) move; '
            'worst ${m.pixels} px², ${(m.change * 100).round()} %, up to '
            '${m.farthest.toStringAsFixed(0)} px from the cut';
        // ignore: avoid_print
        print(line);
        if (m.moved > 0) failures.add(line);
      }
    }
    expect(failures, isEmpty);
  }, timeout: const Timeout(Duration(minutes: 5)));
}
