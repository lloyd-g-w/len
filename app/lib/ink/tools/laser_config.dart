import 'package:flutter/foundation.dart' show listEquals;

import '../../domain/stroke.dart';
import '../pen/pen_ends.dart';
import 'laser_config_json.dart';

export '../pen/pen_ends.dart';

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

/// The laser pointer's customisation (persisted with the tool settings):
/// like an ink's, quick colours and quick sizes — independent rows of
/// [minSlots]..[maxSlots] slots, one of each selected — plus how it shows
/// (dot or trail) and fades, and the pen's feel for the trail: pressure
/// sensitivity, stabiliser and ends (the trail is shaped by the pen's
/// engine, `LaserStroke`). Immutable; `ToolSettings` swaps configs.
class LaserConfig {
  const LaserConfig({
    this.mode = LaserMode.trail,
    this.colors = defaultColors,
    this.colorIndex = 0,
    this.sizes = defaultSizes,
    this.sizeIndex = defaultSizeIndex,
    this.duration = defaultDuration,
    this.fade = LaserFade.stroke,
    this.hold = defaultHold,
    this.thinning = 0,
    this.streamline = 0,
    this.ends = defaultEnds,
  });

  /// The trail's ends at first: flat, as the trail always ended (the dot
  /// covers the end while pointing).
  static const PenEnds defaultEnds = PenEnds(style: StrokeEnds.flat);

  /// The end styles offered: the pen's three.
  static const List<StrokeEnds> endStyles = [StrokeEnds.round, StrokeEnds.tapered, StrokeEnds.flat];

  /// The quick colours at first: red, green and blue.
  static const List<int> defaultColors = [0xFFFF2D2D, 0xFF2BD957, 0xFF2F8BFF];

  /// The quick sizes at first, the middle one selected.
  static const List<double> defaultSizes = [4, 6, 10];
  static const int defaultSizeIndex = 1;

  static const Duration defaultDuration = Duration(milliseconds: 1000);
  static const Duration defaultHold = Duration(milliseconds: 2000);

  /// Fewest and most slots in each row (as an ink's).
  static const int minSlots = 1;
  static const int maxSlots = 5;

  /// Width of the bright core on screen (logical pixels).
  static const double minSize = 3, maxSize = 16;

  /// How long the trail lasts.
  static const Duration minDuration = Duration(milliseconds: 300);
  static const Duration maxDuration = Duration(milliseconds: 3000);

  /// How long the trail stays after the last lift ([LaserFade.pause]).
  static const Duration minHold = Duration(milliseconds: 500);
  static const Duration maxHold = Duration(milliseconds: 5000);

  /// The colour palette: red, orange, yellow, green, blue, magenta.
  static const List<int> presets = [
    0xFFFF2D2D,
    0xFFFF8A00,
    0xFFFFD60A,
    0xFF2BD957,
    0xFF2F8BFF,
    0xFFE83CFF,
  ];

  final LaserMode mode;

  /// Quick colours (opaque ARGB) and sizes (width of the bright core on
  /// screen, logical pixels, [minSize]..[maxSize]).
  final List<int> colors;
  final List<double> sizes;

  /// The selected colour and size slots.
  final int colorIndex;
  final int sizeIndex;

  /// How long a point of the trail stays visible ([LaserFade.stroke]).
  final Duration duration;

  /// When the trail fades.
  final LaserFade fade;

  /// How long the whole trail stays after the last lift before it fades
  /// ([LaserFade.pause]).
  final Duration hold;

  /// Pressure sensitivity of the trail's width (0..1, as the pen's
  /// `PenConfig.thinning`; 0: one width).
  final double thinning;

  /// Stabiliser strength of the trail (0..1, as the pen's
  /// `PenConfig.streamline`).
  final double streamline;

  /// The trail's ends (round, flat or tapered, as the pen's).
  final PenEnds ends;

  /// The selected colour (opaque ARGB) and size.
  int get color => colors[colorIndex];
  double get size => sizes[sizeIndex];

