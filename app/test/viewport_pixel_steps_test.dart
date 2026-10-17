import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/ink/viewport.dart';

/// Whether [offset] lies whole device pixels ([dpr]) from [from].
bool wholePixels(Offset offset, Offset from, double dpr) {
  final d = (offset - from) * dpr;
  return (d.dx - d.dx.roundToDouble()).abs() < 1e-9 && (d.dy - d.dy.roundToDouble()).abs() < 1e-9;
}

void main() {
  test('without a pixel ratio the view moves freely', () {
    final v = ViewportController()..panBy(const Offset(0.3, 0.7));
    expect(v.offset, const Offset(0.3, 0.7));
  });

  test('with one, pans move in whole device pixels from where the zoom left it', () {
    final v = ViewportController()
      ..setSize(const Size(800, 600))
      ..devicePixelRatio = 2.625
      ..zoomAt(const Offset(101.3, 47.9), 1.37);
    final anchor = v.offset;
    for (final d in const [Offset(3.21, -0.7), Offset(0.05, 0.05), Offset(-11.9, 4.44)]) {
      v.panBy(d);
      expect(wholePixels(v.offset, anchor, 2.625), isTrue, reason: '${v.offset}');
    }
    // The steps are no drift: the view is within half a device pixel of
    // where the pans took it.
    final exact = anchor + const Offset(3.21 + 0.05 - 11.9, -0.7 + 0.05 + 4.44);
    expect((v.offset - exact).dx.abs(), lessThanOrEqualTo(0.5 / 2.625 + 1e-9));
    expect((v.offset - exact).dy.abs(), lessThanOrEqualTo(0.5 / 2.625 + 1e-9));
  });

  test('pans smaller than a device pixel add up', () {
    final v = ViewportController()..devicePixelRatio = 2;
    for (var i = 0; i < 10; i++) {
      v.panBy(const Offset(0.1, 0));
    }
    expect(v.offset.dx, closeTo(1, 1e-9));
  });

  test('glides (setView at the same zoom) step in whole device pixels too', () {
    final v = ViewportController()
      ..devicePixelRatio = 3
      ..setView(scale: 1.5, offset: const Offset(10.1, 20.2));
    final anchor = v.offset;
    expect(anchor, const Offset(10.1, 20.2), reason: 'a zoom moves as asked');
    v.setView(scale: 1.5, offset: const Offset(33.333, 44.444));
    expect(wholePixels(v.offset, anchor, 3), isTrue);
    expect((v.offset - const Offset(33.333, 44.444)).distance, lessThan(0.25));
  });

  test('bounded content stays in whole device pixels at its edges', () {
    final v = ViewportController(contentBounds: const Rect.fromLTWH(0, 0, 600, 2000))
      ..setSize(const Size(800, 600))
      ..devicePixelRatio = 2.625
      ..zoomAt(const Offset(400.3, 300.7), 1.21);
    final anchor = v.offset;
    v.panBy(const Offset(0, -100000)); // To the bottom edge.
    expect(wholePixels(v.offset, anchor, 2.625), isTrue);
    v.panBy(const Offset(0, 100000)); // To the top edge.
    expect(wholePixels(v.offset, anchor, 2.625), isTrue);
  });
}
