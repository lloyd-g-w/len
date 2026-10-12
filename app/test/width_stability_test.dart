import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/input/pressure_filter.dart';
import 'package:len/ink/render/stroke_outline.dart';

/// A pen with high pressure sensitivity (where flicker is most visible).
const spec = OutlineSpec(width: 3, thinning: 0.8, streamline: 0.4);

/// The same pen with the stabiliser at maximum (heavy noise is its job).
const stabilised = OutlineSpec(width: 3, thinning: 0.8, streamline: 1);

/// The same pen with no stabiliser: raw pressure response.
const raw = OutlineSpec(width: 3, thinning: 0.8, streamline: 0);

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
  test('with the stabiliser up, noisy pressure does not make the width flicker', () {
    final path = StrokeOutline.build(noisyLine(), stabilised);
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
    // Width at x = 80 while the pen is at x = 106, 112, 120, 160 (the
    // stabilised live line trails the pen by 10–20 px).
    final widths = [
      for (final end in [53, 56, 60, 80])
        thicknessAt(StrokeOutline.build(points.sublist(0, end + 1), spec, complete: false), 80),
    ];
    final spread = widths.reduce(math.max) - widths.reduce(math.min);
    expect(spread, lessThan(0.08), reason: 'live stroke width must not pulse ($widths)');
  });

  group('dense (240 Hz) stylus input', () {
    /// A line sampled four times as densely, as merged Android historical
    /// samples deliver it, with independent pressure noise per sample.
    List<StrokePoint> denseNoisyLine({int seed = 5, double length = 200}) {
      final rnd = math.Random(seed);
      final filter = PressureFilter();
      return [
        for (var x = 0.0; x <= length; x += 0.5)
          StrokePoint(x, 50, filter.next((0.5 + (rnd.nextDouble() - 0.5) * 0.5).clamp(0.0, 1.0))),
      ];
    }

    test('more samples do not make the width flicker', () {
      final path = StrokeOutline.build(denseNoisyLine(), spec);
      final widths = [for (var x = 20.0; x <= 180; x += 3) thicknessAt(path, x)];
      var worst = 0.0;
      for (var i = 1; i < widths.length; i++) {
        worst = math.max(worst, (widths[i] - widths[i - 1]).abs() / widths[i]);
      }
      expect(worst, lessThan(0.05));
    });

    test('the width behind the tip stays put while dense samples arrive', () {
      final points = denseNoisyLine(length: 300);
      final widths = [
        for (final end in [212, 224, 240, 320])
          thicknessAt(StrokeOutline.build(points.sublist(0, end + 1), spec, complete: false), 90),
      ];
      final spread = widths.reduce(math.max) - widths.reduce(math.min);
      expect(spread, lessThan(0.08), reason: '$widths');
    });

    test('a deliberate pressure change shows up within a short distance', () {
      // Pressure steps from 0.3 to 0.8 at x = 100.
      final filter = PressureFilter();
      final points = [
        for (var x = 0.0; x <= 200; x += 0.5) StrokePoint(x, 50, filter.next(x < 100 ? 0.3 : 0.8)),
      ];
      final path = StrokeOutline.build(points, spec);
      final thin = thicknessAt(path, 90), thick = thicknessAt(path, 180);
      // The radius smoothing is by length (5 widths), not by sample count,
      // so dense input changes width as promptly as sparse input.
      final at = thicknessAt(path, 100 + 10 * spec.width);
      expect((at - thin) / (thick - thin), greaterThan(0.85));
    });

    test('the outline follows the pen path (no over-smoothing)', () {
      // A wavy line (like small handwriting) sampled at 240 Hz.
      double wave(double x) => 50 + 4 * math.sin(x / 4);
      final points = [for (var x = 0.0; x <= 200; x += 0.5) StrokePoint(x, wave(x), 0.5)];
      // The pen as shipped (stabiliser off).
      final path = StrokeOutline.build(points, raw);
      var worst = 0.0;
      for (var x = 20.0; x <= 180; x += 7) {
        double edge(double outside) {
          var inside = wave(x);
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

        final centre = (edge(80) + edge(20)) / 2;
        worst = math.max(worst, (centre - wave(x)).abs());
      }
      expect(worst, lessThan(0.2), reason: 'centre line within 0.2 units of the pen');
    });
  });

  test('at stabiliser 0 a pressure change shows within about one width', () {
    final points = [for (var x = 0.0; x <= 120; x += 1) StrokePoint(x, 50, x < 60 ? 0.2 : 0.9)];
    final path = StrokeOutline.build(points, raw);
    final light = thicknessAt(path, 40), heavy = thicknessAt(path, 100);
    expect(heavy / light, greaterThan(2), reason: 'pressure clearly changes the width');
    // Most of the change has happened 1.5 widths after the step.
    final after = thicknessAt(path, 60 + 4.5);
    expect((after - light) / (heavy - light), greaterThan(0.6));
  });
}