  LaserConfig copyWith({
    LaserMode? mode,
    List<int>? colors,
    int? colorIndex,
    List<double>? sizes,
    int? sizeIndex,
    Duration? duration,
    LaserFade? fade,
    Duration? hold,
    double? thinning,
    double? streamline,
    PenEnds? ends,
  }) => LaserConfig(
    mode: mode ?? this.mode,
    colors: colors ?? this.colors,
    colorIndex: colorIndex ?? this.colorIndex,
    sizes: sizes ?? this.sizes,
    sizeIndex: sizeIndex ?? this.sizeIndex,
    duration: duration ?? this.duration,
    fade: fade ?? this.fade,
    hold: hold ?? this.hold,
    thinning: thinning ?? this.thinning,
    streamline: streamline ?? this.streamline,
    ends: ends ?? this.ends,
  );

  /// A copy with the defaults of everything but the quick slots (what
  /// Reset restores: the slots are the user's choices, as an ink's).
  LaserConfig withFeelDefaults() => const LaserConfig().copyWith(
    colors: colors,
    colorIndex: colorIndex,
    sizes: sizes,
    sizeIndex: sizeIndex,
  );

  /// A copy with colour slot [index] set to [argb] (made opaque).
  LaserConfig withColor(int index, int argb) =>
      copyWith(colors: [...colors]..[index] = argb | 0xFF000000);

  /// A copy with size slot [index] set to [size] (clamped to the range).
  LaserConfig withSize(int index, double size) =>
      copyWith(sizes: [...sizes]..[index] = size.clamp(minSize, maxSize));

  /// A copy with [argb] appended as a new, selected colour slot (unchanged
  /// when the row is full).
  LaserConfig addColor(int argb) => colors.length >= maxSlots
      ? this
      : copyWith(colors: [...colors, argb | 0xFF000000], colorIndex: colors.length);

  /// A copy with [size] appended as a new, selected size slot.
  LaserConfig addSize(double size) => sizes.length >= maxSlots
      ? this
      : copyWith(sizes: [...sizes, size.clamp(minSize, maxSize)], sizeIndex: sizes.length);

  /// A copy without colour slot [index] (the last slot is never removed).
  LaserConfig removeColor(int index) {
    if (colors.length <= minSlots || index < 0 || index >= colors.length) return this;
    return copyWith(
      colors: [...colors]..removeAt(index),
      colorIndex: _afterRemoval(colorIndex, index),
    );
  }

  /// A copy without size slot [index] (the last slot is never removed).
  LaserConfig removeSize(int index) {
    if (sizes.length <= minSlots || index < 0 || index >= sizes.length) return this;
    return copyWith(sizes: [...sizes]..removeAt(index), sizeIndex: _afterRemoval(sizeIndex, index));
  }

  static int _afterRemoval(int selected, int removed) =>
      selected > removed || (selected == removed && selected > 0) ? selected - 1 : selected;

  Map<String, Object?> toJson() => {
    'mode': mode.name,
    'colors': colors,
    'color': colorIndex,
    'sizes': sizes,
    'size': sizeIndex,
    'duration': duration.inMilliseconds,
    'fade': fade.name,
    'hold': hold.inMilliseconds,
    'thinning': thinning,
    'streamline': streamline,
    'ends': ends.toJson(),
  };

  /// Reads [toJson] output; a part missing or malformed takes its default
  /// (the quick colours with their selection, the sizes with theirs).
  static LaserConfig fromJson(Object? json) => LaserConfigJson.parse(json);

  @override
  bool operator ==(Object other) =>
      other is LaserConfig &&
      other.mode == mode &&
      listEquals(other.colors, colors) &&
      other.colorIndex == colorIndex &&
      listEquals(other.sizes, sizes) &&
      other.sizeIndex == sizeIndex &&
      other.duration == duration &&
      other.fade == fade &&
      other.hold == hold &&
      other.thinning == thinning &&
      other.streamline == streamline &&
      other.ends == ends;

  @override
  int get hashCode => Object.hash(
    mode,
    Object.hashAll(colors),
    colorIndex,
    Object.hashAll(sizes),
    sizeIndex,
    duration,
    fade,
    hold,
    thinning,
    streamline,
    ends,
  );
}
