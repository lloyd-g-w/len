import 'text_data.dart';

/// Mutable formatted text while a text box is edited: the text, one
/// [SpanStyle] per UTF-16 unit and one [ParaStyle] per line. Pure logic
/// (no Flutter), so editing behaviours are unit-testable; the editor's
/// controller maps the field's edits onto it.
class RichTextBuffer {
  RichTextBuffer(TextData data)
    : _text = data.text,
      _chars = data.charStyles(),
      _paras = [...data.paras];

  String _text;
  List<SpanStyle> _chars;
  final List<ParaStyle> _paras;

  String get text => _text;
  List<ParaStyle> get paras => List.unmodifiable(_paras);
  int get length => _text.length;
  int get lineCount => _paras.length;

  /// The formatted text with [box]'s defaults.
  TextData toData(TextData box) => TextData.rich(
    text: _text,
    spans: TextData.compact(_chars),
    paras: _paras,
    font: box.font,
    fontSize: box.fontSize,
    color: box.color,
    align: box.align,
    autoWidth: box.autoWidth,
  );

  /// [start, end) as formatted text with [box]'s defaults (a copy): with
  /// the paragraph styles of the lines it touches, unless it is part of a
  /// single line (a word copied out of a heading is no heading). A copy
  /// ending at a line's start (taking the break before it) ends with an
  /// empty line of body text: that line's style stays behind.
  TextData slice(int start, int end, TextData box) {
    final first = lineOf(start), last = lineOf(end);
    final part = first == last && (start > lineStart(first) || end < lineEnd(first));
    final touched = last > first && end == lineStart(last);
    return TextData.rich(
      text: _text.substring(start, end),
      spans: TextData.compact(_chars.sublist(start, end)),
      paras: part
          ? const []
          : [..._paras.sublist(first, touched ? last : last + 1), if (touched) ParaStyle.body],
      font: box.font,
      fontSize: box.fontSize,
      color: box.color,
      align: box.align,
      autoWidth: box.autoWidth,
    );
  }

  SpanStyle charStyle(int offset) => _chars[offset];
  ParaStyle para(int line) => _paras[line];

  /// The line containing [offset] (a caret position).
  int lineOf(int offset) {
    var line = 0;
    for (var i = 0; i < offset && i < _text.length; i++) {
      if (_text.codeUnitAt(i) == 0x0A) line++;
    }
    return line;
  }

  /// Offset of the first character of [line].
  int lineStart(int line) {
    var start = 0;
    for (var l = 0; l < line; l++) {
      start = _text.indexOf('\n', start) + 1;
    }
    return start;
  }

  /// Offset of the end of [line] (before its `\n`).
  int lineEnd(int line) {
    final end = _text.indexOf('\n', lineStart(line));
    return end < 0 ? _text.length : end;
  }

  /// The style text typed at [offset] gets: that of the character before
  /// it on the same line, else the one after it, else plain.
  SpanStyle styleAt(int offset) {
    if (offset > 0 && _text.codeUnitAt(offset - 1) != 0x0A) return _chars[offset - 1];
    if (offset < _text.length && _text.codeUnitAt(offset) != 0x0A) return _chars[offset];
    return SpanStyle.plain;
  }

  /// Replaces [start, end) with [inserted], formatted as [style].
  ///
  /// Lines joined by deleting their `\n` keep the first line's paragraph
  /// style. Lines split by an inserted `\n` continue lists (unchecked, same
  /// indent) but not headings; a split at the very start of a line inserts
  /// the new lines above it, which keep the line's style (unchecked).
  void replace(int start, int end, String inserted, SpanStyle style) {
    assert(0 <= start && start <= end && end <= _text.length);
    final firstLine = lineOf(start);
    final removedBreaks = '\n'.allMatches(_text.substring(start, end)).length;
    final addedBreaks = '\n'.allMatches(inserted).length;
    final atLineStart = start == lineStart(firstLine) && start == end;
    _text = _text.replaceRange(start, end, inserted);
    _chars = [
      ..._chars.sublist(0, start),
      for (var i = 0; i < inserted.length; i++) style,
      ..._chars.sublist(end),
    ];
    final para = _paras[firstLine];
    _paras.removeRange(firstLine + 1, firstLine + 1 + removedBreaks);
    if (addedBreaks == 0) return;
    if (atLineStart) {
      // New lines above; the line keeps its style and moves down.
      _paras
        ..[firstLine] = para.copyWith(checked: false)
        ..insertAll(firstLine, List.filled(addedBreaks - 1, para.copyWith(checked: false)))
        ..insert(firstLine + addedBreaks, para);
    } else {
      _paras.insertAll(
        firstLine + 1,
        List.filled(addedBreaks, ParaStyle(list: para.list, indent: para.indent)),
      );
    }
  }

