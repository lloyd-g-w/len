import 'dart:math' as math;

import 'text_data.dart';

/// An RTF paragraph's formatting, as read when its text started or ended.
class RtfPara {
  const RtfPara({
    required this.heading,
    required this.listed,
    required this.tableKind,
    required this.pn,
    required this.indent,
    required this.space,
  });

  /// 0, 1 or 2.
  final int heading;

  /// A list item (`\ls`, `\pn`), whatever its marker.
  final bool listed;

  /// The kind the list table gives (none: an item without a marker), or
  /// null where it doesn't tell.
  final ListKind? tableKind;

  /// The kind `\pn` numbering gives.
  final ListKind? pn;

  /// List nesting (0-based).
  final int indent;

  /// The larger of `\sa` and `\sb` (twips), or null.
  final int? space;
}

/// One line (paragraph) of RTF text being read.
class RtfLine {
  final text = StringBuffer();

  /// Each UTF-16 unit's style (no size yet).
  final styles = <SpanStyle>[];

  /// Each UTF-16 unit's font size (half points).
  final halves = <int>[];

  /// Its formatting: at its end (`\par`), else where its text started.
  RtfPara? para;

  /// The text of its list marker (`\listtext`), if any.
  StringBuffer? marker;

  bool get isEmpty => styles.isEmpty;
}

/// The lines RTF text makes, turned into a box's [TextData] ([result]).
class RtfLines {
  final _lines = [RtfLine()];

  RtfLine get current => _lines.last;

  /// Appends [text] in [style] at [half] points / 2 to the current line
  /// (no-break spaces as spaces); [para] tells the line's formatting
  /// unless its end does.
  void add(String text, SpanStyle style, int half, RtfPara Function() para) {
    final line = current;
    line.para ??= para();
    for (var i = 0; i < text.length; i++) {
      final c = text.codeUnitAt(i);
      if (c == 0xFEFF) continue;
      line.text.writeCharCode(c == 0xA0 ? 0x20 : c);
      line.styles.add(style);
      line.halves.add(half);
    }
  }

  /// A list marker group (`\listtext`) starts on the current line.
  void startMarker() => current.marker = StringBuffer();

  /// Text of the current line's list marker.
  void marker(String text) => current.marker?.write(text);

  /// Ends the current line (a paragraph formatted as [para]).
  void newLine(RtfPara para) {
    current.para = para;
    _lines.add(RtfLine());
  }

  /// The box: the lines but blank ones at either end, sizes relative to
  /// the body size (that of most characters) as the [box]'s, its font,
  /// colour, alignment and width; null when there is no text.
  TextData? result(TextData box) {
    var lines = _lines;
    var start = 0, end = lines.length;
    while (end > start && lines[end - 1].text.toString().trim().isEmpty) {
      end--;
    }
    while (start < end && lines[start].text.toString().trim().isEmpty) {
      start++;
    }
    if (start == end) return null;
    lines = lines.sublist(start, end);
    final paras = [for (final l in lines) _finalPara(l)];
    final body = _bodyHalf(lines, paras);
    final chars = <SpanStyle>[];
    for (final (i, l) in lines.indexed) {
      if (i > 0) chars.add(SpanStyle.plain);
      for (final (j, style) in l.styles.indexed) {
        final ratio = l.halves[j] / body;
        final sized = paras[i].heading == 0 && (ratio - 1).abs() > 0.1;
        chars.add(sized ? style.withSize(_size(box.fontSize * ratio)) : style);
      }
    }
    return TextData.rich(
      text: lines.map((l) => l.text.toString()).join('\n'),
      spans: StyledRange.compact(chars),
      paras: paras,
      font: box.font,
      fontSize: box.fontSize,
      color: box.color,
      align: box.align,
      autoWidth: box.autoWidth,
      spacing: _spacing(lines, body) ?? box.spacing,
    );
  }

  static double _size(double v) => (v < 10 ? (v * 2).round() / 2 : v.roundToDouble()).clamp(
    TextData.minFontSize,
    TextData.maxFontSize,
  );

  /// The size (half points) most characters of body lines have.
  static int _bodyHalf(List<RtfLine> lines, List<ParaStyle> paras) {
    final counts = <int, int>{};
    for (final (i, l) in lines.indexed) {
      if (paras[i].heading != 0) continue;
      for (final h in l.halves) {
        counts[h] = (counts[h] ?? 0) + 1;
      }
    }
    if (counts.isEmpty) return 24;
    return counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
  }

  /// The spacing nearest the space most paragraphs with text leave, or
  /// null where none sets one.
  static ParagraphSpacing? _spacing(List<RtfLine> lines, int bodyHalf) {
    final counts = <int, int>{};
    for (final l in lines) {
      final space = l.para?.space;
      if (l.isEmpty || space == null) continue;
      counts[space] = (counts[space] ?? 0) + 1;
    }
    if (counts.isEmpty) return null;
    final twips = counts.entries.reduce((a, b) => b.value > a.value ? b : a).key;
    return ParagraphSpacing.nearest(math.max(0, twips) / 10 / bodyHalf);
  }

  static ParaStyle _finalPara(RtfLine l) {
    final p = l.para;
    final marker = l.marker?.toString().trim();
    final markerKind = marker == null
        ? null
        : RegExp(r'^\(?[0-9a-zA-Z]{1,5}[.)]$').hasMatch(marker)
        ? ListKind.number
        : ListKind.bullet;
    if (p == null) {
      return markerKind == null ? ParaStyle.body : ParaStyle(list: markerKind);
    }
    final kind = p.tableKind ?? markerKind ?? p.pn ?? (p.listed ? ListKind.bullet : ListKind.none);
    return ParaStyle(heading: p.heading, list: kind, indent: kind == ListKind.none ? 0 : p.indent);
  }
}
