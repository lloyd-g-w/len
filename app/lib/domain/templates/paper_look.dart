import 'dart:ui';

/// How a template is drawn, beyond its style: pattern spacing, line weight,
/// dot size, pattern colour and opacity, the margin line and a header area.
/// Part of a page's [Paper] (and of a notebook's, for canvases and new
/// pages); stored and synced in `paperData.look`.
///
/// Settings a template has no use for (dot size on ruled paper, spacing of
/// a planner) are kept but ignored.
class PaperLook {
  const PaperLook({
    this.spacing,
    this.lineWeight = 1,
    this.dotSize = 1,
    this.patternColor,
    this.patternOpacity = 1,
    this.margin = true,
    this.header = false,
  });

  static const PaperLook standard = PaperLook();

  /// Pattern pitch in millimetres (line distance, grid cell, dot spacing,
  /// staff line distance); null keeps the template's own.
  final double? spacing;

  /// Line thickness relative to the default ([minScale] … [maxScale]).
  final double lineWeight;

  /// Dot size relative to the default ([minScale] … [maxScale]).
  final double dotSize;

  /// Colour (opaque ARGB) of lines, dots and printed text; null follows
  /// the paper colour.
  final int? patternColor;

  /// Opacity of the pattern ([minOpacity] … 1).
  final double patternOpacity;

  /// Whether ruled pages have their red margin line.
  final bool margin;

  /// Whether pages have a header area: a band at the top for a title,
  /// ruled off, with the pattern below it.
  final bool header;

  static const double minScale = 0.5, maxScale = 3;
  static const double minOpacity = 0.1;
  static const double minSpacing = 1.5, maxSpacing = 25;

  /// World units (96 per inch) per millimetre.
  static const double unitsPerMm = 96 / 25.4;

  bool get isStandard => this == standard;

  PaperLook copyWith({
    double? spacing,
    bool clearSpacing = false,
    double? lineWeight,
    double? dotSize,
    int? patternColor,
    bool clearPatternColor = false,
    double? patternOpacity,
    bool? margin,
    bool? header,
  }) => PaperLook(
    spacing: clearSpacing ? null : spacing ?? this.spacing,
    lineWeight: lineWeight ?? this.lineWeight,
    dotSize: dotSize ?? this.dotSize,
    patternColor: clearPatternColor ? null : patternColor ?? this.patternColor,
    patternOpacity: patternOpacity ?? this.patternOpacity,
    margin: margin ?? this.margin,
    header: header ?? this.header,
  );

  /// The pattern colour on paper whose own pattern colour is [paperPattern].
  Color patternOn(Color paperPattern) {
    final base = patternColor == null ? paperPattern : Color(patternColor!);
    return base.withValues(alpha: base.a * patternOpacity);
  }

  Map<String, Object?> toJson() => {
    'spacing': spacing,
    'lineWeight': lineWeight,
    'dotSize': dotSize,
    'patternColor': patternColor,
    'patternOpacity': patternOpacity,
    'margin': margin,
    'header': header,
  };

  /// Parses [toJson] output; null when a field is missing or has the wrong
  /// type. Numbers out of range are clamped.
  static PaperLook? fromJson(Object? json) {
    if (json is! Map) return null;
    const keys = ['spacing', 'lineWeight', 'dotSize', 'patternColor', 'patternOpacity'];
    if (!keys.every(json.containsKey)) return null;
    final spacing = json['spacing'];
    final lineWeight = json['lineWeight'];
    final dotSize = json['dotSize'];
    final patternColor = json['patternColor'];
    final opacity = json['patternOpacity'];
    final margin = json['margin'];
    final header = json['header'];
    if ((spacing != null && spacing is! num) ||
        lineWeight is! num ||
        dotSize is! num ||
        (patternColor != null && patternColor is! int) ||
        opacity is! num ||
        margin is! bool ||
        header is! bool) {
      return null;
    }
    return PaperLook(
      spacing: (spacing as num?)?.toDouble().clamp(minSpacing, maxSpacing),
      lineWeight: lineWeight.toDouble().clamp(minScale, maxScale),
      dotSize: dotSize.toDouble().clamp(minScale, maxScale),
      patternColor: patternColor == null ? null : (patternColor as int) | 0xFF000000,
      patternOpacity: opacity.toDouble().clamp(minOpacity, 1),
      margin: margin,
      header: header,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is PaperLook &&
      other.spacing == spacing &&
      other.lineWeight == lineWeight &&
      other.dotSize == dotSize &&
      other.patternColor == patternColor &&
      other.patternOpacity == patternOpacity &&
      other.margin == margin &&
      other.header == header;

  @override
  int get hashCode =>
      Object.hash(spacing, lineWeight, dotSize, patternColor, patternOpacity, margin, header);

  @override
  String toString() => 'PaperLook(${toJson()})';
}
