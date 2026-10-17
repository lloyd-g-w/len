import 'package:flutter/foundation.dart';

/// Where the end of a line or arrow is attached to another shape (a
/// connector): the shape stroke's [id] and the [at] point on its outline,
/// a parameter in 0..1 along the outline in the shape's own terms, so the
/// end follows the shape when it moves, turns, resizes or is reshaped:
///  * rectangle, triangle, diamond, polygon, star: `at · n` is `i + f` for
///    `n` vertices, the point `f` of the way along the side from vertex `i`
///    to the next;
///  * circle, ellipse: the angle `2π · at` of `centre + u·cos t + v·sin t`;
///  * closed curve: `at · n` is `i + f` for `n` anchors, the Bézier
///    parameter `f` of the segment from anchor `i`.
///
/// Only closed shapes are targets. A reference to a stroke that is not on
/// the line's own surface (deleted, replaced without it, another page) is
/// ignored: the end stays where it is.
@immutable
class ShapeAttachment {
  const ShapeAttachment(this.id, this.at);

  /// The target shape stroke's id.
  final String id;

  /// The point on its outline, 0 ≤ at < 1.
  final double at;

  /// This attachment to [id] instead.
  ShapeAttachment withId(String id) => ShapeAttachment(id, at);

  /// `{id, t}`.
  Map<String, Object?> toJson() => {'id': id, 't': at};

  /// Parses [json] (see [toJson]); null stays null. Throws
  /// [FormatException] when malformed.
  static ShapeAttachment? fromJson(Object? json) {
    if (json == null) return null;
    if (json case {'id': final String id, 't': final num t} when id.isNotEmpty) {
      if (t.isFinite && t >= 0 && t <= 1) return ShapeAttachment(id, t.toDouble() % 1);
    }
    throw const FormatException('Malformed shape: a');
  }

  @override
  bool operator ==(Object other) => other is ShapeAttachment && other.id == id && other.at == at;

  @override
  int get hashCode => Object.hash(id, at);

  @override
  String toString() => 'ShapeAttachment($id, $at)';
}