  /// Replaces [start, end) with [fragment]'s formatted text (pasted from
  /// another app): its character formatting over [base] (the font, size,
  /// colour and highlight at the caret, where the fragment sets none) and
  /// the paragraph styles of the lines it adds. The first line takes the
  /// fragment's style only if the paste fills it or goes above it, and that
  /// style is not body text (plain text pasted into a list item stays an
  /// item); a line pasted above keeps its own style. An [exact] fragment
  /// (Len's own copy, where unset means the box's default) keeps its
  /// characters' styles as they are.
  void insertRich(int start, int end, TextData fragment, SpanStyle base, {bool exact = false}) {
    final line = lineOf(start);
    final fills = start == lineStart(line) && end == lineEnd(lineOf(end));
    // Lines pasted at the start of a line go above it: it keeps its style.
    final above = start == end && start == lineStart(line) && !fills;
    replace(start, end, fragment.text, base);
    final styles = fragment.charStyles();
    for (var i = 0; i < styles.length; i++) {
      final s = styles[i];
      _chars[start + i] = exact
          ? s
          : SpanStyle(
              bold: s.bold,
              italic: s.italic,
              underline: s.underline,
              strike: s.strike,
              color: s.color ?? base.color,
              highlight: s.highlight ?? base.highlight,
              size: s.size ?? base.size,
              font: s.font ?? base.font,
            );
    }
    final paras = fragment.paras;
    final first = fills || (above && paras.length > 1);
    if (first && paras.first != ParaStyle.body) _paras[line] = paras.first;
    // A fragment ending in a break adds no text to its last line: that
    // line (the rest of the one pasted into) keeps its style.
    final keepLast = above || fragment.text.endsWith('\n');
    for (var k = 1; k < paras.length - (keepLast ? 1 : 0); k++) {
      _paras[line + k] = paras[k];
    }
  }

  /// Changes the style of the characters in [start, end).
  void updateChars(int start, int end, SpanStyle Function(SpanStyle) update) {
    for (var i = start; i < end; i++) {
      _chars[i] = update(_chars[i]);
    }
  }

  /// Whether every non-newline character in [start, end) passes [test]
  /// (false for a range without any).
  bool everyChar(int start, int end, bool Function(SpanStyle) test) {
    var any = false;
    for (var i = start; i < end; i++) {
      if (_text.codeUnitAt(i) == 0x0A) continue;
      if (!test(_chars[i])) return false;
      any = true;
    }
    return any;
  }

  /// Changes the paragraph style of lines [first]..[last] (inclusive).
  void updateParas(int first, int last, ParaStyle Function(ParaStyle) update) {
    for (var l = first; l <= last; l++) {
      _paras[l] = update(_paras[l]);
    }
  }

  /// Number shown before line [line] of a numbered list: its position
  /// among the consecutive numbered items at the same indent.
  int listNumber(int line) => listNumberOf(_paras, line);

  /// [listNumber] over any paragraph list.
  static int listNumberOf(List<ParaStyle> paras, int line) {
    final p = paras[line];
    var n = 1;
    for (var l = line - 1; l >= 0; l--) {
      final q = paras[l];
      if (!q.isList || q.indent < p.indent) break;
      if (q.indent > p.indent) continue;
      if (q.list != ListKind.number) break;
      n++;
    }
    return n;
  }
}
