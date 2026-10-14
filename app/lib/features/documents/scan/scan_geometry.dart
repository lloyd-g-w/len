import 'dart:math' as math;
import 'dart:ui' show Offset, Size;

/// A document outline in image pixels: four corners, clockwise on screen
/// (y down) from the top left.
class Quad {
  /// A quad from its corners in order.
  const Quad(this.topLeft, this.topRight, this.bottomRight, this.bottomLeft);

  /// A quad from exactly four corners, ordered top left, top right, bottom
  /// right, bottom left.
  factory Quad.fromCorners(List<Offset> corners) {
    if (corners.length != 4) throw ArgumentError.value(corners, 'corners', 'needs 4 points');
    return Quad(corners[0], corners[1], corners[2], corners[3]);
  }

  /// The whole of an image of [width] × [height] pixels.
  factory Quad.bounds(double width, double height) =>
      Quad(Offset.zero, Offset(width, 0), Offset(width, height), Offset(0, height));

  /// Sorts four arbitrary points into top left, top right, bottom right,
  /// bottom left: clockwise around their centroid, starting at the point
  /// with the smallest x + y.
  factory Quad.ordered(Iterable<Offset> four) {
    final points = four.toList();
    if (points.length != 4) throw ArgumentError.value(four, 'four', 'needs 4 points');
    final c = points.fold(Offset.zero, (s, p) => s + p) / 4;
    double angle(Offset p) => math.atan2(p.dy - c.dy, p.dx - c.dx);
    points.sort((a, b) => angle(a).compareTo(angle(b)));
    var first = 0;
    for (var i = 1; i < 4; i++) {
      final p = points[i], f = points[first];
      if (p.dx + p.dy < f.dx + f.dy) first = i;
    }
    return Quad.fromCorners([for (var i = 0; i < 4; i++) points[(first + i) % 4]]);
  }

  /// Top-left corner.
  final Offset topLeft;

  /// Top-right corner.
  final Offset topRight;

  /// Bottom-right corner.
  final Offset bottomRight;

  /// Bottom-left corner.
  final Offset bottomLeft;

  /// The corners: top left, top right, bottom right, bottom left.
  List<Offset> get corners => [topLeft, topRight, bottomRight, bottomLeft];

  /// The enclosed area (shoelace formula, always ≥ 0).
  double get area {
    final c = corners;
    var sum = 0.0;
    for (var i = 0; i < 4; i++) {
      final a = c[i], b = c[(i + 1) % 4];
      sum += a.dx * b.dy - b.dx * a.dy;
    }
    return sum.abs() / 2;
  }

  /// Whether the quad is strictly convex (no reflex or straight corner,
  /// no self-intersection).
  bool get isConvex {
    final c = corners;
    var sign = 0;
    for (var i = 0; i < 4; i++) {
      final a = c[i], b = c[(i + 1) % 4], d = c[(i + 2) % 4];
      final cross = (b.dx - a.dx) * (d.dy - b.dy) - (b.dy - a.dy) * (d.dx - b.dx);
      if (cross == 0) return false;
      final s = cross > 0 ? 1 : -1;
      if (sign != 0 && s != sign) return false;
      sign = s;
    }
    return true;
  }

  /// This quad with corner [i] (0 = top left … 3 = bottom left) moved to [p].
  Quad withCorner(int i, Offset p) {
    final c = corners;
    c[i] = p;
    return Quad.fromCorners(c);
  }

  /// This quad with every coordinate multiplied by [s].
  Quad scaled(double s) => Quad(topLeft * s, topRight * s, bottomRight * s, bottomLeft * s);

  /// The flattened page's size in pixels: the longer of the top and bottom
  /// edges by the longer of the left and right edges, scaled down (never up)
  /// so the long side is at most [maxEdge]; each side at least 1.
  Size outputSize({required int maxEdge}) {
    final w = math.max((topRight - topLeft).distance, (bottomRight - bottomLeft).distance);
    final h = math.max((bottomLeft - topLeft).distance, (bottomRight - topRight).distance);
    final long = math.max(w, h);
    final s = long > maxEdge ? maxEdge / long : 1.0;
    return Size(math.max(1, (w * s).round()).toDouble(), math.max(1, (h * s).round()).toDouble());
  }

