import 'dart:ui' show TextDirection;

import 'paragraph_direction.dart';
import 'paragraph_style.dart';
import 'span_style.dart';
import 'text_alignment.dart';
import 'text_flow.dart';
import 'text_font.dart';

export 'paragraph_style.dart';
export 'span_style.dart';
export 'text_alignment.dart';
export 'text_flow.dart';
export 'text_font.dart';

/// The content and formatting of a text element (`SurfaceElement.data` of
/// type `text`): plain [text] (lines separated by `\n`), character
/// formatting as [spans] over it, one [ParaStyle] per line, and the box's
/// defaults ([font], [fontSize], [color]) that unformatted text uses.
///
/// Keeping the plain text whole makes it directly searchable (the search
/// index reads `data.text`). Spans are kept normalised: sorted,
/// non-overlapping, non-empty, never plain, and adjacent equal spans
/// merged; [paras] has exactly one entry per line. [TextData.fromJson]
/// tolerates malformed values (it reads rows this app wrote); records from
/// elsewhere are checked by [TextRecord.parse] first (see SYNC_PROTOCOL.md).
class TextData {
  /// A box of plain [text]. Use [TextData.rich] for formatted text.
  const TextData({
    this.text = '',
    this.font = TextFont.inter,
    this.fontSize = 24,
    this.color = defaultColor,
    this.align = TextAlignment.start,
    this.autoWidth = false,
  }) : spans = const [],
       _paras = const [],
       flow = null;

  TextData._(
    this.text,
    this.spans,
    this._paras, {
    required this.font,
    required this.fontSize,
    required this.color,
    required this.align,
    required this.autoWidth,
    this.flow,
  });

  /// Formatted text; [spans] and [paras] are normalised.
  factory TextData.rich({
    required String text,
    List<StyledRange> spans = const [],
    List<ParaStyle> paras = const [],
    TextFont font = TextFont.inter,
    double fontSize = 24,
    int color = defaultColor,
    TextAlignment align = TextAlignment.start,
    bool autoWidth = false,
    TextFlow? flow,
  }) => TextData._(
    text,
    StyledRange.normalize(spans, text.length),
    ParaStyle.normalize(paras, text),
    font: font,
    fontSize: fontSize.clamp(minFontSize, maxFontSize),
    color: color,
    align: align,
    autoWidth: autoWidth,
    flow: flow,
  );

  static const int defaultColor = 0xFF1A2233;
  static const double minFontSize = 6;
  static const double maxFontSize = 400;

  final String text;

  /// Character formatting (see the class doc).
  final List<StyledRange> spans;
  final List<ParaStyle> _paras;

  /// The box font, used where no span sets one.
  final TextFont font;

  /// Body font size in world units, used where no span sets one.
  final double fontSize;

  /// ARGB colour of text without a span colour.
  final int color;
  final TextAlignment align;

  /// Whether the box is as wide as its text (it grows while typing) rather
  /// than wrapping at a width the user chose.
  final bool autoWidth;

  /// Set on a box continuing another one from the page before (see
  /// [TextFlow]); null on a box of its own and on the first of a chain.
  final TextFlow? flow;

  /// A copy continuing as [flow] says (null: standing on its own).
  TextData withFlow(TextFlow? flow) => TextData._(
    text,
    spans,
    _paras,
    font: font,
    fontSize: fontSize,
    color: color,
    align: align,
    autoWidth: autoWidth,
    flow: flow,
  );

  /// The direction of each paragraph (see [ParagraphDirection]); a box
  /// continuing another keeps its first paragraph's from the whole text
  /// ([TextFlow.direction]).
  List<TextDirection> get directions => ParagraphDirection.of(text, first: flow?.direction);

  /// One style per line of [text].
  List<ParaStyle> get paras {
    final lines = lineCount;
    if (_paras.length == lines) return _paras;
    return [for (var i = 0; i < lines; i++) i < _paras.length ? _paras[i] : ParaStyle.body];
  }

  int get lineCount => '\n'.allMatches(text).length + 1;

  /// Whether any character or paragraph formatting is set.
  bool get isRich => spans.isNotEmpty || _paras.any((p) => p != ParaStyle.body);

