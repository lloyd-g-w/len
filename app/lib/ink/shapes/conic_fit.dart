import 'dart:math' as math;
import 'dart:ui';

/// A circle: [centre] and [radius].
typedef FittedCircle = ({Offset centre, double radius});

/// An ellipse: [centre], semi-axes [rx] along [angle] (radians) and [ry]
/// across it.
typedef FittedEllipse = ({Offset centre, double rx, double ry, double angle});

/// Least-squares circles and ellipses through points (a hand-drawn loop).
///
///  * [circle]: Taubin's fit (G. Taubin, "Estimation of planar curves,
///    surfaces and nonplanar space curves defined by implicit equations",
///    IEEE PAMI 1991), solved by Newton's method as in N. Chernov's
///    *Circular and Linear Regression* (2010): nearly as good as the
///    geometric fit and, unlike Kåsa's, unbiased by noise and by points
///    covering only part of the circle.
///  * [ellipse]: Fitzgibbon, Pilu and Fisher's direct least-squares
///    ellipse ("Direct least square fitting of ellipses", IEEE PAMI 1999)
///    in Halíř and Flusser's numerically stable form (1998): always an
///    ellipse, never a hyperbola, from one 3 × 3 eigenproblem.
///
/// Both work on points centred and scaled to unit size first, so
/// coordinates far from the origin lose no precision.
abstract final class ConicFit {
  /// The circle fitting [points] best (at least three, not all in line);
  /// null when there is none.
  static FittedCircle? circle(List<Offset> points) {
    final n = points.length;
    if (n < 3) return null;
    final (mean, scale) = _frame(points);
    var mxx = 0.0, myy = 0.0, mxy = 0.0, mxz = 0.0, myz = 0.0, mzz = 0.0;
    for (final p in points) {
      final x = (p.dx - mean.dx) / scale, y = (p.dy - mean.dy) / scale, z = x * x + y * y;
      mxx += x * x;
      myy += y * y;
      mxy += x * y;
      mxz += x * z;
      myz += y * z;
      mzz += z * z;
    }
    mxx /= n;
    myy /= n;
    mxy /= n;
    mxz /= n;
    myz /= n;
    mzz /= n;
    final mz = mxx + myy, cov = mxx * myy - mxy * mxy, varZ = mzz - mz * mz;
    // Taubin's characteristic polynomial, its smallest root by Newton's
    // method from 0 (Chernov's CircleFitByTaubin).
    final a3 = 4 * mz;
    final a2 = -3 * mz * mz - mzz;
    final a1 = varZ * mz + 4 * cov * mz - mxz * mxz - myz * myz;
    final a0 = mxz * (mxz * myy - myz * mxy) + myz * (myz * mxx - mxz * mxy) - varZ * cov;
    final a22 = 2 * a2, a33 = 3 * a3;
    var x = 0.0, y = a0;
    for (var i = 0; i < 99; i++) {
      final dy = a1 + x * (a22 + x * a33);
      if (dy == 0) break;
      final next = x - y / dy;
      if (!next.isFinite || (next - x).abs() <= 1e-12 * math.max(1, next.abs())) break;
      final yNext = a0 + next * (a1 + next * (a2 + next * a3));
      if (yNext.abs() > y.abs()) break;
      x = next;
      y = yNext;
    }
    final det = x * x - x * mz + cov;
    if (det.abs() < 1e-12) return null;
    final cx = (mxz * (myy - x) - myz * mxy) / det / 2;
    final cy = (myz * (mxx - x) - mxz * mxy) / det / 2;
    final r = math.sqrt(cx * cx + cy * cy + mz);
    if (!r.isFinite) return null;
    return (centre: mean + Offset(cx, cy) * scale, radius: r * scale);
  }

