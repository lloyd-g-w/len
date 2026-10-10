import 'package:flutter_test/flutter_test.dart';
import 'package:len/ink/input/pressure_filter.dart';

void main() {
  test('smooths a single-sample spike', () {
    final f = PressureFilter();
    final out = [for (final p in [0.4, 0.4, 1.0, 0.4, 0.4]) f.next(p)];
    expect(out[2], lessThan(0.8));
    expect(out.last, closeTo(0.4, 0.15));
  });

  test('follows a sustained change', () {
    final f = PressureFilter();
    double last = 0;
    for (var i = 0; i < 12; i++) {
      last = f.next(i == 0 ? 0.2 : 0.9);
    }
    expect(last, closeTo(0.9, 0.01));
  });

  test('synthesized samples reuse the previous pressure', () {
    final f = PressureFilter()..next(0.3);
    expect(f.next(1.0, synthesized: true), 0.3);
  });

  test('settleEnd never lets the tail rise', () {
    expect(PressureFilter.settleEnd([0.5, 0.5, 0.9, 1.0]), [0.5, 0.5, 0.5, 0.5]);
    expect(PressureFilter.settleEnd([0.5, 0.6, 0.4, 0.2]), [0.5, 0.5, 0.4, 0.2]);
    expect(PressureFilter.settleEnd([0.7]), [0.7]);
  });
}
