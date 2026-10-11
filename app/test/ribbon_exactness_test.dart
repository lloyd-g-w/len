import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/render/capsule_emitter.dart';
import 'package:len/ink/render/ribbon_emitter.dart';
import 'package:len/ink/render/stroke_outline.dart';
import 'package:len/ink/render/stroke_shaper.dart';

import 'inklab/metrics/outline_geometry.dart';
import 'inklab/metrics/raster.dart';

/// Wiggly test strokes: loops, hairpins and spirals of every tightness.
List<List<StrokePoint>> strokes(int seed) {
  final rng = math.Random(seed);
  final out = <List<StrokePoint>>[];
  for (var k = 0; k < 12; k++) {
    final a1 = 2 + rng.nextDouble() * 10, a2 = rng.nextDouble() * 6;
    final f1 = 0.2 + rng.nextDouble() * 0.8, f2 = 0.5 + rng.nextDouble() * 2;
    final drift = 0.5 + rng.nextDouble() * 3;
    out.add([
      for (var i = 0; i < 300; i++)
        StrokePoint(
          i * 0.08 * drift + a1 * math.sin(i * 0.08 * f1) + a2 * math.sin(i * 0.08 * f2 + 1),
          a1 * math.cos(i * 0.08 * f1 * 1.3) + a2 * math.cos(i * 0.08 * f2),
          0.3 + 0.4 * (0.5 + 0.5 * math.sin(i * 0.05 + k)),
        ),
    ]);
  }
  // Bends of every radius: arcs of radius rho (0.2..3 × the radius of
  // the widest pen) turning by 60..300°, with straight legs.
  for (final rho in [0.3, 0.6, 1.0, 1.5, 2.5, 4, 6, 10]) {
    for (final turn in [1.2, 1.9, 2.6, 3.14, 4.5]) {
      final pts = <StrokePoint>[];
      for (var i = 0; i < 40; i++) {
        pts.add(StrokePoint(-12 + i * 0.3, 0, 0.5));
      }
      for (var a = 0.0; a <= turn; a += 0.25 / rho) {
        pts.add(StrokePoint(rho * math.sin(a), rho - rho * math.cos(a), 0.5 + 0.2 * a / turn));
      }
      final ex = rho * math.sin(turn), ey = rho - rho * math.cos(turn);
      for (var i = 1; i < 40; i++) {
        pts.add(StrokePoint(ex + i * 0.3 * math.cos(turn), ey + i * 0.3 * math.sin(turn), 0.7));
      }
      out.add(pts);
    }
  }
  return out;
}

int holes(List<StrokePoint> points, OutlineSpec spec, {required double zoom}) {
  final s = StrokeShaper(StrokeOutline.paramsOf(points, spec));
  StrokeOutline.feed(s, points, spec, null);
  s.update(ended: true);
  Offset map(Offset o) => o * zoom;
  final ribbon = PolygonSink(map: map, tolerance: 0.05);
  RibbonEmitter(s, flatCaps: false, width: spec.width, step: s.p.step).emit(ribbon);
  final exact = PolygonSink(map: map, tolerance: 0.05);
  for (var i = 0; i + 1 < s.length; i++) {
    emitCapsule(exact, s.x[i], s.y[i], s.r[i], s.x[i + 1], s.y[i + 1], s.r[i + 1]);
  }
  final bounds = boundsOf(exact.contours).expandToInclude(boundsOf(ribbon.contours));
  final a = rasterize(ribbon.contours, bounds), b = rasterize(exact.contours, bounds);
  var bad = 0;
  for (var y = a.top; y < a.top + a.height; y++) {
    for (var x = a.left; x < a.left + a.width; x++) {
      if ((a.at(x, y) - b.at(x, y)).abs() > 0.5) bad++;
    }
  }
  return bad;
}

void main() {
  test('the ribbon outline covers exactly the union of the circles', () {
    for (final width in [1.5, 2.5, 4.0, 8.0, 16.0]) {
      for (final st in [0.0, 0.4, 1.0]) {
        final spec = OutlineSpec(width: width, thinning: 0.6, streamline: st);
        var worst = 0;
        for (final p in strokes(width.toInt())) {
          worst = math.max(worst, holes(p, spec, zoom: 8));
        }
        // ignore: avoid_print
        print('width $width st $st: worst $worst px');
        expect(worst, lessThanOrEqualTo(2));
      }
    }
  });
}
