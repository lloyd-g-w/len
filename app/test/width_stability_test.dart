import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/input/pressure_filter.dart';
import 'package:len/ink/render/stroke_outline.dart';

/// A pen with high pressure sensitivity (where flicker is most visible).
const spec = OutlineSpec(width: 3, thinning: 0.8, streamline: 0.4);

/// Outline thickness at x (vertical extent of the filled path around
/// y = 50), found precisely by bisection.
double thicknessAt(Path path, double x) {
  double edge(double outside) {
    var inside = 50.0;
    for (var i = 0; i < 40; i++) {
      final mid = (inside + outside) / 2;
      if (path.contains(Offset(x, mid))) {
        inside = mid;
      } else {
        outside = mid;
      }
    }
    return inside;
  }

  return edge(70) - edge(30);
}

/// A straight line written with noisy digitiser pressure, filtered as the
/// input controller does.
List<StrokePoint> noisyLine({int seed = 3, double length = 200}) {
  final rnd = math.Random(seed);
  final filter = PressureFilter();
  return [
    for (var x = 0.0; x <= length; x += 2)
      StrokePoint(x, 50, filter.next((0.5 + (rnd.nextDouble() - 0.5) * 0.5).clamp(0.0, 1.0))),
  ];
}

void main() {
  test('noisy pressure does not make the width flicker along a stroke', () {
    final path = StrokeOutline.build(noisyLine(), spec);
    // Flicker is width changing over short distances; slow swells that
    // follow the hand's pressure are fine.
    final widths = [for (var x = 20.0; x <= 180; x += 3) thicknessAt(path, x)];
    var worst = 0.0;
    for (var i = 1; i < widths.length; i++) {
      worst = math.max(worst, (widths[i] - widths[i - 1]).abs() / widths[i]);
    }
    // Extreme noise (±0.25 pressure at 0.8 sensitivity): smoothing is causal
    // (drawn ink must never change, see below), which leaves a little more
    // residual than a symmetric filter would.
    expect(worst, lessThan(0.05), reason: 'width changes < 5% per 3 units of length');
  });

  test('the width behind the pen tip does not change as the stroke grows', () {
    final points = noisyLine(length: 300);
    // Width at x = 100 while the pen is at x = 106, 112, 120, 160.
    final widths = [
      for (final end in [53, 56, 60, 80])
        thicknessAt(StrokeOutline.build(points.sublist(0, end + 1), spec, complete: false), 100),
    ];
    final spread = widths.reduce(math.max) - widths.reduce(math.min);
    expect(spread, lessThan(0.08), reason: 'live stroke width must not pulse ($widths)');
  });
}
