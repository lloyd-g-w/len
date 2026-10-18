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
/// line; paragraph spacing below a part's last line may reach past it). One layout of the whole text serves every part, which lays out
/// alone as it does here (a part begins at a line start); a part on a page
/// of another width (`width(k)`) lays out what is left again there.
abstract final class TextFlowLayout {
  /// The parts of [layout]'s text when part k has [room] (k) to fill and is
  /// [width] (k) wide (by default all as wide as [layout]); a single part
  /// when it all fits the first.
  static List<FlowPart> split(
    TextBoxLayout layout,
    double Function(int part) room, {
    double Function(int part)? width,
  }) {
    final whole = layout.data;
    var (:starts, :heights) = _cuts(layout, room);
    if (starts.length == 1) {
      return [FlowPart(start: 0, end: whole.text.length, height: layout.painter.height)];
    }
    if (width != null) {
      var w = width(0);
      for (var k = 1; k < starts.length; k++) {
        if (width(k) == w) continue;
        w = width(k);
        // The rest, from part k on, as it lays out at its own width.
        final at = starts[k];
        final rest = _part(layout, at, whole.text.length, 0, k).dataOf(whole, from: '-');
        final relaid = TextLayout.layout(rest, w);
        final more = _cuts(relaid, (j) => room(k + j));
        relaid.dispose();
        starts = [...starts.take(k), for (final s in more.starts) at + s];
        heights = [...heights.take(k), ...more.heights];
      }
    }
    final text = whole.text;
    return [
      for (var k = 0; k < starts.length; k++)
        _part(
          layout,
          starts[k],
          k + 1 < starts.length ? starts[k + 1] : text.length,
          heights[k],
          k,
          last: k + 1 == starts.length,
        ),
    ];
  }

  /// Where the parts of [layout]'s text begin (model offsets) and their
  /// heights, part k at most [room] (k) tall.
  static ({List<int> starts, List<double> heights}) _cuts(
    TextBoxLayout layout,
    double Function(int part) room,
  ) {
    final lines = layout.painter.computeLineMetrics();
    final length = layout.data.text.length;
    final starts = <int>[0];
    final heights = <double>[];
    var partTop = 0.0, top = 0.0;
    var first = 0; // The part's first line.
    for (var i = 0; i < lines.length; i++) {
      final bottom = top + lines[i].height;
      // Paragraph spacing below the line's text may run past the room.
      final text = bottom - layout.spacingAbove(bottom);
      if (i > first && text - partTop > room(starts.length - 1)) {
        final at = _lineStart(layout, top, lines[i].height);
        if (at > starts.last && at <= length) {
          heights.add(top - partTop);
          starts.add(at);
          partTop = top;
          first = i;
        }
      }
      top = bottom;
    }
    heights.add(top - partTop);
    return (starts: starts, heights: heights);
  }

  /// Part [k] of [layout]'s text, from [start] to the next part's start
  /// [next] (the end of the text when [last]), [height] tall.
  static FlowPart _part(
    TextBoxLayout layout,
    int start,
    int next,
    double height,
    int k, {
    bool last = true,
  }) {
    final whole = layout.data;
    final text = whole.text;
    final hard = start > 0 && text.codeUnitAt(start - 1) == 0x0A;
    final nextHard = !last && text.codeUnitAt(next - 1) == 0x0A;
    final line = '\n'.allMatches(text.substring(0, start)).length;
    return FlowPart(
      start: start,
      end: nextHard ? next - 1 : next,
      height: height,
      joined: k > 0 && !hard,
      numbers: k == 0 ? const [] : TextFlow.numbersAfter(whole.paras.sublist(0, line)),
      direction: layout.plan.directions[line],
    );
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
