/// How a closed shape is filled: not at all, with a light tint of its
/// ink's colour (translucent, so paper and ink beneath show through) or
/// with a solid colour. The Shape tool's choice for new shapes
/// (`ToolSettings.shapeFill`) and what the selection's Style panel sets.
class ShapeFill {
  const ShapeFill._(this.tint, this.color);

  /// A tint of the ink's colour at opacity [alpha] (one of [tints]).
  const ShapeFill.tint(double alpha) : this._(alpha, null);

  /// A solid fill in [argb] (opaque).
  const ShapeFill.solid(int argb) : this._(0, argb);

  /// No fill.
  static const none = ShapeFill._(0, null);

  /// The tints offered, lightest first.
  static const List<double> tints = [0.12, 0.25, 0.45];

  /// The tint's opacity (0 unless a tint).
  final double tint;

  /// The solid colour, if solid.
  final int? color;

  bool get isNone => tint == 0 && color == null;
  bool get isTint => tint > 0;

  /// The fill colour (ARGB) of a shape drawn in ink colour [ink]; null for
  /// none.
  int? colorFor(int ink) {
    if (color case final c?) return c | 0xFF000000;
    if (tint <= 0) return null;
    return (tint * 255).round() << 24 | ink & 0xFFFFFF;
  }

  /// The choice that gives a shape in ink colour [ink] fill [fill].
  static ShapeFill of(int? fill, int ink) {
    if (fill == null) return none;
    if (fill & 0xFFFFFF == ink & 0xFFFFFF) {
      for (final t in tints) {
        if ((t * 255).round() == fill >>> 24) return ShapeFill.tint(t);
      }
    }
    return ShapeFill.solid(fill | 0xFF000000);
  }

  /// Compact JSON for the tool preferences.
  Object toJson() => color != null ? {'color': color} : (isTint ? {'tint': tint} : 'none');

  /// Parses [json] strictly; anything else is [none].
  static ShapeFill parse(Object? json) {
    if (json is! Map) return none;
    if (json['color'] case final int c when c >= 0 && c <= 0xFFFFFFFF) {
      return ShapeFill.solid(c | 0xFF000000);
    }
    if (json['tint'] case final num t when tints.contains(t)) return ShapeFill.tint(t.toDouble());
    return none;
  }

  @override
  bool operator ==(Object other) =>
      other is ShapeFill && other.tint == tint && other.color == color;

  @override
  int get hashCode => Object.hash(tint, color);

  @override
  String toString() => 'ShapeFill(${toJson()})';
}
