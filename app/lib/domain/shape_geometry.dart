import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import 'shape_attachment.dart';
import 'shape_kind.dart';

export 'shape_attachment.dart';
export 'shape_kind.dart';

/// The editable geometry of a shape stroke (drawn with the Shape tool or
/// snapped by hold to snap): its [kind] and control [points], from which
/// its outline (the stroke's points) is built.
///
/// [points] by kind:
///  * line, arrow: the two ends (tail, tip), and for a bent one a third
///    point, the bend: the middle of the curve (a quadratic Bézier from
///    tail to tip through it at t = ½);
///  * rectangle: the four corners in order (a parallelogram once skewed);
///  * triangle, diamond, polygon: the vertices in order (a diamond's are
///    top, right, bottom, left of its frame);
///  * circle: the centre and a point on the rim (its radius handle);
///  * ellipse: the centre and the ends of its two semi-axes `u`, `v`,
///    kept perpendicular (the outline is `centre + u·cos t + v·sin t`);
///  * star: a frame like an ellipse's (centre, `u`, `v`, not necessarily
///    perpendicular): its [tips] outer points lie at −90° + k·360°/[tips]
///    of the unit circle mapped through it, the inner ones at [inner] of
///    that radius in between;
///  * curve: a cubic Bézier spline: anchor, its outgoing handle, the next
///    anchor's incoming handle, the next anchor, … — `3n − 2` points for
///    `n` anchors when open; closed, `3n`, the last being the first
///    anchor's incoming handle.
///
/// Every kind is described by points an affine map takes to the same kind
/// (a circle squashed becomes an ellipse), so moving, scaling or rotating
/// a shape maps its points ([map]).
@immutable
class ShapeGeometry {
  ShapeGeometry(
    this.kind,
    List<Offset> points, {
    this.inner = defaultInner,
    this.tips = defaultTips,
    this.tail,
    this.tip,
    this.origin,
  }) : points = List.unmodifiable(points),
       assert(isValidCount(kind, points.length), 'Wrong number of points for $kind'),
       assert(
         (tail == null && tip == null) || kind == ShapeKind.line || kind == ShapeKind.arrow,
         'Only lines and arrows attach',
       );

  /// The ellipse around [centre] with conjugate semi-axes [u] and [v] (any
  /// affine image of a circle), as its perpendicular semi-axes: the pair
  /// nearest [u] and [v].
  factory ShapeGeometry.ellipse(Offset centre, Offset u, Offset v, {String? origin}) {
    final (a, b) = principalAxes(u, v);
    return ShapeGeometry(ShapeKind.ellipse, [centre, centre + a, centre + b], origin: origin);
  }

  final ShapeKind kind;
  final List<Offset> points;

  /// A star's inner radius as a share of its outer one (0 < inner < 1).
  final double inner;

  /// How many points a star has.
  final int tips;

  /// The shapes a line's or arrow's ends ([points] 0 and 1) are attached
  /// to (connectors), if any; null for other kinds.
  final ShapeAttachment? tail, tip;

  /// The shape's identity across edits: the id of the stroke it was first
  /// drawn as, which every edit (a new stroke) keeps; null for a shape
  /// never edited, whose identity is its stroke's own id
  /// ([Stroke.shapeId]). Connectors refer to it ([ShapeAttachment.id]), so
  /// an edit of the shape on one device and of its arrow on another still
  /// meet.
  final String? origin;

  /// This shape with identity [origin] (see [ShapeGeometry.origin]).
  ShapeGeometry withOrigin(String? origin) => origin == this.origin
      ? this
      : ShapeGeometry(kind, points, inner: inner, tips: tips, tail: tail, tip: tip, origin: origin);

  /// The attachment of end [index] (0: tail, 1: tip).
  ShapeAttachment? attachmentOf(int index) => index == 0 ? tail : tip;

  /// Whether an end is attached to a shape.
  bool get isAttached => tail != null || tip != null;

