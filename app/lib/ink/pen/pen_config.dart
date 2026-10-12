import 'package:flutter/foundation.dart' show listEquals;

import '../../domain/stroke.dart';
import 'pen_config_json.dart';
import 'pen_defaults.dart';
import 'pen_ends.dart';

export 'pen_ends.dart';

/// The user's customisation of one ink (pen or highlighter): its quick
/// colours and quick widths — independent rows of slots, one of each
/// selected — plus feel settings. Immutable; `ToolSettings` swaps configs.
class PenConfig {
  const PenConfig({
    required this.colors,
    required this.widths,
    this.colorIndex = 0,
    this.widthIndex = 0,
    required this.opacity,
    required this.thinning,
    required this.streamline,
    this.straight = false,
    this.ends = const PenEnds(),
  }) : assert(colors.length > 0 && widths.length > 0);

  /// Defaults for [tool]: three colours and three widths.
  factory PenConfig.defaultsFor(InkTool tool) {
    final d = PenDefaults.of(tool);
    return PenConfig(
      colors: d.colors,
      widths: d.widths,
      widthIndex: 1,
      opacity: d.opacity,
      thinning: d.thinning,
      streamline: d.streamline,
    );
  }

  /// Fewest and most slots in each row.
  static const int minSlots = 1;
  static const int maxSlots = 6;

  /// Lowest opacity the highlighter can be set to, so it never vanishes.
  static const double minOpacity = 0.1;

  /// Quick colours (opaque ARGB) and widths (world units).
  final List<int> colors;
  final List<double> widths;

  /// The selected colour and width slots.
  final int colorIndex;
  final int widthIndex;

  /// Ink opacity ([minOpacity]..1); the pen is always opaque.
  final double opacity;

  /// Pressure sensitivity (0..1).
  final double thinning;

  /// Stabiliser strength (0..1).
  final double streamline;

  /// Every stroke is a straight line from pen-down to the pen (offered for
  /// the highlighter).
  final bool straight;

  /// The shape of the ends (offered for the pen; the highlighter's are
  /// flat).
  final PenEnds ends;

  /// The selected colour and width.
  int get color => colors[colorIndex];
  double get width => widths[widthIndex];

  /// A copy with the given fields replaced.
  PenConfig copyWith({
    List<int>? colors,
    List<double>? widths,
    int? colorIndex,
    int? widthIndex,
    double? opacity,
    double? thinning,
    double? streamline,
    bool? straight,
    PenEnds? ends,
  }) => PenConfig(
    colors: colors ?? this.colors,
    widths: widths ?? this.widths,
    colorIndex: colorIndex ?? this.colorIndex,
    widthIndex: widthIndex ?? this.widthIndex,
    opacity: opacity ?? this.opacity,
    thinning: thinning ?? this.thinning,
    streamline: streamline ?? this.streamline,
    straight: straight ?? this.straight,
    ends: ends ?? this.ends,
  );

  /// A copy with the feel settings (opacity, pressure sensitivity,
  /// stabiliser, straight lines, ends) of [tool]'s defaults, keeping the
  /// slots.
  PenConfig withFeelDefaults(InkTool tool) {
    final d = PenConfig.defaultsFor(tool);
    return copyWith(
      opacity: d.opacity,
      thinning: d.thinning,
      streamline: d.streamline,
      straight: d.straight,
      ends: d.ends,
    );
  }

  /// A copy with colour slot [index] set to [argb] (made opaque).
  PenConfig withColor(int index, int argb) =>
      copyWith(colors: [...colors]..[index] = argb | 0xFF000000);

  /// A copy with width slot [index] set to [width].
  PenConfig withWidth(int index, double width) => copyWith(widths: [...widths]..[index] = width);

  /// A copy with [argb] appended as a new, selected colour slot (unchanged
  /// when the row is full).
  PenConfig addColor(int argb) => colors.length >= maxSlots
      ? this
      : copyWith(colors: [...colors, argb | 0xFF000000], colorIndex: colors.length);

  /// A copy with [width] appended as a new, selected width slot.
  PenConfig addWidth(double width) => widths.length >= maxSlots
      ? this
      : copyWith(widths: [...widths, width], widthIndex: widths.length);

  /// A copy without colour slot [index] (the last slot is never removed).
  PenConfig removeColor(int index) {
    if (colors.length <= minSlots || index < 0 || index >= colors.length) return this;
    return copyWith(
      colors: [...colors]..removeAt(index),
      colorIndex: _afterRemoval(colorIndex, index),
    );
  }

  /// A copy without width slot [index] (the last slot is never removed).
  PenConfig removeWidth(int index) {
    if (widths.length <= minSlots || index < 0 || index >= widths.length) return this;
    return copyWith(
      widths: [...widths]..removeAt(index),
      widthIndex: _afterRemoval(widthIndex, index),
    );
  }

  static int _afterRemoval(int selected, int removed) =>
      selected > removed || (selected == removed && selected > 0) ? selected - 1 : selected;

  /// The style a new stroke of [tool] drawn with this config gets (a
  /// straight line needs no stabiliser; the highlighter's ends are its
  /// own).
  StrokeStyle styleFor(InkTool tool) {
    final style = StrokeStyle(
      opacity: tool.isHighlighter ? opacity : 1,
      thinning: thinning,
      streamline: straight ? 0 : streamline,
    );
    return tool.isHighlighter ? style : ends.applyTo(style);
  }

  /// JSON for the local settings store (see [fromJson]).
  Map<String, Object?> toJson() => {
    'colors': colors,
    'widths': widths,
    'color': colorIndex,
    'width': widthIndex,
    'opacity': opacity,
    'thinning': thinning,
    'streamline': streamline,
    'straight': straight,
    'ends': ends.toJson(),
  };

  /// Parses the config of [tool] strictly (every field present and valid),
  /// or returns null.
  static PenConfig? fromJson(Object? json, {required InkTool tool}) =>
      PenConfigJson.parse(json, tool: tool);

  @override
  bool operator ==(Object other) =>
      other is PenConfig &&
      listEquals(other.colors, colors) &&
      listEquals(other.widths, widths) &&
      other.colorIndex == colorIndex &&
      other.widthIndex == widthIndex &&
      other.opacity == opacity &&
      other.thinning == thinning &&
      other.streamline == streamline &&
      other.straight == straight &&
      other.ends == ends;

  @override
  int get hashCode => Object.hash(
    Object.hashAll(colors),
    Object.hashAll(widths),
    colorIndex,
    widthIndex,
    opacity,
    thinning,
    streamline,
    straight,
    ends,
  );
}
