import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'shape_kind.dart';

export 'shape_kind.dart';

/// The editable geometry of a shape stroke (drawn with the Shape tool or
/// snapped by hold to snap): its [kind] and control [points], from which
/// its outline (the stroke's points) is built.
///
/// [points] by kind:
///  * line, arrow: the two ends (tail, tip);
///  * rectangle: the four corners in order (a parallelogram once skewed);
///  * triangle, diamond, polygon: the vertices in order;
///  * ellipse: the centre and the ends of two conjugate semi-axes `u`,
///    `v` (the outline is `centre + u·cos t + v·sin t`);
///  * star: a frame like the ellipse's: the outer points are at angles
///    −90° + k·72° of the unit circle mapped through it, the inner ones at
///    [inner] of that radius in between.
///
/// Every kind is described by points an affine map takes to the same kind,
/// so moving, scaling or rotating a shape just maps its points ([map]).
@immutable
class ShapeGeometry {
  ShapeGeometry(this.kind, List<Offset> points, {this.inner = defaultInner})
    : points = List.unmodifiable(points),
      assert(isValidCount(kind, points.length), 'Wrong number of points for $kind');

  final ShapeKind kind;
  final List<Offset> points;

  /// A star's inner radius as a share of its outer one (0 < inner < 1).
  final double inner;

  static const double defaultInner = 0.42;
  static const double minInner = 0.1, maxInner = 0.95;

  /// The most vertices a polygon has.
  static const int maxVertices = 12;

  /// Whether a [kind] has [count] control points.
  static bool isValidCount(ShapeKind kind, int count) => switch (kind) {
    ShapeKind.line || ShapeKind.arrow => count == 2,
    ShapeKind.rectangle || ShapeKind.diamond => count == 4,
    ShapeKind.triangle || ShapeKind.ellipse || ShapeKind.star => count == 3,
    ShapeKind.polygon => count >= 3 && count <= maxVertices,
  };

  /// This shape with every point moved by [f] (an affine map).
  ShapeGeometry map(Offset Function(Offset p) f) =>
      ShapeGeometry(kind, [for (final p in points) f(p)], inner: inner);

  /// This shape with point [index] at [p].
  ShapeGeometry withPoint(int index, Offset p) =>
      ShapeGeometry(kind, [...points]..[index] = p, inner: inner);

  /// Compact JSON for storage and sync: `k` the kind, `p` the points as
  /// `[x0, y0, x1, y1, …]`, `i` a star's [inner] radius (stars only).
  Map<String, Object?> toJson() => {
    'k': kind.name,
    'p': [
      for (final p in points) ...[p.dx, p.dy],
    ],
    if (kind == ShapeKind.star) 'i': inner,
  };

  /// Parses [json] strictly (see [toJson]); throws [FormatException] when
  /// malformed.
  static ShapeGeometry fromJson(Object? json) {
    if (json is! Map) throw const FormatException('Malformed shape');
    final kind = ShapeKind.strict(json['k']);
    final p = json['p'];
    if (p is! List || p.length.isOdd || !isValidCount(kind, p.length ~/ 2)) {
      throw const FormatException('Malformed shape: p');
    }
    final points = <Offset>[];
    for (var i = 0; i < p.length; i += 2) {
      final x = p[i], y = p[i + 1];
      if (x is! num || y is! num || !x.isFinite || !y.isFinite) {
        throw const FormatException('Malformed shape: p');
      }
      points.add(Offset(x.toDouble(), y.toDouble()));
    }
    final inner = json['i'];
    if (kind == ShapeKind.star) {
      if (inner is! num || !(inner >= minInner && inner <= maxInner)) {
        throw const FormatException('Malformed shape: i');
      }
      return ShapeGeometry(kind, points, inner: inner.toDouble());
    }
    if (inner != null) throw const FormatException('Malformed shape: i without a star');
    return ShapeGeometry(kind, points);
  }

  @override
  bool operator ==(Object other) =>
      other is ShapeGeometry &&
      other.kind == kind &&
      other.inner == inner &&
      listEquals(other.points, points);

  @override
  int get hashCode => Object.hash(kind, inner, Object.hashAll(points));

  @override
  String toString() => 'ShapeGeometry(${toJson()})';
}
