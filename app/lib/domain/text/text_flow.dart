import 'rich_text_buffer.dart';
import 'text_data.dart';

/// How a text box continues the box before it in a chain of boxes that
/// flows across the pages of a notebook (`TextData.flow`): a box reaching
/// the bottom of its page continues at the top of the next page.
///
/// The first box of a chain (its head) has no flow; each continuation
/// names the box it continues ([from], on the page before). Every box holds
/// its own part of the text, so a page draws, searches and exports on its
/// own; [joined] and [numbers] make that part look as it does in the whole
/// text (a paragraph split between pages, a numbered list running on).
class TextFlow {
  const TextFlow({required this.from, this.joined = false, this.numbers = const []});

  /// Id of the box this one continues.
  final String from;

  /// Whether the first line goes on with the previous box's last paragraph
  /// (the page ended inside it): that line has no list marker, and the
  /// whole text joins the two without a line break.
  final bool joined;

  /// For each list indent level, how many numbered items of a list running
  /// on into this box came before it (trailing zeros left out).
  final List<int> numbers;

  /// Parses a stored flow strictly: every field present and well-typed,
  /// else null (the box then stands on its own).
  static TextFlow? fromJson(Object? json) {
    if (json is! Map) return null;
    final from = json['from'], joined = json['joined'], numbers = json['numbers'];
    if (from is! String || from.isEmpty || joined is! bool || numbers is! List) return null;
    if (numbers.length > ParaStyle.maxIndent + 1) return null;
    final counts = <int>[];
    for (final n in numbers) {
      if (n is! int || n < 0) return null;
      counts.add(n);
    }
    return TextFlow(from: from, joined: joined, numbers: _trim(counts));
  }

  Map<String, Object?> toJson() => {'from': from, 'joined': joined, 'numbers': numbers};

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
  /// defaults (no flow): the lines it touches keep their paragraph styles.
  static TextData slice(TextData data, int start, int end) {
    final text = data.text.substring(start, end);
    final firstLine = '\n'.allMatches(data.text.substring(0, start)).length;
    final lines = '\n'.allMatches(text).length + 1;
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
      paras: data.paras.sublist(firstLine, firstLine + lines),
      font: data.font,
      fontSize: data.fontSize,
      color: data.color,
      align: data.align,
      autoWidth: data.autoWidth,
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
      paras.addAll(joined ? part.paras.skip(1) : part.paras);
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
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TextFlow &&
      other.from == from &&
      other.joined == joined &&
      other.numbers.length == numbers.length &&
      Iterable<int>.generate(numbers.length).every((i) => other.numbers[i] == numbers[i]);

  @override
  int get hashCode => Object.hash(from, joined, Object.hashAll(numbers));

  @override
  String toString() => 'TextFlow(${toJson()})';
}