  /// The ellipse fitting [points] best (at least five, spread round it);
  /// null when they fit none (all in line).
  static FittedEllipse? ellipse(List<Offset> points) {
    if (points.length < 5) return null;
    final (mean, scale) = _frame(points);
    // Scatter matrices of the quadratic part D1 = [x², xy, y²] and the
    // linear part D2 = [x, y, 1] (Halíř–Flusser).
    final s1 = List.filled(9, 0.0), s2 = List.filled(9, 0.0), s3 = List.filled(9, 0.0);
    for (final p in points) {
      final x = (p.dx - mean.dx) / scale, y = (p.dy - mean.dy) / scale;
      final d1 = [x * x, x * y, y * y], d2 = [x, y, 1.0];
      for (var i = 0; i < 3; i++) {
        for (var j = 0; j < 3; j++) {
          s1[3 * i + j] += d1[i] * d1[j];
          s2[3 * i + j] += d1[i] * d2[j];
          s3[3 * i + j] += d2[i] * d2[j];
        }
      }
    }
    final s3inv = _inverse(s3);
    if (s3inv == null) return null;
    // T = −S3⁻¹ S2ᵀ; M = S1 + S2 T; then C1⁻¹ M.
    final t = List.filled(9, 0.0);
    for (var i = 0; i < 3; i++) {
      for (var j = 0; j < 3; j++) {
        var sum = 0.0;
        for (var k = 0; k < 3; k++) {
          sum += s3inv[3 * i + k] * s2[3 * j + k];
        }
        t[3 * i + j] = -sum;
      }
    }
    final m = List.filled(9, 0.0);
    for (var i = 0; i < 3; i++) {
      for (var j = 0; j < 3; j++) {
        var sum = s1[3 * i + j];
        for (var k = 0; k < 3; k++) {
          sum += s2[3 * i + k] * t[3 * k + j];
        }
        m[3 * i + j] = sum;
      }
    }
    final c = [
      for (var j = 0; j < 3; j++) m[6 + j] / 2,
      for (var j = 0; j < 3; j++) -m[3 + j],
      for (var j = 0; j < 3; j++) m[j] / 2,
    ];
    // The eigenvector with 4ac − b² > 0 is the ellipse.
    List<double>? best;
    var bestCondition = 0.0;
    for (final lambda in _realEigenvalues(c)) {
      final v = _nullVector(c, lambda);
      if (v == null) continue;
      final condition = 4 * v[0] * v[2] - v[1] * v[1];
      final norm = v[0] * v[0] + v[1] * v[1] + v[2] * v[2];
      if (condition / norm > bestCondition) {
        best = v;
        bestCondition = condition / norm;
      }
    }
    if (best == null) return null;
    final [a, b, cc] = best;
    final d = t[0] * a + t[1] * b + t[2] * cc;
    final e = t[3] * a + t[4] * b + t[5] * cc;
    final f = t[6] * a + t[7] * b + t[8] * cc;
    final shape = _conicEllipse(a, b, cc, d, e, f);
    if (shape == null) return null;
    return (
      centre: mean + shape.centre * scale,
      rx: shape.rx * scale,
      ry: shape.ry * scale,
      angle: shape.angle,
    );
  }

  /// The centroid of [points] and their RMS distance from it.
  static (Offset, double) _frame(List<Offset> points) {
    var sum = Offset.zero;
    for (final p in points) {
      sum += p;
    }
    final mean = sum / points.length.toDouble();
    var s = 0.0;
    for (final p in points) {
      s += (p - mean).distanceSquared;
    }
    final scale = math.sqrt(s / points.length);
    return (mean, scale > 0 ? scale : 1);
  }

