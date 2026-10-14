import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset, Size;

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:len/features/documents/scan/quad_detector.dart';
import 'package:len/features/documents/scan/scan_enhance.dart';
import 'package:len/features/documents/scan/scan_job.dart';
import 'package:len/features/documents/scan/scan_warp.dart';

/// Whether [p] lies inside the convex [quad] (clockwise on screen).
bool _inside(Quad quad, double x, double y) {
  final c = quad.corners;
  for (var i = 0; i < 4; i++) {
    final a = c[i], b = c[(i + 1) % 4];
    if ((b.dx - a.dx) * (y - a.dy) - (b.dy - a.dy) * (x - a.dx) < 0) return false;
  }
  return true;
}

/// A grey photo as RGBA: [paper] inside [quads], [background] elsewhere,
/// plus deterministic noise.
Uint8List _photo(
  int w,
  int h,
  List<Quad> quads, {
  required int Function(int x, int y) background,
  int paper = 230,
  int noise = 12,
  int seed = 1,
}) {
  final rnd = math.Random(seed);
  final out = Uint8List(w * h * 4);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final inPaper = quads.any((q) => _inside(q, x + 0.5, y + 0.5));
      final base = inPaper ? paper - x * 20 ~/ w : background(x, y);
      final v = (base + rnd.nextInt(2 * noise + 1) - noise).clamp(0, 255);
      final o = (y * w + x) * 4;
      out[o] = v;
      out[o + 1] = v;
      out[o + 2] = v;
      out[o + 3] = 255;
    }
  }
  return out;
}

Quad? _detect(Uint8List rgba, int w, int h) {
  final g = QuadDetector.luminance(rgba, w, h);
  return QuadDetector.locate(g.grey, g.width, g.height)?.scaled(g.scale);
}

void _expectNear(Quad? found, Quad truth, double tolerance) {
  expect(found, isNotNull);
  for (var i = 0; i < 4; i++) {
    final d = (found!.corners[i] - truth.corners[i]).distance;
    expect(d, lessThan(tolerance), reason: 'corner $i: $found vs $truth');
  }
}

