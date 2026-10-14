import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' show Offset;

import 'quad_hull.dart';
import 'quad_raster.dart';
import 'quad_refine.dart';
import 'scan_geometry.dart';
import 'scan_image.dart';

/// A downsampled 8-bit luminance image; multiply its coordinates by
/// [scale] to get the full image's.
typedef ScanGrey = ({Uint8List grey, int width, int height, double scale});

/// Finds a document (a bright or dark quadrilateral with clear edges) in a
/// photo.
abstract final class QuadDetector {
  /// The long side detection works at; larger input is shrunk first.
  static const int workingEdge = 400;

  /// A region must cover this share of the image to count as a document.
  static const double minAreaShare = 0.15;

  /// Luminance of straight RGBA [rgba], shrunk by an integer factor (box
  /// average) so its long side is at most [maxEdge].
  static ScanGrey luminance(Uint8List rgba, int width, int height, {int maxEdge = 400}) {
    final full = Uint8List(width * height);
    for (var i = 0, o = 0; i < full.length; i++, o += 4) {
      full[i] = (rgba[o] * 77 + rgba[o + 1] * 150 + rgba[o + 2] * 29) >> 8;
    }
    final f = math.max(1, (math.max(width, height) / maxEdge).ceil());
    return (
      grey: GreyOps.shrink(full, width, height, f),
      width: width ~/ f,
      height: height ~/ f,
      scale: f.toDouble(),
    );
  }

  /// The long side corners are refined at; larger input is shrunk first.
  static const int refineEdge = 1600;

  /// The document's outline in [photo] in its pixel coordinates, or null
  /// (see [locate]).
  static Quad? find(RgbaImage photo) {
    final g = luminance(photo.pixels, photo.width, photo.height, maxEdge: refineEdge);
    return locate(g.grey, g.width, g.height)?.scaled(g.scale);
  }

  /// [detect]'s outline with its sides fitted to the edges in [grey] at
  /// its own resolution, to a fraction of a pixel (`QuadRefiner`).
  static Quad? locate(Uint8List grey, int width, int height) {
    final coarse = detect(grey, width, height);
    if (coarse == null) return null;
    // Detection works f times smaller, and its corners may be cut.
    final f = math.max(1, (math.max(width, height) / workingEdge).ceil());
    final smooth = GreyOps.blur(grey, width, height);
    return QuadRefiner.refine(smooth, width, height, coarse, radius: 3.0 * f + 3);
  }

  /// The document's outline in [grey] (8-bit luminance, row major, [width]
  /// × [height]) in its pixel coordinates, or null when no convincing one
  /// (large, convex, edged all round) is found.
  static Quad? detect(Uint8List grey, int width, int height) {
    final f = math.max(1, (math.max(width, height) / workingEdge).ceil());
    final w = width ~/ f, h = height ~/ f;
    if (w < 16 || h < 16) return null;
    final g = GreyOps.blur(GreyOps.blur(GreyOps.shrink(grey, width, height, f), w, h), w, h);
    final minArea = minAreaShare * w * h;
    final minBox = minArea.ceil();
    final regions = <List<Offset>>[];
    final o = GreyOps.otsu(g);
    for (final t in {o.threshold, ((o.threshold + o.high) / 2).round()}) {
      regions.addAll(GreyOps.regions(_mask(g, (v) => v > t), w, h, minBox));
    }
    regions.addAll(GreyOps.regions(_mask(g, (v) => v <= o.threshold), w, h, minBox));
    final edges = GreyOps.sobel(g, w, h);
    final e = math.max(8, GreyOps.otsu(edges).threshold);
    regions.addAll(GreyOps.regions(_mask(edges, (v) => v > e), w, h, minBox));

    Quad? best;
    for (final region in regions) {
      final hull = QuadHull.simplify(QuadHull.convexHull(region), 24);
      final four = QuadHull.largestQuad(hull);
      if (four == null) continue;
      final quad = Quad.ordered(four);
      if (quad.area < minArea || !quad.isConvex) continue;
      if (best != null && quad.area <= best.area) continue;
      if (_supported(g, w, h, quad)) best = quad;
    }
    return best?.scaled(f.toDouble());
  }

  static Uint8List _mask(Uint8List g, bool Function(int) test) {
    final m = Uint8List(g.length);
    for (var i = 0; i < g.length; i++) {
      if (test(g[i])) m[i] = 1;
    }
    return m;
  }

  /// Whether [quad]'s sides run along clear edges: across most of each
  /// side, the inside differs from the outside by a clear step, the same
  /// way round (brighter or darker) all round.
  static bool _supported(Uint8List g, int w, int h, Quad quad) {
    const offset = 3.0, minStep = 16, minSide = 0.4, minMean = 0.7;
    final c = quad.corners;
    final brighter = <double>[], darker = <double>[];
    for (var s = 0; s < 4; s++) {
      final a = c[s], b = c[(s + 1) % 4];
      final d = b - a;
      final len = d.distance;
      // Inward normal: the corners run clockwise on screen.
      final n = Offset(-d.dy, d.dx) / len * offset;
      final count = math.max(10, len ~/ 2);
      var up = 0, down = 0;
      for (var i = 0; i < count; i++) {
        final p = a + d * (0.1 + 0.8 * i / (count - 1));
        final inside = _at(g, w, h, p + n), outside = _at(g, w, h, p - n);
        if (inside < 0 || outside < 0) continue;
        if (inside - outside >= minStep) up++;
        if (outside - inside >= minStep) down++;
      }
      brighter.add(up / count);
      darker.add(down / count);
    }
    bool good(List<double> f) =>
        f.every((v) => v >= minSide) && f.reduce((a, b) => a + b) / 4 >= minMean;
    return good(brighter) || good(darker);
  }

  /// The grey value of the pixel containing [p], or -1 outside the image.
  static int _at(Uint8List g, int w, int h, Offset p) {
    final x = p.dx.floor(), y = p.dy.floor();
    if (x < 0 || y < 0 || x >= w || y >= h) return -1;
    return g[y * w + x];
  }
}
