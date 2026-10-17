/// Shapes the Shape tool draws and "hold to snap" recognises. Stored (tool
/// preferences, a shape stroke's `ShapeGeometry`) by [name]; never rename.
enum ShapeKind {
  line('Line'),
  arrow('Arrow'),
  rectangle('Rectangle'),
  ellipse('Ellipse'),
  triangle('Triangle'),
  diamond('Diamond'),
  star('Star'),

  /// A cubic Bézier spline through anchors, open or closed.
  curve('Curve'),

  /// An ellipse drawn regular (Shift, or nearly round); not in the picker:
  /// the Ellipse makes it.
  circle('Circle'),

  /// Recognised only (an irregular closed polygon); not in the picker.
  polygon('Polygon');

  const ShapeKind(this.label);

  final String label;

  /// The shapes offered by the Shape tool, in display order.
  static const List<ShapeKind> drawable = [
    line,
    arrow,
    rectangle,
    ellipse,
    triangle,
    diamond,
    star,
  ];

  /// Outlines that are always closed (start where they end). A curve may
  /// be either (`ShapeGeometry.isClosed`).
  bool get isClosed => this != line && this != arrow && this != curve;

  /// Whether shapes of this kind can take a fill: the closed kinds, and
  /// curves (once closed).
  bool get mayFill => isClosed || this == curve;

  /// The Shape tool's kind named [value]; a rectangle for anything else
  /// (tool preferences).
  static ShapeKind parse(Object? value) =>
      drawable.firstWhere((k) => k.name == value, orElse: () => rectangle);

  /// The kind named [value]; throws [FormatException] for others.
  static ShapeKind strict(Object? value) =>
      values.asNameMap()[value] ?? (throw FormatException('Unknown shape kind $value'));
}
