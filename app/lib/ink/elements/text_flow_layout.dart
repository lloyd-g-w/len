import 'package:flutter/painting.dart';

import '../../domain/text/text_data.dart';
import 'text_layout.dart';

/// One box of a chain flowing across pages, as laid out: the part
/// [start, end) of the whole text (model offsets) and its height.
class FlowPart {
  const FlowPart({
    required this.start,
    required this.end,
    required this.height,
    this.joined = false,
    this.numbers = const [],
    this.direction = TextDirection.ltr,
  });

  /// Where the part begins in the whole text. After a paragraph break the
  /// `\n` before it belongs to neither part.
  final int start;
  final int end;

  /// Height of its lines, in world units.
  final double height;

  /// Whether it begins inside a paragraph (see [TextFlow.joined]).
  final bool joined;

  /// See [TextFlow.numbers].
  final List<int> numbers;

  /// The direction its first paragraph has in the whole text (see
  /// [TextFlow.direction]).
  final TextDirection direction;

  /// The part's text out of [whole]; continuing the box [from] (null for
  /// the first part).
  TextData dataOf(TextData whole, {String? from}) {
    final data = TextFlow.slice(whole, start, end);
    return from == null
        ? data
        : data.withFlow(
            TextFlow(from: from, joined: joined, numbers: numbers, direction: direction),
          );
  }

  @override
  String toString() => 'FlowPart($start–$end, h $height${joined ? ', joined' : ''})';
}

/// Splits a laid-out text box into the parts that fit on successive pages:
/// at line boundaries, each part at most `room(k)` tall (yet at least one
/// line). One layout of the whole text serves every part, which lays out
/// alone as it does here (a part begins at a line start).
abstract final class TextFlowLayout {
  /// The parts of [layout]'s text when part k has [room] (k) to fill;
  /// a single part when it all fits the first.
  static List<FlowPart> split(TextBoxLayout layout, double Function(int part) room) {
    final painter = layout.painter;
    final whole = layout.data;
    final lines = painter.computeLineMetrics();
    final starts = <int>[0];
    final heights = <double>[];
    var partTop = 0.0, top = 0.0;
    var first = 0; // The part's first line.
    for (var i = 0; i < lines.length; i++) {
      final bottom = top + lines[i].height;
      if (i > first && bottom - partTop > room(starts.length - 1)) {
        final at = _lineStart(layout, top, lines[i].height);
        if (at > starts.last && at <= whole.text.length) {
          heights.add(top - partTop);
          starts.add(at);
          partTop = top;
          first = i;
        }
      }
      top = bottom;
    }
    heights.add(top - partTop);
    if (starts.length == 1) {
      return [FlowPart(start: 0, end: whole.text.length, height: painter.height)];
    }
    final paras = whole.paras;
    final directions = layout.plan.directions;
    final text = whole.text;
    final parts = <FlowPart>[];
    for (var k = 0; k < starts.length; k++) {
      final s = starts[k];
      final hard = s > 0 && text.codeUnitAt(s - 1) == 0x0A;
      final next = k + 1 < starts.length ? starts[k + 1] : text.length;
      final nextHard = k + 1 < starts.length && text.codeUnitAt(next - 1) == 0x0A;
      final line = '\n'.allMatches(text.substring(0, s)).length;
      parts.add(
        FlowPart(
          start: s,
          end: nextHard ? next - 1 : next,
          height: heights[k],
          joined: k > 0 && !hard,
          numbers: k == 0 ? const [] : TextFlow.numbersAfter(paras.sublist(0, line)),
          direction: directions[line],
        ),
      );
    }
    return parts;
  }

  /// The model offset where the line at [top] (of [height]) begins: at
  /// its start side in the box's direction (the right of a right-to-left
  /// box, where also the lines of left-to-right paragraphs begin with their
  /// padding, see [TextPlan]).
  static int _lineStart(TextBoxLayout layout, double top, double height) {
    final painter = layout.painter;
    final x = layout.plan.base == TextDirection.rtl ? painter.width + 1 : -1.0;
    final position = painter.getPositionForOffset(Offset(x, top + height / 2));
    return layout.offsets.toModel(position.offset);
  }
}
