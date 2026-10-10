/// How the eraser removes ink.
enum EraserMode {
  /// Removes every stroke it touches, whole.
  stroke,

  /// Removes only the ink under the eraser, splitting strokes.
  pixel;

  static EraserMode parse(Object? value) =>
      values.firstWhere((m) => m.name == value, orElse: () => stroke);
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

  static EraserConfig fromJson(Object? json) {
    if (json is! Map) return const EraserConfig();
    final r = json['radius'], h = json['highlighterOnly'];
    return EraserConfig(
      mode: EraserMode.parse(json['mode']),
      radius: r is num && r.isFinite ? r.toDouble().clamp(minRadius, maxRadius) : 12,
      highlighterOnly: h is bool && h,
    );
  }
}
