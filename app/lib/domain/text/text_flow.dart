import 'dart:ui' show TextDirection;

import 'rich_text_buffer.dart';
import 'table_cells.dart';
import 'text_data.dart';

/// A cell of a table's header row as repeated on a page the table goes on
/// to ([TextFlow.header]): its text and character formatting.
typedef RepeatedCell = ({String text, List<StyledRange> spans});

/// How a text box continues the box before it in a chain of boxes that
/// flows across the pages of a notebook (`TextData.flow`): a box reaching
/// the bottom of its page continues at the top of the next page.
///
/// The first box of a chain (its head) has no flow; each continuation
/// names the box it continues ([from], on the page before). Every box holds
/// its own part of the text, so a page draws, searches and exports on its
/// own; [joined], [numbers] and [direction] make that part look as it does
/// in the whole text (a paragraph split between pages, a numbered list
/// running on, a right-to-left paragraph going on with a Latin word).
class TextFlow {
  const TextFlow({
    required this.from,
    this.joined = false,
    this.numbers = const [],
    this.direction = TextDirection.ltr,
    this.header = const [],
  });

  /// Id of the box this one continues.
  final String from;

  /// Whether the first line goes on with the previous box's last paragraph
  /// (the page ended inside it): that line has no list marker, and the
  /// whole text joins the two without a line break.
  final bool joined;

  /// For each list indent level, how many numbered items of a list running
  /// on into this box came before it (trailing zeros left out).
  final List<int> numbers;

  /// The direction of the box's first paragraph in the whole text: a part
  /// of a paragraph (or a paragraph without strong characters) keeps the
  /// direction it has there, whatever its own first strong character.
  final TextDirection direction;

  /// The header row of the table the box's first line goes on with, when
  /// that table has one (left on a page before): drawn again above its
  /// rows here (UX_AUDIT R26-15), for display only — not part of the
  /// box's text, so not searched, copied or exported as text twice.
  final List<RepeatedCell> header;

  /// A copy continuing the box [from].
  TextFlow withFrom(String from) =>
      TextFlow(from: from, joined: joined, numbers: numbers, direction: direction, header: header);

  /// The header row repeated on a box whose first line is line [line] of
  /// [whole]: that of the table [line] is in, if it has a header and
  /// [line] is past its first row; else none.
  static List<RepeatedCell> headerAt(TextData whole, int line) {
    final t = TextTables.at(whole.tables, line);
    if (t == null || !t.spec.header || t.cellOf(line).row == 0) return const [];
    final starts = whole.lineStarts;
    final cells = [
      for (var c = 0; c < t.columns; c++)
        whole.cellData(t.lineOf(0, c), start: starts[t.lineOf(0, c)]),
    ];
    return [for (final cell in cells) (text: cell.text, spans: cell.spans)];
  }

  /// Parses a stored flow strictly: every field present and well-typed,
  /// else null (the box then stands on its own).
  static TextFlow? fromJson(Object? json) {
    if (json is! Map) return null;
    final from = json['from'], joined = json['joined'], numbers = json['numbers'];
    if (from is! String || from.isEmpty || joined is! bool || numbers is! List) return null;
    final direction = switch (json['dir']) {
      'ltr' => TextDirection.ltr,
      'rtl' => TextDirection.rtl,
      _ => null,
    };
    if (direction == null) return null;
    final header = json.containsKey('header') ? _header(json['header']) : const <RepeatedCell>[];
    if (header == null) return null;
    if (numbers.length > ParaStyle.maxIndent + 1) return null;
    final counts = <int>[];
    for (final n in numbers) {
      if (n is! int || n < 0) return null;
      counts.add(n);
    }
    return TextFlow(
      from: from,
      joined: joined,
      numbers: _trim(counts),
      direction: direction,
      header: header,
    );
  }

  /// Stored [header] cells, strictly: `[{"text": …, "spans": [range, …]}, …]`
  /// (at most [TableSpec.maxColumns]); null if malformed.
  static List<RepeatedCell>? _header(Object? json) {
    if (json is! List || json.isEmpty || json.length > TableSpec.maxColumns) return null;
    final out = <RepeatedCell>[];
    for (final c in json) {
      if (c is! Map) return null;
      final text = c['text'], spans = c['spans'];
      if (text is! String || text.contains('\n') || spans is! List) return null;
      final ranges = <StyledRange>[];
      for (final s in spans) {
        final r = StyledRange.tryParse(s);
        if (r == null || r.start < 0 || r.end <= r.start || r.end > text.length) return null;
        ranges.add(r);
      }
      out.add((text: text, spans: List.unmodifiable(ranges)));
    }
    return List.unmodifiable(out);
  }