  /// This line or arrow with end [index] (0: tail, 1: tip) attached to
  /// [attachment] (null: detached).
  ShapeGeometry withAttachment(int index, ShapeAttachment? attachment) => ShapeGeometry(
    kind,
    points,
    tail: index == 0 ? attachment : tail,
    tip: index == 1 ? attachment : tip,
    origin: origin,
  );

  /// This shape with its attachments changed by [f] (null: detached).
  ShapeGeometry withAttachments(ShapeAttachment? Function(ShapeAttachment a) f) {
    if (!isAttached) return this;
    final a = tail == null ? null : f(tail!), b = tip == null ? null : f(tip!);
    return a == tail && b == tip
        ? this
        : ShapeGeometry(kind, points, tail: a, tip: b, origin: origin);
  }

  static const double defaultInner = 0.42;
  static const double minInner = 0.1, maxInner = 0.95;
  static const int defaultTips = 5, minTips = 3, maxTips = 12;

  /// The most vertices a polygon has.
  static const int maxVertices = 12;

  /// The most anchors a curve has.
  static const int maxAnchors = 64;

  /// Whether a [kind] has [count] control points.
  static bool isValidCount(ShapeKind kind, int count) => switch (kind) {
    ShapeKind.line || ShapeKind.arrow => count == 2 || count == 3,
    ShapeKind.circle => count == 2,
    ShapeKind.rectangle || ShapeKind.diamond => count == 4,
    ShapeKind.triangle || ShapeKind.ellipse || ShapeKind.star => count == 3,
    ShapeKind.polygon => count >= 3 && count <= maxVertices,
    ShapeKind.curve =>
      (count % 3 == 1 && count >= 4 && count <= 3 * maxAnchors - 2) ||
          (count % 3 == 0 && count >= 6 && count <= 3 * maxAnchors),
  };

  /// Whether the outline is closed: every kind but lines, arrows and open
  /// curves.
  bool get isClosed => kind == ShapeKind.curve ? points.length % 3 == 0 : kind.isClosed;

  /// A line or arrow with a bend (three points).
  bool get isBent => (kind == ShapeKind.line || kind == ShapeKind.arrow) && points.length == 3;

  /// A curve's number of anchors.
  int get anchorCount => isClosed ? points.length ~/ 3 : (points.length + 2) ~/ 3;

  /// This shape with every point moved by [f] (an affine map). An
  /// ellipse keeps perpendicular semi-axes; a circle no longer round
  /// becomes an ellipse.
  ShapeGeometry map(Offset Function(Offset p) f) {
    switch (kind) {
      case ShapeKind.circle:
        final [c, rim] = points;
        final u = rim - c, v = Offset(-u.dy, u.dx);
        final c2 = f(c), u2 = f(c + u) - c2, v2 = f(c + v) - c2;
        final round =
            (u2.distance - v2.distance).abs() <= 1e-9 * (u2.distance + v2.distance) &&
            (u2.dx * v2.dx + u2.dy * v2.dy).abs() <= 1e-9 * u2.distanceSquared;
        return round
            ? ShapeGeometry(kind, [c2, c2 + u2], origin: origin)
            : ShapeGeometry.ellipse(c2, u2, v2, origin: origin);
      case ShapeKind.ellipse:
        final c2 = f(points[0]);
        return ShapeGeometry.ellipse(c2, f(points[1]) - c2, f(points[2]) - c2, origin: origin);
      default:
        return withPoints([for (final p in points) f(p)]);
    }
  }

  /// This shape with point [index] at [p].
  ShapeGeometry withPoint(int index, Offset p) => withPoints([...points]..[index] = p);

  /// This shape (same kind, star parameters, attachments, origin) with
  /// other [points].
  ShapeGeometry withPoints(List<Offset> points) =>
      ShapeGeometry(kind, points, inner: inner, tips: tips, tail: tail, tip: tip, origin: origin);

  /// This star with another [inner] radius or number of [tips].
  ShapeGeometry withStar({double? inner, int? tips}) => ShapeGeometry(
    kind,
    points,
    inner: inner ?? this.inner,
    tips: tips ?? this.tips,
    origin: origin,
  );

