// How the pen answers to pressure on real S Pen handwriting
// (`recordings/real_spen_01.leninput`, ≈ 1 min of writing): the ink should
// be about as wide as the pen's width (what its toolbar slot shows), and
// follow the hand within a stroke. See INK_LAB.md, F11.
@Tags(['inklab'])
library;

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/ink/input/pressure_filter.dart';
import 'package:len/ink/lab/recording_codec.dart';
import 'package:len/ink/lab/replay_run.dart';
import 'package:len/ink/render/stroke_outline.dart';
import 'package:len/ink/render/stroke_renderer.dart';

/// Quantile [q] of sorted [v].
double _q(List<double> v, double q) => v[((v.length - 1) * q).round()];

void main() {
  test('the pressure curve: 0 → 0, medium → 0.5, 1 → 1, rising and concave', () {
    expect(PressureCurve.apply(0), 0);
    expect(PressureCurve.apply(PressureCurve.medium), closeTo(0.5, 1e-12));
    expect(PressureCurve.apply(1), 1);
    var last = 0.0, lastSlope = double.infinity;
    for (var i = 1; i <= 100; i++) {
      final p = PressureCurve.apply(i / 100);
      final slope = (p - last) * 100;
      expect(p, greaterThan(last));
      expect(p, greaterThanOrEqualTo(i / 100));
      expect(slope, lessThan(lastSlope));
      last = p;
      lastSlope = slope;
    }
  });

  test('real handwriting: the ink is the pen\'s width and follows the hand', () {
    final file = File('test/inklab/recordings/real_spen_01.leninput');
    final replay = ReplayResult.run(RecordingCodec.decode(file.readAsBytesSync()));
    // Diameter ÷ the pen's width along the body of every stroke (10 samples
    // in from each end), and per stroke how much it varies (p90 ÷ p10).
    final widths = <double>[];
    final spreads = <double>[];
    for (final s in replay.strokes) {
      final spec = StrokeRenderer.specFor(s.width, s.style);
      final line = StrokeOutline.centerline(s.points, spec);
      if (line == null || line.length < 40) continue;
      final body = [for (var i = 10; i < line.length - 10; i++) 2 * line.r[i] / s.width]..sort();
      widths.addAll(body);
      spreads.add(_q(body, 0.9) / _q(body, 0.1));
    }
    widths.sort();
    spreads.sort();
    final width = _q(widths, 0.5), spread = _q(spreads, 0.5);
    // ignore: avoid_print
    print('median width ${width.toStringAsFixed(3)} × the pen\'s, median spread $spread');
    // Before the curve: 0.82 × and 5 % (a light hand drew thin, nearly
    // monoline ink); now 0.95 × and 9 %.
    expect(width, inInclusiveRange(0.9, 1.1));
    expect(spread, greaterThan(1.07));
  });
}
