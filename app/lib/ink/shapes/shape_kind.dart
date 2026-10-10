/// Shapes the Shape tool draws and "hold to snap" recognises.
/// Stored (tool preferences) by [name]; never rename.
enum ShapeKind {
  line('Line'),
  arrow('Arrow'),
  rectangle('Rectangle'),
  ellipse('Ellipse'),
  triangle('Triangle'),
  diamond('Diamond'),
  star('Star'),

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

  /// Closed outlines (start where they end).
  bool get isClosed => this != line && this != arrow;

  static ShapeKind parse(Object? value) =>
      drawable.firstWhere((k) => k.name == value, orElse: () => rectangle);
}
