import 'shape_geometry.dart';

/// Something with a shape a connector's end can name: a stroke, or just
/// its id and geometry as read for a connector repair (no points decoded).
abstract interface class Shaped {
  /// The stroke's id.
  String get id;

  /// Its shape's geometry; null for free-hand ink.
  ShapeGeometry? get shape;

  /// The shape's identity across edits ([ShapeGeometry.origin], else [id]).
  String get shapeId;
}
