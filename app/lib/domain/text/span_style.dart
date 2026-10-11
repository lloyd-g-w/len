import 'text_font.dart';

/// Character formatting of a stretch of text in a text box. Null fields
/// inherit from the box (`TextData`): its font, size and colour.
///
/// Stored compactly (only set attributes): `b` bold, `i` italic,
/// `u` underline, `s` strikethrough (booleans, present only when true),
/// `c` colour and `hl` highlight (ARGB ints), `sz` size (world units),
/// `f` font ([TextFont.name]).
class SpanStyle {
  const SpanStyle({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strike = false,
    this.color,
    this.highlight,
    this.size,
    this.font,
  });

  static const SpanStyle plain = SpanStyle();

  final bool bold;
  final bool italic;
  final bool underline;
  final bool strike;

  /// ARGB text colour; null = the box colour.
  final int? color;

  /// ARGB background (highlighter) colour; null = none.
  final int? highlight;

  /// Font size in world units; null = the box size (scaled for headings).
  final double? size;

  /// Font; null = the box font.
  final TextFont? font;

  bool get isPlain => this == plain;

  factory SpanStyle.fromJson(Map<Object?, Object?> json) {
    final size = json['sz'];
    final color = json['c'], highlight = json['hl'];
    return SpanStyle(
      bold: json['b'] == true,
      italic: json['i'] == true,
      underline: json['u'] == true,
      strike: json['s'] == true,
      color: color is int ? color : null,
      highlight: highlight is int ? highlight : null,
      size: size is num && size.isFinite && size > 0 ? size.toDouble() : null,
      font: TextFont.tryParse(json['f']),
    );
  }

  Map<String, Object?> toJson() => {
    if (bold) 'b': true,
    if (italic) 'i': true,
    if (underline) 'u': true,
    if (strike) 's': true,
    'c': ?color,
    'hl': ?highlight,
    'sz': ?size,
    'f': ?font?.name,
  };

  SpanStyle copyWith({bool? bold, bool? italic, bool? underline, bool? strike}) => SpanStyle(
    bold: bold ?? this.bold,
    italic: italic ?? this.italic,
    underline: underline ?? this.underline,
    strike: strike ?? this.strike,
    color: color,
    highlight: highlight,
    size: size,
    font: font,
  );

  SpanStyle withColor(int? value) => _with(color: () => value);
  SpanStyle withHighlight(int? value) => _with(highlight: () => value);
  SpanStyle withSize(double? value) => _with(size: () => value);
  SpanStyle withFont(TextFont? value) => _with(font: () => value);

  SpanStyle _with({
    int? Function()? color,
    int? Function()? highlight,
    double? Function()? size,
    TextFont? Function()? font,
  }) => SpanStyle(
    bold: bold,
    italic: italic,
    underline: underline,
    strike: strike,
    color: color == null ? this.color : color(),
    highlight: highlight == null ? this.highlight : highlight(),
    size: size == null ? this.size : size(),
    font: font == null ? this.font : font(),
  );

  @override
  bool operator ==(Object other) =>
      other is SpanStyle &&
      other.bold == bold &&
      other.italic == italic &&
      other.underline == underline &&
      other.strike == strike &&
      other.color == color &&
      other.highlight == highlight &&
      other.size == size &&
      other.font == font;

  @override
  int get hashCode => Object.hash(bold, italic, underline, strike, color, highlight, size, font);

  @override
  String toString() => 'SpanStyle(${toJson()})';
}

/// [style] applied to the UTF-16 range [start, end) of a text.
class StyledRange {
  const StyledRange(this.start, this.end, this.style);

  final int start;
  final int end;
  final SpanStyle style;

  /// Stored as `[start, end, {style}]`.
  List<Object?> toJson() => [start, end, style.toJson()];

  @override
  bool operator ==(Object other) =>
      other is StyledRange && other.start == start && other.end == end && other.style == style;

  @override
  int get hashCode => Object.hash(start, end, style);

  @override
  String toString() => 'StyledRange($start, $end, $style)';
}
