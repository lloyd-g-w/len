import '../../domain/stroke.dart';
import 'pen_profile.dart';

/// One quick-pick toolbar slot: an opaque colour and a width.
class PenPreset {
  const PenPreset({required this.color, required this.width});

  /// Opaque ARGB colour (opacity is a per-pen setting).
  final int color;

  /// Nominal width in world units.
  final double width;

  PenPreset copyWith({int? color, double? width}) =>
      PenPreset(color: color ?? this.color, width: width ?? this.width);

  Map<String, Object?> toJson() => {'c': color, 'w': width};

  static PenPreset? fromJson(Object? json) {
    if (json is! Map) return null;
    final c = json['c'], w = json['w'];
    if (c is! int || w is! num || !w.isFinite || w <= 0) return null;
    return PenPreset(color: c | 0xFF000000, width: w.toDouble());
  }

  @override
  bool operator ==(Object other) =>
      other is PenPreset && other.color == color && other.width == width;

  @override
  int get hashCode => Object.hash(color, width);
}

/// The user's customisation of one pen type: three presets (one selected)
/// plus feel settings. Immutable; [ToolSettings] swaps whole configs.
class PenConfig {
  const PenConfig({
    required this.presets,
    this.selected = 0,
    required this.opacity,
    required this.thinning,
    required this.streamline,
    required this.taper,
  });

  /// Defaults for [tool] from its [PenProfile].
  factory PenConfig.defaultsFor(InkTool tool) {
    final p = PenProfile.of(tool);
    return PenConfig(
      presets: [for (final s in p.presets) PenPreset(color: s.color, width: s.width)],
      opacity: p.opacity,
      thinning: p.thinning,
      streamline: p.streamline,
      taper: p.taper,
    );
  }

  static const int presetCount = 3;

  final List<PenPreset> presets;
  final int selected;
  final double opacity;

  /// Pressure sensitivity (0..1).
  final double thinning;

  /// Stabiliser strength (0..1).
  final double streamline;

  /// Whether stroke ends taper to a point.
  final bool taper;

  PenPreset get current => presets[selected];

  PenConfig copyWith({
    List<PenPreset>? presets,
    int? selected,
    double? opacity,
    double? thinning,
    double? streamline,
    bool? taper,
  }) => PenConfig(
    presets: presets ?? this.presets,
    selected: selected ?? this.selected,
    opacity: opacity ?? this.opacity,
    thinning: thinning ?? this.thinning,
    streamline: streamline ?? this.streamline,
    taper: taper ?? this.taper,
  );

  /// A copy with preset [index] replaced.
  PenConfig withPreset(int index, PenPreset preset) =>
      copyWith(presets: [...presets]..[index] = preset);

  /// The style a new stroke drawn with this config and [width] gets.
  StrokeStyle styleFor(InkTool tool, double width) {
    final taperLength = taper ? width * PenProfile.of(tool).taperFactor : 0.0;
    return StrokeStyle(
      opacity: opacity,
      thinning: thinning,
      streamline: streamline,
      taperStart: taperLength,
      taperEnd: taperLength,
    );
  }

  Map<String, Object?> toJson() => {
    'presets': [for (final p in presets) p.toJson()],
    'selected': selected,
    'opacity': opacity,
    'thinning': thinning,
    'streamline': streamline,
    'taper': taper,
  };

  /// Parses leniently, taking anything missing or invalid from [fallback].
  static PenConfig fromJson(Object? json, PenConfig fallback) {
    if (json is! Map) return fallback;
    double unit(String key, double orElse) {
      final v = json[key];
      return v is num && v.isFinite ? v.toDouble().clamp(0.0, 1.0) : orElse;
    }

    final rawPresets = json['presets'];
    final presets = [
      for (var i = 0; i < presetCount; i++)
        (rawPresets is List && i < rawPresets.length ? PenPreset.fromJson(rawPresets[i]) : null) ??
            fallback.presets[i],
    ];
    final selected = json['selected'];
    final taper = json['taper'];
    return PenConfig(
      presets: presets,
      selected: selected is int && selected >= 0 && selected < presetCount
          ? selected
          : fallback.selected,
      opacity: unit('opacity', fallback.opacity),
      thinning: unit('thinning', fallback.thinning),
      streamline: unit('streamline', fallback.streamline),
      taper: taper is bool ? taper : fallback.taper,
    );
  }
}