  /// The ellipse `ax² + bxy + cy² + dx + ey + f = 0`, or null if it is
  /// none.
  static FittedEllipse? _conicEllipse(double a, double b, double c, double d, double e, double f) {
    final den = b * b - 4 * a * c;
    if (den >= 0) return null;
    final cx = (2 * c * d - b * e) / den, cy = (2 * a * e - b * d) / den;
    // The value at the centre: the conic is (x − c)ᵀ A (x − c) = −f0.
    final f0 = a * cx * cx + b * cx * cy + c * cy * cy + d * cx + e * cy + f;
    // Eigenvalues of A = [[a, b/2], [b/2, c]].
    final mean = (a + c) / 2, diff = math.sqrt(math.pow((a - c) / 2, 2) + b * b / 4);
    final l1 = mean - diff, l2 = mean + diff;
    final angle = 0.5 * math.atan2(b, a - c) + math.pi / 2; // the axis of l1
    final rx2 = -f0 / l1, ry2 = -f0 / l2;
    if (!(rx2 > 0 && ry2 > 0)) return null;
    return (centre: Offset(cx, cy), rx: math.sqrt(rx2), ry: math.sqrt(ry2), angle: angle);
  }

  static List<double>? _inverse(List<double> m) {
    final [a, b, c, d, e, f, g, h, i] = m;
    final co = [e * i - f * h, c * h - b * i, b * f - c * e, f * g - d * i, a * i - c * g];
    final det = a * co[0] + b * co[3] + c * (d * h - e * g);
    if (det.abs() < 1e-14) return null;
    return [
      co[0] / det,
      co[1] / det,
      co[2] / det,
      co[3] / det,
      co[4] / det,
      (c * d - a * f) / det,
      (d * h - e * g) / det,
      (b * g - a * h) / det,
      (a * e - b * d) / det,
    ];
  }

  /// The real eigenvalues of 3 × 3 [m] (row-major): roots of its
  /// characteristic cubic.
  static List<double> _realEigenvalues(List<double> m) {
    final [a, b, c, d, e, f, g, h, i] = m;
    final tr = a + e + i;
    final minors = (a * e - b * d) + (a * i - c * g) + (e * i - f * h);
    final det = a * (e * i - f * h) - b * (d * i - f * g) + c * (d * h - e * g);
    // λ³ − tr λ² + minors λ − det = 0.
    return _cubicRoots(-tr, minors, -det);
  }

  /// The real roots of x³ + px² + qx + r.
  static List<double> _cubicRoots(double p, double q, double r) {
    final a = p / 3;
    final qq = (p * p - 3 * q) / 9;
    final rr = (2 * p * p * p - 9 * p * q + 27 * r) / 54;
    final q3 = qq * qq * qq;
    if (rr * rr < q3) {
      final theta = math.acos((rr / math.sqrt(q3)).clamp(-1.0, 1.0));
      final s = -2 * math.sqrt(qq);
      return [
        s * math.cos(theta / 3) - a,
        s * math.cos((theta + 2 * math.pi) / 3) - a,
        s * math.cos((theta - 2 * math.pi) / 3) - a,
      ];
    }
    final big = -rr.sign * math.pow(rr.abs() + math.sqrt(rr * rr - q3), 1 / 3).toDouble();
    final small = big == 0 ? 0.0 : qq / big;
    return [big + small - a];
  }

  /// A vector [m] − λI takes to zero: the largest cross product of two of
  /// its rows.
  static List<double>? _nullVector(List<double> m, double lambda) {
    final rows = [
      [m[0] - lambda, m[1], m[2]],
      [m[3], m[4] - lambda, m[5]],
      [m[6], m[7], m[8] - lambda],
    ];
    List<double>? best;
    var bestNorm = 0.0;
    for (final (i, j) in const [(0, 1), (0, 2), (1, 2)]) {
      final u = rows[i], v = rows[j];
      final w = [u[1] * v[2] - u[2] * v[1], u[2] * v[0] - u[0] * v[2], u[0] * v[1] - u[1] * v[0]];
      final norm = w[0] * w[0] + w[1] * w[1] + w[2] * w[2];
      if (norm > bestNorm) {
        best = w;
        bestNorm = norm;
      }
    }
    return bestNorm > 0 ? best : null;
  }
}
