import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui';

/// A 2D affine transform: `x' = a·x + c·y + tx`, `y' = b·x + d·y + ty`.
///
/// Used to move, scale and rotate selections; [matrix4] lets a canvas apply
/// the same transform to a cached picture for a cheap live preview.
class Affine {
  const Affine(this.a, this.b, this.c, this.d, this.tx, this.ty);

  static const Affine identity = Affine(1, 0, 0, 1, 0, 0);

  factory Affine.translation(Offset delta) => Affine(1, 0, 0, 1, delta.dx, delta.dy);

  /// Clockwise rotation by [angle] radians (screen coordinates, y down)
  /// about [pivot].
  factory Affine.rotation(double angle, {Offset pivot = Offset.zero}) {
    final cos = math.cos(angle), sin = math.sin(angle);
    return Affine(
      cos,
      sin,
      -sin,
      cos,
      pivot.dx - cos * pivot.dx + sin * pivot.dy,
      pivot.dy - sin * pivot.dx - cos * pivot.dy,
    );
  }

  /// Scaling by [sx] / [sy] keeping [anchor] fixed.
  factory Affine.scaling(double sx, double sy, {Offset anchor = Offset.zero}) =>
      Affine(sx, 0, 0, sy, anchor.dx * (1 - sx), anchor.dy * (1 - sy));

  final double a, b, c, d, tx, ty;

  Offset apply(Offset p) => Offset(a * p.dx + c * p.dy + tx, b * p.dx + d * p.dy + ty);

  /// Applies only the linear part (for direction vectors).
  Offset applyVector(Offset v) => Offset(a * v.dx + c * v.dy, b * v.dx + d * v.dy);

  /// This transform followed by [next].
  Affine then(Affine next) => Affine(
    next.a * a + next.c * b,
    next.b * a + next.d * b,
    next.a * c + next.c * d,
    next.b * c + next.d * d,
    next.a * tx + next.c * ty + next.tx,
    next.b * tx + next.d * ty + next.ty,
  );

  double get determinant => a * d - b * c;

  /// The rotation angle of the transform's x axis.
  double get rotation => math.atan2(b, a);

  /// Factor by which lengths change on average (sqrt of the area factor).
  double get meanScale => math.sqrt(determinant.abs());

  bool get isTranslation => a == 1 && b == 0 && c == 0 && d == 1;
  bool get isIdentity => isTranslation && tx == 0 && ty == 0;

  Affine get inverse {
    final det = determinant;
    return Affine(
      d / det,
      -b / det,
      -c / det,
      a / det,
      (c * ty - d * tx) / det,
      (b * tx - a * ty) / det,
    );
  }

  /// Column-major 4×4 matrix for [Canvas.transform].
  Float64List get matrix4 =>
      Float64List.fromList([a, b, 0, 0, c, d, 0, 0, 0, 0, 1, 0, tx, ty, 0, 1]);

  @override
  bool operator ==(Object other) =>
      other is Affine &&
      other.a == a &&
      other.b == b &&
      other.c == c &&
      other.d == d &&
      other.tx == tx &&
      other.ty == ty;

  @override
  int get hashCode => Object.hash(a, b, c, d, tx, ty);

  @override
  String toString() => 'Affine($a, $b, $c, $d, $tx, $ty)';
}