  Map<String, Object?> toJson() => {
    'from': from,
    'joined': joined,
    'numbers': numbers,
    'dir': direction.name,
    if (header.isNotEmpty)
      'header': [
        for (final c in header)
          {
            'text': c.text,
            'spans': [for (final s in c.spans) s.toJson()],
          },
      ],
  };

  static List<int> _trim(List<int> counts) {
    var n = counts.length;
    while (n > 0 && counts[n - 1] == 0) {
      n--;
    }
    return List.unmodifiable(counts.sublist(0, n));
  }

  /// The [numbers] of a box whose first paragraph follows the paragraphs
  /// styled [before] (of the whole text).
  static List<int> numbersAfter(List<ParaStyle> before) => _trim([
    for (var level = 0; level <= ParaStyle.maxIndent; level++)
      RichTextBuffer.listNumberOf([
            ...before,
            ParaStyle(list: ListKind.number, indent: level),
          ], before.length) -
          1,
  ]);

  /// The part [start, end) of [data]'s text with its formatting and box
  /// defaults (no flow): the lines it touches keep their paragraph styles;
  /// a part beginning inside a table begins with a copy of it marked
  /// [TableSpec.continued].
  static TextData slice(TextData data, int start, int end) {
    final text = data.text.substring(start, end);
    final firstLine = '\n'.allMatches(data.text.substring(0, start)).length;
    final lines = '\n'.allMatches(text).length + 1;
    final paras = data.paras.sublist(firstLine, firstLine + lines);
    if (paras.first.cell case final cell? when !cell.first) {
      paras[0] = ParaStyle(cell: TextTableCell(cell.spec.copyWith(continued: true), first: true));
    }
    return TextData.rich(
      text: text,
      spans: [
        for (final s in data.spans)
          if (s.end > start && s.start < end)
            StyledRange(
              s.start.clamp(start, end) - start,
              s.end.clamp(start, end) - start,
              s.style,
            ),
      ],
      paras: paras,
      font: data.font,
      fontSize: data.fontSize,
      color: data.color,
      align: data.align,
      autoWidth: data.autoWidth,
      spacing: data.spacing,
    );
  }

  /// The boxes of a chain ([parts], head first) as one text, in the box
  /// defaults of the head (no flow): a part joins the one before without a
  /// line break when its flow says [joined].
  static TextData join(List<TextData> parts) {
    final head = parts.first;
    if (parts.length == 1) return head.withFlow(null);
    final text = StringBuffer(head.text);
    final spans = [...head.spans];
    final paras = [...head.paras];
    for (final part in parts.skip(1)) {
      final joined = part.flow?.joined ?? false;
      if (!joined) text.write('\n');
      final at = text.length;
      text.write(part.text);
      for (final s in part.spans) {
        spans.add(StyledRange(s.start + at, s.end + at, s.style));
      }
      final more = joined ? part.paras.skip(1).toList() : [...part.paras];
      // A table going on from the part before joins its table; one that
      // can't (text or another table before it) is a table of its own.
      if (more.firstOrNull?.cell case final cell? when cell.spec.continued) {
        final before = paras.lastOrNull?.cell;
        more[0] = before != null && before.spec.columns == cell.spec.columns
            ? ParaStyle(cell: TextTableCell(before.spec))
            : ParaStyle(cell: TextTableCell(cell.spec.copyWith(continued: false), first: true));
      }
      paras.addAll(more);
    }
    return TextData.rich(
      text: text.toString(),
      spans: spans,
      paras: paras,
      font: head.font,
      fontSize: head.fontSize,
      color: head.color,
      align: head.align,
      autoWidth: head.autoWidth,
      spacing: head.spacing,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TextFlow &&
      other.from == from &&
      other.joined == joined &&
      other.direction == direction &&
      other.numbers.length == numbers.length &&
      Iterable<int>.generate(numbers.length).every((i) => other.numbers[i] == numbers[i]) &&
      _sameHeader(other.header, header);

  @override
  int get hashCode => Object.hash(
    from,
    joined,
    direction,
    Object.hashAll(numbers),
    Object.hashAll(header.map((c) => c.text)),
  );

  static bool _sameHeader(List<RepeatedCell> a, List<RepeatedCell> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].text != b[i].text || a[i].spans.length != b[i].spans.length) return false;
      for (var k = 0; k < a[i].spans.length; k++) {
        if (a[i].spans[k] != b[i].spans[k]) return false;
      }
    }
    return true;
  }

  @override
  String toString() => 'TextFlow(${toJson()})';
}
