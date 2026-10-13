/// How the eraser removes ink.
enum EraserMode {
  /// Removes every stroke it touches, whole.
  stroke,

  /// Removes only the ink under the eraser, splitting strokes.
  pixel,
}

/// Eraser settings.
class EraserConfig {
  const EraserConfig({
    this.mode = EraserMode.stroke,
    this.radius = 12,
    this.highlighterOnly = false,
  });

  static const double minRadius = 3;
  static const double maxRadius = 60;

  /// Quick sizes offered in the toolbar (radius in screen pixels).
  static const List<double> quickSizes = [6, 12, 28];

  final EraserMode mode;

  /// Radius in screen pixels (independent of zoom).
  final double radius;

  /// Only erase highlighter ink, leaving pen ink untouched.
  final bool highlighterOnly;

  EraserConfig copyWith({EraserMode? mode, double? radius, bool? highlighterOnly}) => EraserConfig(
    mode: mode ?? this.mode,
    radius: radius ?? this.radius,
    highlighterOnly: highlighterOnly ?? this.highlighterOnly,
  );

  Map<String, Object?> toJson() => {
    'mode': mode.name,
    'radius': radius,
    'highlighterOnly': highlighterOnly,
  };

  /// Parses settings saved by [toJson] strictly (every field present and
  /// valid), or returns null.
  static EraserConfig? fromJson(Object? json) {
    if (json is! Map<String, Object?>) return null;
    final mode = EraserMode.values.asNameMap()[json['mode']];
    final r = json['radius'], h = json['highlighterOnly'];
    if (mode == null || r is! num || !(r >= minRadius && r <= maxRadius)) return null;
    if (h is! bool) return null;
    return EraserConfig(mode: mode, radius: r.toDouble(), highlighterOnly: h);
  }

  @override
  bool operator ==(Object other) =>
      other is EraserConfig &&
      other.mode == mode &&
      other.radius == radius &&
      other.highlighterOnly == highlighterOnly;

  @override
  int get hashCode => Object.hash(mode, radius, highlighterOnly);
}