  /// The perpendicular semi-axes of the ellipse `u·cos t + v·sin t`: the
  /// pair at the parameter nearest 0 (so already perpendicular axes stay
  /// as they are).
  static (Offset, Offset) principalAxes(Offset u, Offset v) {
    final dot = u.dx * v.dx + u.dy * v.dy;
    if (dot.abs() <= 1e-12 * (u.distanceSquared + v.distanceSquared)) return (u, v);
    var t = 0.5 * math.atan2(2 * dot, u.distanceSquared - v.distanceSquared);
    // Both t and t ± 90° are principal: take the one nearest 0.
    if (t > math.pi / 4) t -= math.pi / 2;
    if (t < -math.pi / 4) t += math.pi / 2;
    final c = math.cos(t), s = math.sin(t);
    return (u * c + v * s, v * c - u * s);
  }

  /// Compact JSON for storage and sync: `k` the kind, `p` the points as
  /// `[x0, y0, x1, y1, …]`, `i` a star's [inner] radius and `n` its
  /// [tips] (stars only), `a` a line's or arrow's attachments `[tail, tip]`
  /// (each `{id, t}` or null; absent when neither end is attached), `o`
  /// the [origin] (absent when null).
  Map<String, Object?> toJson() => {
    'k': kind.name,
    'p': [
      for (final p in points) ...[p.dx, p.dy],
    ],
    if (kind == ShapeKind.star) ...{'i': inner, 'n': tips},
    if (isAttached) 'a': [tail?.toJson(), tip?.toJson()],
    'o': ?origin,
  };

  /// Parses [json] strictly (see [toJson]); throws [FormatException] when
  /// malformed. An ellipse's semi-axes are made perpendicular; a star
  /// without `n` has five points.
  static ShapeGeometry fromJson(Object? json) {
    if (json is! Map) throw const FormatException('Malformed shape');
    final origin = json['o'];
    if (origin != null && (origin is! String || origin.isEmpty)) {
      throw const FormatException('Malformed shape: o');
    }
    return _fromJson(json).withOrigin(origin as String?);
  }

  static ShapeGeometry _fromJson(Map<Object?, Object?> json) {
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
    final inner = json['i'], tips = json['n'];
    if (kind == ShapeKind.star) {
      if (inner is! num || !(inner >= minInner && inner <= maxInner)) {
        throw const FormatException('Malformed shape: i');
      }
      // Stars written before they had other numbers of points have five.
      final n = tips ?? defaultTips;
      if (n is! int || n < minTips || n > maxTips) {
        throw const FormatException('Malformed shape: n');
      }
      return ShapeGeometry(kind, points, inner: inner.toDouble(), tips: n);
    }
    if (inner != null || tips != null) {
      throw const FormatException('Malformed shape: i or n without a star');
    }
    final a = json['a'];
    if (a != null) {
      if (kind != ShapeKind.line && kind != ShapeKind.arrow || a is! List || a.length != 2) {
        throw const FormatException('Malformed shape: a');
      }
      return ShapeGeometry(
        kind,
        points,
        tail: ShapeAttachment.fromJson(a[0]),
        tip: ShapeAttachment.fromJson(a[1]),
      );
    }
    if (kind == ShapeKind.ellipse) {
      return ShapeGeometry.ellipse(points[0], points[1] - points[0], points[2] - points[0]);
    }
    return ShapeGeometry(kind, points);
  }

  @override
  bool operator ==(Object other) =>
      other is ShapeGeometry &&
      other.kind == kind &&
      other.inner == inner &&
      other.tips == tips &&
      other.tail == tail &&
      other.tip == tip &&
      other.origin == origin &&
      listEquals(other.points, points);

  @override
  int get hashCode => Object.hash(kind, inner, tips, tail, tip, origin, Object.hashAll(points));

  @override
  String toString() => 'ShapeGeometry(${toJson()})';
}
