import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:len/ink/render/catmull_rom.dart';

void main() {
  test('passes through every input sample and fills gaps', () {
    final px = <double>[0, 10, 20, 30], py = <double>[0, 8, 0, 8], pr = <double>[1, 1, 2, 2];
    final d = CatmullRom.densify(px, py, pr, 1);
    for (var i = 0; i < px.length; i++) {
      final hit = List.generate(
        d.x.length,
        (k) => k,
      ).any((k) => d.x[k] == px[i] && d.y[k] == py[i]);
      expect(hit, isTrue, reason: 'sample $i kept');
    }
    for (var k = 1; k < d.x.length; k++) {
      final gap = math.sqrt(math.pow(d.x[k] - d.x[k - 1], 2) + math.pow(d.y[k] - d.y[k - 1], 2));
      expect(gap, lessThan(1.6));
    }
    expect(d.r.length, d.x.length);
  });

  test('sparse samples of a circle come back round', () {
    const n = 10, radius = 20.0;
    final px = [for (var i = 0; i <= n; i++) radius * math.cos(2 * math.pi * i / n)];
    final py = [for (var i = 0; i <= n; i++) radius * math.sin(2 * math.pi * i / n)];
    final d = CatmullRom.densify(px, py, List.filled(n + 1, 1.0), 0.5);
    for (var k = 0; k < d.x.length; k++) {
      // A chord between samples would sag up to r·(1−cos(π/n)) ≈ 0.98.
      expect(math.sqrt(d.x[k] * d.x[k] + d.y[k] * d.y[k]), closeTo(radius, 0.7));
    }
  });

  test('no overshoot on a sharp turn', () {
    final d = CatmullRom.densify(<double>[0, 20, 20.5, 40], <double>[0, 0, 20, 20], <double>[
      1,
      1,
      1,
      1,
    ], 0.5);
    expect(d.x.reduce(math.max), lessThanOrEqualTo(40));
    expect(d.y.reduce(math.min), greaterThan(-1.5));
  });

  test('dense input (already closer than the gap) passes through unchanged', () {
    // 240 Hz stylus samples: every point is kept and nothing is inserted,
    // so the spline only ever fills real gaps.
    final px = [for (var i = 0; i < 50; i++) i * 0.4];
    final py = [for (var i = 0; i < 50; i++) math.sin(i / 8) * 3];
    final pr = List.filled(50, 1.0);
    final d = CatmullRom.densify(px, py, pr, 1);
    expect(d.x, px);
    expect(d.y, py);
  });
}
