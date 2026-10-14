import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/features/documents/scan/quad_detector.dart';
import 'package:len/features/documents/scan/scan_job.dart';

/// Whether (x, y) lies inside the convex [quad] (clockwise on screen).
bool _inside(Quad quad, double x, double y) {
  final c = quad.corners;
  for (var i = 0; i < 4; i++) {
    final a = c[i], b = c[(i + 1) % 4];
    if ((b.dx - a.dx) * (y - a.dy) - (b.dy - a.dy) * (x - a.dx) < 0) return false;
  }
  return true;
}

/// A grey photo (RGBA) of [paper] inside [quad] on [background], edges
/// anti-aliased (4 × 4 coverage), softened like a lens (3 × 3 box) and
/// with deterministic noise.
RgbaImage _photo(
  int w,
  int h,
  Quad quad, {
  required int Function(int x, int y) background,
  int Function(int x, int y)? paper,
  int noise = 8,
}) {
  final paperAt = paper ?? (x, y) => 225 - x * 20 ~/ w;
  final grey = Float64List(w * h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final corners = [
        _inside(quad, x + 0.0, y + 0.0),
        _inside(quad, x + 1.0, y + 0.0),
        _inside(quad, x + 0.0, y + 1.0),
        _inside(quad, x + 1.0, y + 1.0),
      ];
      double cover;
      if (corners.every((c) => c)) {
        cover = 1;
      } else if (corners.every((c) => !c)) {
        cover = 0;
      } else {
        var n = 0;
        for (var j = 0; j < 4; j++) {
          for (var i = 0; i < 4; i++) {
            if (_inside(quad, x + (i + 0.5) / 4, y + (j + 0.5) / 4)) n++;
          }
        }
        cover = n / 16;
      }
      grey[y * w + x] = cover * paperAt(x, y) + (1 - cover) * background(x, y);
    }
  }
  final rnd = math.Random(3);
  final out = RgbaImage.blank(w, h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      var s = 0.0;
      for (var j = -1; j <= 1; j++) {
        for (var i = -1; i <= 1; i++) {
          s += grey[(y + j).clamp(0, h - 1) * w + (x + i).clamp(0, w - 1)];
        }
      }
      final v = (s / 9 + rnd.nextInt(2 * noise + 1) - noise).round().clamp(0, 255);
      out.pixels.setAll((y * w + x) * 4, [v, v, v, 255]);
    }
  }
  return out;
}

/// The largest corner error of [found] against [truth], in pixels.
double _error(Quad? found, Quad truth) {
  expect(found, isNotNull);
  var worst = 0.0;
  for (var i = 0; i < 4; i++) {
    worst = math.max(worst, (found!.corners[i] - truth.corners[i]).distance);
  }
  return worst;
}

/// [quad] turned by [degrees] about its centre.
Quad _turned(Quad quad, double degrees) {
  final c = quad.corners.fold(Offset.zero, (s, p) => s + p) / 4;
  final a = degrees * math.pi / 180, cos = math.cos(a), sin = math.sin(a);
  Offset turn(Offset p) {
    final d = p - c;
    return c + Offset(d.dx * cos - d.dy * sin, d.dx * sin + d.dy * cos);
  }

  return Quad.fromCorners(quad.corners.map(turn).toList());
}

void main() {
  const w = 800, h = 600;
  int desk(int x, int y) => 55 + x * 25 ~/ w;

  /// Detects on [photo] and expects every corner within [bound] pixels of
  /// [truth] moved inside by the detector's [QuadDetector.inset].
  void expectPrecise(RgbaImage photo, Quad truth, {double bound = 0.5}) {
    final found = QuadDetector.find(photo);
    final expected = truth.inset(QuadDetector.inset);
    expect(_error(found, expected), lessThan(bound), reason: '$found vs $expected');
  }

  test('a rotated page: corners to half a pixel', () {
    final truth = _turned(
      const Quad(Offset(200, 110), Offset(600, 110), Offset(600, 490), Offset(200, 490)),
      9,
    );
    expectPrecise(_photo(w, h, truth, background: desk), truth);
  });

  test('a page in strong perspective: corners to half a pixel', () {
    const truth = Quad(Offset(250, 70), Offset(560, 90), Offset(720, 540), Offset(90, 520));
    expectPrecise(_photo(w, h, truth, background: desk), truth);
  });

  test('a low-contrast page (grey paper on a light desk): corners to half a pixel', () {
    const truth = Quad(Offset(150, 95), Offset(640, 70), Offset(670, 530), Offset(120, 510));
    expectPrecise(
      _photo(w, h, truth, background: (x, y) => 120, paper: (x, y) => 165, noise: 6),
      truth,
    );
  });

  test('ink near the edges and a textured desk do not pull the sides', () {
    final rnd = math.Random(11);
    final blocks = List.generate(40 * 30, (_) => 25 + rnd.nextInt(70));
    int texture(int x, int y) => blocks[(y ~/ 20) * 40 + x ~/ 20];
    const truth = Quad(Offset(180, 100), Offset(610, 80), Offset(640, 500), Offset(170, 520));
    // Lines of "text" from just inside the left edge (and a margin above and below).
    int written(int x, int y) => y % 24 < 3 && y > 120 && y < 490 && x > 182 && x < 560 ? 40 : 220;
    expectPrecise(_photo(w, h, truth, background: texture, paper: written), truth);
  });

  test('a page filling most of the photo: corners to half a pixel', () {
    const truth = Quad(Offset(28, 22), Offset(772, 12), Offset(784, 582), Offset(18, 574));
    expectPrecise(_photo(w, h, truth, background: desk), truth);
  });

  test('corners come out in photo pixels for larger photos', () {
    // 1600 px: refined at full size (QuadDetector.refineEdge), detected at a quarter.
    final truth = _turned(
      const Quad(Offset(400, 220), Offset(1200, 220), Offset(1200, 980), Offset(400, 980)),
      -6,
    );
    expectPrecise(_photo(1600, 1200, truth, background: desk), truth, bound: 1);
  });
}