  @override
  bool operator ==(Object other) =>
      other is Quad &&
      other.topLeft == topLeft &&
      other.topRight == topRight &&
      other.bottomRight == bottomRight &&
      other.bottomLeft == bottomLeft;

  @override
  int get hashCode => Object.hash(topLeft, topRight, bottomRight, bottomLeft);

  @override
  String toString() => 'Quad($topLeft, $topRight, $bottomRight, $bottomLeft)';
}

/// A projective map of the plane: a 3 × 3 matrix, row major.
class Homography {
  /// A homography from its nine coefficients, row major.
  Homography(List<double> m) : m = List.unmodifiable(m) {
    if (m.length != 9) throw ArgumentError.value(m, 'm', 'needs 9 coefficients');
  }

  /// The map from a flattened page of [page] size (pixel coordinates in
  /// [0, w] × [0, h]) onto [quad] in the source image: the page's corners
  /// land exactly on the quad's corners (Heckbert's square-to-quad).
  factory Homography.pageToQuad(Size page, Quad quad) {
    final x0 = quad.topLeft.dx, y0 = quad.topLeft.dy;
    final x1 = quad.topRight.dx, y1 = quad.topRight.dy;
    final x2 = quad.bottomRight.dx, y2 = quad.bottomRight.dy;
    final x3 = quad.bottomLeft.dx, y3 = quad.bottomLeft.dy;
    final sx = x0 - x1 + x2 - x3, sy = y0 - y1 + y2 - y3;
    double a, b, d, e, g, h;
    if (sx.abs() < 1e-9 && sy.abs() < 1e-9) {
      a = x1 - x0;
      b = x3 - x0;
      d = y1 - y0;
      e = y3 - y0;
      g = 0;
      h = 0;
    } else {
      final dx1 = x1 - x2, dx2 = x3 - x2, dy1 = y1 - y2, dy2 = y3 - y2;
      final den = dx1 * dy2 - dx2 * dy1;
      g = (sx * dy2 - dx2 * sy) / den;
      h = (dx1 * sy - sx * dy1) / den;
      a = x1 - x0 + g * x1;
      b = x3 - x0 + h * x3;
      d = y1 - y0 + g * y1;
      e = y3 - y0 + h * y3;
    }
    // Unit square → quad, preceded by page → unit square.
    final iw = 1 / page.width, ih = 1 / page.height;
    return Homography([a * iw, b * ih, x0, d * iw, e * ih, y0, g * iw, h * ih, 1]);
  }

  /// The coefficients, row major.
  final List<double> m;

  /// Maps [p] through this homography.
  Offset map(Offset p) {
    final w = m[6] * p.dx + m[7] * p.dy + m[8];
    return Offset((m[0] * p.dx + m[1] * p.dy + m[2]) / w, (m[3] * p.dx + m[4] * p.dy + m[5]) / w);
  }

  /// The inverse map (the adjugate over the determinant).
  Homography inverse() {
    final a = m[0], b = m[1], c = m[2], d = m[3], e = m[4], f = m[5], g = m[6], h = m[7];
    final i = m[8];
    final ca = e * i - f * h, cb = f * g - d * i, cc = d * h - e * g;
    final det = a * ca + b * cb + c * cc;
    if (det == 0) throw StateError('Singular homography');
    final r = 1 / det;
    return Homography([
      ca * r,
      (c * h - b * i) * r,
      (b * f - c * e) * r,
      cb * r,
      (a * i - c * g) * r,
      (c * d - a * f) * r,
      cc * r,
      (b * g - a * h) * r,
      (a * e - b * d) * r,
    ]);
  }
}