  factory TextData.fromJson(Map<String, Object?> json) {
    final size = json['size'];
    final color = json['color'];
    final text = json['text'] is String ? json['text']! as String : '';
    final spans = [
      if (json['spans'] case final List<Object?> list)
        for (final s in list) ?StyledRange.tryParse(s),
    ];
    final paras = json['paras'] is List
        ? [for (final p in json['paras']! as List) ParaStyle.fromJson(p)]
        : const <ParaStyle>[];
    return TextData.rich(
      text: text,
      spans: spans,
      paras: paras,
      font: TextFont.parse(json['font']),
      fontSize: size is num && size.isFinite ? size.toDouble() : 24,
      color: color is int ? color : defaultColor,
      align: TextAlignment.tryParse(json['align']) ?? TextAlignment.start,
      autoWidth: json['autoWidth'] == true,
      flow: TextFlow.fromJson(json['flow']),
    );
  }

  /// Merges into [base] so unknown keys written by newer clients survive
  /// an edit made here.
  Map<String, Object?> toJson([Map<String, Object?> base = const {}]) => {
    for (final e in base.entries)
      if (e.key != 'flow') e.key: e.value,
    'text': text,
    'spans': [for (final s in spans) s.toJson()],
    'paras': [for (final p in _paras) p.toJson()],
    'font': font.name,
    'size': fontSize,
    'color': color,
    'align': align.name,
    'autoWidth': autoWidth,
    if (flow case final flow?) 'flow': flow.toJson(),
  };

  /// A copy with other box defaults. Changing [text] drops the formatting
  /// (use [TextData.rich] to keep some).
  TextData copyWith({
    String? text,
    TextFont? font,
    double? fontSize,
    int? color,
    TextAlignment? align,
    bool? autoWidth,
  }) {
    final same = text == null || text == this.text;
    return TextData._(
      text ?? this.text,
      same ? spans : const [],
      same ? _paras : const [],
      font: font ?? this.font,
      fontSize: (fontSize ?? this.fontSize).clamp(minFontSize, maxFontSize),
      color: color ?? this.color,
      align: align ?? this.align,
      autoWidth: autoWidth ?? this.autoWidth,
      flow: flow,
    );
  }

  /// The same formatting with other [spans] / [paras].
  TextData withFormatting({List<StyledRange>? spans, List<ParaStyle>? paras}) => TextData.rich(
    text: text,
    spans: spans ?? this.spans,
    paras: paras ?? this.paras,
    font: font,
    fontSize: fontSize,
    color: color,
    align: align,
    autoWidth: autoWidth,
    flow: flow,
  );

  /// Every size (the box's and the spans') scaled by [factor], so the
  /// text keeps its proportions (lasso resize, "Size" on a selection).
  TextData scaled(double factor) {
    if (factor == 1) return this;
    double clamp(double v) => (v * factor).clamp(minFontSize, maxFontSize);
    return TextData._(
      text,
      [
        for (final s in spans)
          s.style.size == null
              ? s
              : StyledRange(s.start, s.end, s.style.withSize(clamp(s.style.size!))),
      ],
      _paras,
      font: font,
      fontSize: clamp(fontSize),
      color: color,
      align: align,
      autoWidth: autoWidth,
      flow: flow,
    );
  }

  /// The box set to [size]: other sizes in it scale along.
  TextData withFontSize(double size) => scaled(size.clamp(minFontSize, maxFontSize) / fontSize);

  /// All text in [argb]: span colours are dropped.
  TextData withColor(int argb) => TextData.rich(
    text: text,
    spans: [for (final s in spans) StyledRange(s.start, s.end, s.style.withColor(null))],
    paras: paras,
    font: font,
    fontSize: fontSize,
    color: argb,
    align: align,
    autoWidth: autoWidth,
    flow: flow,
  );

  /// All text in [value]: span fonts are dropped.
  TextData withFont(TextFont value) => TextData.rich(
    text: text,
    spans: [for (final s in spans) StyledRange(s.start, s.end, s.style.withFont(null))],
    paras: paras,
    font: value,
    fontSize: fontSize,
    color: color,
    align: align,
    autoWidth: autoWidth,
    flow: flow,
  );

  /// The style of every UTF-16 unit of [text].
  List<SpanStyle> charStyles() {
    final styles = List<SpanStyle>.filled(text.length, SpanStyle.plain);
    for (final s in spans) {
      styles.fillRange(s.start, s.end, s.style);
    }
    return styles;
  }

  @override
  bool operator ==(Object other) =>
      other is TextData &&
      other.text == text &&
      other.font == font &&
      other.fontSize == fontSize &&
      other.color == color &&
      other.align == align &&
      other.autoWidth == autoWidth &&
      other.flow == flow &&
      _listEquals(other.spans, spans) &&
      _listEquals(other.paras, paras);

  @override
  int get hashCode => Object.hash(
    text,
    font,
    fontSize,
    color,
    align,
    autoWidth,
    flow,
    Object.hashAll(spans),
    Object.hashAll(paras),
  );

  static bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
