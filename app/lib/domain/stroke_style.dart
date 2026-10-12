import 'stroke.dart';

/// Per-stroke rendering parameters, stored with the stroke so it renders
/// identically on every device regardless of the local tool settings.
class StrokeStyle {
  const StrokeStyle({
    this.opacity = 1,
    this.thinning = 0.5,
    this.streamline = 0.4,
    this.taperStart = 0,
    this.taperEnd = 0,
    this.unit = 0,
  });

  /// Overall ink opacity, 0..1 (the stroke colour itself is stored opaque).
  final double opacity;

  /// How strongly pressure changes the width, 0 (none) .. 1 (strong).
  final double thinning;

  /// Stabiliser: how much input jitter is smoothed away, 0..1.
  final double streamline;

  /// Length (world units) over which the start / end of the stroke tapers
  /// to a point; 0 means a round, untapered end.
  final double taperStart;
  final double taperEnd;

  /// World units per screen pixel when the stroke was written (the inverse
  /// of the zoom), 0 when unknown. Digitiser jitter and pen hooks are
  /// screen-sized, so the outline smooths at this scale; without it, the
  /// scale is estimated from the points' spacing (`StrokeOutline.unitOf`).
  final double unit;

  /// The style of a stroke of [tool] created without one (generated
  /// content, tests).
  static StrokeStyle defaultsFor(InkTool tool) => switch (tool) {
    InkTool.highlighter => const StrokeStyle(opacity: 0.35, thinning: 0, streamline: 0.5),
    InkTool.ballpoint => const StrokeStyle(),
  };

  StrokeStyle copyWith({
    double? opacity,
    double? thinning,
    double? streamline,
    double? taperStart,
    double? taperEnd,
    double? unit,
  }) => StrokeStyle(
    opacity: opacity ?? this.opacity,
    thinning: thinning ?? this.thinning,
    streamline: streamline ?? this.streamline,
    taperStart: taperStart ?? this.taperStart,
    taperEnd: taperEnd ?? this.taperEnd,
    unit: unit ?? this.unit,
  );

  /// Compact JSON for storage and sync.
  Map<String, Object?> toJson() => {
    'o': opacity,
    'th': thinning,
    'sl': streamline,
    if (taperStart > 0) 'ts': taperStart,
    if (taperEnd > 0) 'te': taperEnd,
    if (unit > 0) 'u': unit,
  };

  /// Parses [json] strictly: `o`, `th` and `sl` are required, in 0..1;
  /// `ts`, `te` and `u` are omitted when 0. Throws [FormatException] when
  /// malformed. Unknown fields are ignored.
  static StrokeStyle fromJson(Object? json) {
    if (json is! Map) throw const FormatException('Malformed stroke style');
    double read(String key, double max, {bool required = false}) {
      final v = json[key];
      if (v == null && !required) return 0;
      if (v is num && v.isFinite && v >= 0 && v <= max) return v.toDouble();
      throw FormatException('Malformed stroke style: $key');
    }

    return StrokeStyle(
      opacity: read('o', 1, required: true),
      thinning: read('th', 1, required: true),
      streamline: read('sl', 1, required: true),
      taperStart: read('ts', 1e4),
      taperEnd: read('te', 1e4),
      unit: read('u', 1e6),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is StrokeStyle &&
      other.opacity == opacity &&
      other.thinning == thinning &&
      other.streamline == streamline &&
      other.taperStart == taperStart &&
      other.taperEnd == taperEnd &&
      other.unit == unit;

  @override
  int get hashCode => Object.hash(opacity, thinning, streamline, taperStart, taperEnd, unit);

  @override
  String toString() => 'StrokeStyle(${toJson()})';
}