void main() {
  group('geometry', () {
    final quads = [
      Quad.bounds(300, 400),
      const Quad(Offset(10, 20), Offset(290, 5), Offset(280, 390), Offset(30, 370)),
      const Quad(Offset(120, 40), Offset(180, 40), Offset(290, 390), Offset(5, 395)),
      const Quad(Offset(0, 0), Offset(500, 100), Offset(520, 140), Offset(-20, 900)),
    ];

    test('page corners land exactly on the quad and the inverse round-trips', () {
      for (final q in quads) {
        const page = Size(210, 297);
        final h = Homography.pageToQuad(page, q);
        final pageCorners = [
          Offset.zero,
          const Offset(210, 0),
          const Offset(210, 297),
          const Offset(0, 297),
        ];
        for (var i = 0; i < 4; i++) {
          expect((h.map(pageCorners[i]) - q.corners[i]).distance, lessThan(1e-6));
        }
        final inv = h.inverse();
        for (final p in [const Offset(30, 40), const Offset(105, 150), const Offset(200, 10)]) {
          expect((inv.map(h.map(p)) - p).distance, lessThan(1e-6));
        }
      }
    });

    test('ordered sorts shuffled points, convexity, output size', () {
      final q = quads[1];
      final shuffled = [q.bottomRight, q.topLeft, q.bottomLeft, q.topRight];
      expect(Quad.ordered(shuffled), q);
      expect(q.isConvex, isTrue);
      expect(
        Quad.fromCorners([q.topLeft, q.bottomRight, q.topRight, q.bottomLeft]).isConvex,
        false,
      );
      expect(q.withCorner(2, const Offset(100, 100)).isConvex, isFalse);
      expect(Quad.bounds(300, 400).area, 120000);
      expect(Quad.bounds(4000, 3000).outputSize(maxEdge: 2500), const Size(2500, 1875));
      expect(Quad.bounds(300, 400).outputSize(maxEdge: 2500), const Size(300, 400));
      expect(Quad.bounds(300, 400).scaled(2), Quad.bounds(600, 800));
      expect(q.rotated(1).corners, [q.bottomLeft, q.topLeft, q.topRight, q.bottomRight]);
      expect(q.rotated(4), q);
      expect(q.rotated(-1), q.rotated(3));
      expect(q.rotated(1).isConvex, isTrue);
      expect(Quad.bounds(300, 400).rotated(1).outputSize(maxEdge: 2500), const Size(400, 300));
      expect(
        Quad.bounds(300, 400).inset(10),
        const Quad(Offset(10, 10), Offset(290, 10), Offset(290, 390), Offset(10, 390)),
      );
      final skew = q.inset(3);
      for (var i = 0; i < 4; i++) {
        // Each corner moves inside, along its angle's bisector.
        expect(_inside(q, skew.corners[i].dx, skew.corners[i].dy), isTrue);
      }
      expect(q.inset(0), q);
    });
  });

  test('warp flattens coloured quadrants inside a perspective quad', () {
    const w = 300, h = 400;
    const quad = Quad(Offset(60, 50), Offset(250, 80), Offset(280, 380), Offset(20, 330));
    const page = Size(200, 260);
    final toPage = Homography.pageToQuad(page, quad).inverse();
    const colours = [
      [220, 40, 40],
      [40, 200, 40],
      [40, 40, 220],
      [230, 220, 40],
    ];
    final src = RgbaImage.blank(w, h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final o = (y * w + x) * 4;
        var c = const [15, 15, 15];
        if (_inside(quad, x + 0.5, y + 0.5)) {
          final p = toPage.map(Offset(x + 0.5, y + 0.5));
          final right = p.dx > page.width / 2, bottom = p.dy > page.height / 2;
          c = colours[bottom ? (right ? 2 : 3) : (right ? 1 : 0)];
        }
        src.pixels.setAll(o, [...c, 255]);
      }
    }
    final dst = RgbaImage.blank(200, 260);
    warpRows(src, Homography.pageToQuad(page, quad), dst, 0, 260);
    void expectColour(int x, int y, List<int> c, int tolerance) {
      final o = (y * 200 + x) * 4;
      for (var i = 0; i < 3; i++) {
        expect((dst.pixels[o + i] - c[i]).abs(), lessThanOrEqualTo(tolerance), reason: '$x,$y');
      }
      expect(dst.pixels[o + 3], 255);
    }

    expectColour(50, 65, colours[0], 0);
    expectColour(150, 65, colours[1], 0);
    expectColour(150, 195, colours[2], 0);
    expectColour(50, 195, colours[3], 0);
    expectColour(1, 1, colours[0], 60);
    expectColour(198, 1, colours[1], 60);
    expectColour(198, 258, colours[2], 60);
    expectColour(1, 258, colours[3], 60);
  });

  group('detector', () {
    const w = 800, h = 600;
    int gradient(int x, int y) => 50 + x * 25 ~/ w;

    test('finds a rotated paper in perspective on a dark table', () {
      const truth = Quad(Offset(180, 90), Offset(610, 60), Offset(660, 520), Offset(140, 540));
      _expectNear(_detect(_photo(w, h, [truth], background: gradient), w, h), truth, 4);
    });

    test('finds paper on a textured table', () {
      final rnd = math.Random(7);
      final blocks = List.generate(40 * 30, (_) => 20 + rnd.nextInt(100));
      int texture(int x, int y) => blocks[(y ~/ 20) * 40 + x ~/ 20];
      const truth = Quad(Offset(220, 120), Offset(560, 100), Offset(600, 500), Offset(200, 480));
      _expectNear(_detect(_photo(w, h, [truth], background: texture), w, h), truth, 4);
    });

    test('finds paper covering most of the image', () {
      const truth = Quad(Offset(30, 25), Offset(770, 15), Offset(780, 580), Offset(25, 570));
      _expectNear(_detect(_photo(w, h, [truth], background: gradient), w, h), truth, 4);
    });

    test('prefers the bigger of two bright rectangles', () {
      const big = Quad(Offset(300, 80), Offset(740, 110), Offset(720, 540), Offset(290, 520));
      const small = Quad(Offset(40, 300), Offset(220, 300), Offset(220, 500), Offset(40, 500));
      _expectNear(_detect(_photo(w, h, [big, small], background: gradient), w, h), big, 4);
    });

    test('finds nothing without a document', () {
      expect(_detect(_photo(w, h, [], background: (x, y) => 120, noise: 60), w, h), isNull);
      int smooth(int x, int y) => 40 + (x + y) * 180 ~/ (w + h);
      expect(_detect(_photo(w, h, [], background: smooth), w, h), isNull);
      expect(_detect(_photo(w, h, [], background: (x, y) => 128), w, h), isNull);
    });
  });

  group('enhance', () {
    const w = 300, h = 400;
    bool ink(int x, int y) => y % 40 >= 19 && y % 40 <= 21 && x > 20 && x < 280;
    bool paper(int x, int y) => y % 40 < 17 || y % 40 > 23;

    /// Shaded, slightly yellow paper with dark lines; [colour] ink
    /// (red) on every other line.
    RgbaImage page() {
      final page = RgbaImage.blank(w, h);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final v = 200 - 60 * x ~/ (w - 1);
          final c = !ink(x, y)
              ? [v + 6, v + 3, v - 12]
              : (y ~/ 40).isEven
              ? [40, 43, 37]
              : [v, 40, 40];
          page.pixels.setAll((y * w + x) * 4, [...c, 255]);
        }
      }
      return page;
    }

    void check(ScanFilter filter, void Function(int x, int y, List<int> rgb) expectPixel) {
      final p = page();
      enhanceRows(p, EnhanceMap.of(p), 0, h, filter: filter);
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final o = (y * w + x) * 4;
          expectPixel(x, y, p.pixels.sublist(o, o + 3));
        }
      }
    }

    test('greyscale whitens shaded paper and darkens ink', () {
      check(ScanFilter.greyscale, (x, y, c) {
        expect(c[1], c[0]);
        expect(c[2], c[0]);
        if (ink(x, y)) expect(c[0], lessThanOrEqualTo(110), reason: 'ink $x,$y');
        if (paper(x, y)) expect(c[0], greaterThanOrEqualTo(235), reason: '$x,$y');
      });
    });

    test('colour whitens tinted paper and keeps coloured ink', () {
      check(ScanFilter.colour, (x, y, c) {
        if (paper(x, y)) {
          for (final v in c) {
            expect(v, greaterThanOrEqualTo(235), reason: 'paper $x,$y: $c');
          }
        }
        if (ink(x, y) && (y ~/ 40).isOdd) {
          expect(c[0] - c[1], greaterThan(100), reason: 'red ink $x,$y: $c');
        }
        if (ink(x, y) && (y ~/ 40).isEven) expect(c[0], lessThan(100), reason: '$x,$y: $c');
      });
    });

    test('black and white leaves only black ink on white paper', () {
      check(ScanFilter.blackWhite, (x, y, c) {
        expect(c[1], c[0]);
        if (paper(x, y)) expect(c[0], 255, reason: '$x,$y');
        if (ink(x, y) && (y ~/ 40).isEven) expect(c[0], 0, reason: '$x,$y');
      });
    });
  });

  group('job', () {
    final rgba = _photo(300, 400, [], background: (x, y) => (x * 7 + y * 3) % 256, noise: 5);
    const quad = Quad(Offset(20, 30), Offset(280, 10), Offset(290, 390), Offset(10, 370));

    test('run returns a decodable JPEG of the page size', () {
      final job = ScanJob(source: RgbaImage(rgba, 300, 400), quad: quad, filter: ScanFilter.colour);
      final out = job.run();
      final size = quad.outputSize(maxEdge: 2500);
      expect((out.width, out.height), (size.width.toInt(), size.height.toInt()));
      final decoded = img.decodeJpg(out.jpeg)!;
      expect((decoded.width, decoded.height), (out.width, out.height));
    });

    test('sliced rendering matches render', () async {
      for (final filter in [null, ...ScanFilter.values]) {
        final job = ScanJob(source: RgbaImage(rgba, 300, 400), quad: quad, filter: filter);
        final whole = job.render();
        var yields = 0;
        final sliced = await job.renderSliced(() async => yields++, rowsPerSlice: 7);
        expect(yields, greaterThan(10));
        expect(sliced.pixels, whole.pixels);
      }
    });
  });
}
