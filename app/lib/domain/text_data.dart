/// Horizontal alignment of a text box. Stored by [name].
enum TextAlignment {
  left,
  center,
  right;

  static TextAlignment parse(Object? value) =>
      values.firstWhere((a) => a.name == value, orElse: () => left);
}

/// The content and formatting of a text element (`SurfaceElement.data` of
/// type `text`). Parsing tolerates missing or malformed fields and ignores
/// unknown ones, so newer clients can add formatting.
class TextData {
  const TextData({
    this.text = '',
    this.fontSize = 24,
    this.color = 0xFF1F2937,
    this.bold = false,
    this.italic = false,
    this.align = TextAlignment.left,
  });

  final String text;

  /// Font size in world units.
  final double fontSize;

  /// ARGB colour.
  final int color;
  final bool bold;
  final bool italic;
  final TextAlignment align;

  static const double minFontSize = 6;
  static const double maxFontSize = 400;

  factory TextData.fromJson(Map<String, Object?> json) {
    final size = json['size'];
    final color = json['color'];
    return TextData(
      text: json['text'] is String ? json['text']! as String : '',
      fontSize: size is num && size.isFinite ? size.toDouble().clamp(minFontSize, maxFontSize) : 24,
      color: color is int ? color : 0xFF1F2937,
      bold: json['bold'] == true,
      italic: json['italic'] == true,
      align: TextAlignment.parse(json['align']),
    );
  }

  /// Merges into [base] so unknown keys written by newer clients survive
  /// an edit made here.
  Map<String, Object?> toJson([Map<String, Object?> base = const {}]) => {
    ...base,
    'text': text,
    'size': fontSize,
    'color': color,
    'bold': bold,
    'italic': italic,
    'align': align.name,
  };

  TextData copyWith({
    String? text,
    double? fontSize,
    int? color,
    bool? bold,
    bool? italic,
    TextAlignment? align,
  }) => TextData(
    text: text ?? this.text,
    fontSize: fontSize ?? this.fontSize,
    color: color ?? this.color,
    bold: bold ?? this.bold,
    italic: italic ?? this.italic,
    align: align ?? this.align,
  );

  @override
  bool operator ==(Object other) =>
      other is TextData &&
      other.text == text &&
      other.fontSize == fontSize &&
      other.color == color &&
      other.bold == bold &&
      other.italic == italic &&
      other.align == align;

  @override
  int get hashCode => Object.hash(text, fontSize, color, bold, italic, align);
}
