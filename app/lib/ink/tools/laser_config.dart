/// How the laser pointer shows: a dot under the pointer, or a dot that
/// leaves a fading trail.
enum LaserMode {
  dot('Dot'),
  trail('Trail');

  const LaserMode(this.label);

  final String label;

  static LaserMode parse(Object? name) =>
      values.firstWhere((m) => m.name == name, orElse: () => LaserMode.trail);
}

/// When a laser trail fades.
enum LaserFade {
  /// Each point fades [LaserConfig.duration] after it was drawn.
  stroke('Each stroke'),

  /// Everything stays while writing and fades together
  /// [LaserConfig.hold] after the last lift; writing again within that
  /// time keeps it all.
  pause('When I stop');

  const LaserFade(this.label);

  final String label;

  static LaserFade parse(Object? name) =>
      values.firstWhere((f) => f.name == name, orElse: () => LaserFade.stroke);
}

/// The laser pointer's customisation (persisted with the tool settings).
class LaserConfig {
  const LaserConfig({
    this.mode = LaserMode.trail,
    this.color = defaultColor,
    this.size = defaultSize,
    this.duration = defaultDuration,
    this.fade = LaserFade.stroke,
    this.hold = defaultHold,
  });

  static const int defaultColor = 0xFFFF2D2D;
  static const double defaultSize = 6;
  static const Duration defaultDuration = Duration(milliseconds: 1000);
  static const Duration defaultHold = Duration(milliseconds: 2000);

  /// Width of the bright core on screen (logical pixels).
  static const double minSize = 3, maxSize = 16;

  /// How long the trail lasts.
  static const Duration minDuration = Duration(milliseconds: 300);
  static const Duration maxDuration = Duration(milliseconds: 3000);

  /// How long the trail stays after the last lift ([LaserFade.pause]).
  static const Duration minHold = Duration(milliseconds: 500);
  static const Duration maxHold = Duration(milliseconds: 5000);

  /// The quick colours: red, orange, yellow, green, blue, magenta.
  static const List<int> presets = [
    0xFFFF2D2D,
    0xFFFF8A00,
    0xFFFFD60A,
    0xFF2BD957,
    0xFF2F8BFF,
    0xFFE83CFF,
  ];

  final LaserMode mode;

  /// Opaque ARGB.
  final int color;

  /// Width of the bright core on screen (logical pixels).
  final double size;

  /// How long a point of the trail stays visible ([LaserFade.stroke]).
  final Duration duration;

  /// When the trail fades.
  final LaserFade fade;

  /// How long the whole trail stays after the last lift before it fades
  /// ([LaserFade.pause]).
  final Duration hold;

  LaserConfig copyWith({
    LaserMode? mode,
    int? color,
    double? size,
    Duration? duration,
    LaserFade? fade,
    Duration? hold,
  }) => LaserConfig(
    mode: mode ?? this.mode,
    color: color ?? this.color,
    size: size ?? this.size,
    duration: duration ?? this.duration,
    fade: fade ?? this.fade,
    hold: hold ?? this.hold,
  );

  Map<String, Object?> toJson() => {
    'mode': mode.name,
    'color': color,
    'size': size,
    'duration': duration.inMilliseconds,
    'fade': fade.name,
    'hold': hold.inMilliseconds,
  };

  /// Reads [toJson] output; anything missing or malformed takes its default.
  static LaserConfig fromJson(Object? json) {
    if (json is! Map) return const LaserConfig();
    final size = json['size'];
    final duration = json['duration'];
    final color = json['color'];
    final hold = json['hold'];
    return LaserConfig(
      mode: LaserMode.parse(json['mode']),
      color: color is int ? color | 0xFF000000 : defaultColor,
      size: size is num ? size.toDouble().clamp(minSize, maxSize) : defaultSize,
      duration: duration is int
          ? Duration(
              milliseconds: duration.clamp(minDuration.inMilliseconds, maxDuration.inMilliseconds),
            )
          : defaultDuration,
      fade: LaserFade.parse(json['fade']),
      hold: hold is int
          ? Duration(milliseconds: hold.clamp(minHold.inMilliseconds, maxHold.inMilliseconds))
          : defaultHold,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is LaserConfig &&
      other.mode == mode &&
      other.color == color &&
      other.size == size &&
      other.duration == duration &&
      other.fade == fade &&
      other.hold == hold;

  @override
  int get hashCode => Object.hash(mode, color, size, duration, fade, hold);
}
