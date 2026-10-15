import 'dart:math' as math;
import 'dart:ui';

import '../../domain/text/paragraph_direction.dart';
import '../../domain/text/text_data.dart';
import 'text_layout.dart';

/// How a text box is laid out as one paragraph at a width: the direction
/// of the box ([base], its first paragraph's) and of each paragraph, the
/// list markers, where lines wrap on their own ([wraps]) and what the
/// layout inserts into the text ([inserts], mapped by [offsets]).
///
/// Paragraphs running in the box's direction lay out natively; the base
/// direction and the box's alignment put their markers, hanging indents
/// and lines on their start side. A paragraph running the other way (a
/// Hebrew line in an English box, or the reverse) is wrapped on its own
/// ([TextWraps.linesOf]), and each of its lines is broken off, isolated in
/// its direction (bidi isolates, so its words and marker order themselves
/// as in a paragraph of that direction) and padded with empty placeholders
/// so it sits where its alignment puts it: on its own start, centre or end.
/// Canvas, editing field and PDF export share this plan, so they agree to
/// the pixel.
class TextPlan {
  TextPlan._(this.base, this.directions, this.markers, this.wraps, List<TextInsert> inserts)
    : inserts = TextInsert.merge(inserts) {
    offsets = MarkerOffsets(this.inserts);
  }

  /// The plan of [data] in a box [width] wide (unbounded: nothing wraps or
  /// is padded, for measuring). Auto-width boxes never wrap.
  factory TextPlan.of(TextData data, double width) {
    final directions = ParagraphDirection.of(data.text);
    final base = directions.first;
    final markers = TextLayout.markersOf(data, directions);
    final w = width.isFinite ? math.max(width, TextLayout.minWidth) : double.infinity;
    final builder = _Builder(data, w, base, wrap: w.isFinite && !data.autoWidth);
    final byLine = {for (final m in markers) m.line: m};
    final text = data.text;
    var start = 0;
    for (var line = 0; line < directions.length; line++) {
      final nl = text.indexOf('\n', start);
      final end = nl < 0 ? text.length : nl;
      final m = byLine[line];
      if (directions[line] == base) {
        builder.native(line, start, end, m);
      } else {
        builder.against(line, start, end, m, directions[line]);
      }
      start = end + 1;
    }
    return TextPlan._(base, directions, markers, builder.wraps, builder.inserts);
  }

  /// The box's direction: its first paragraph's.
  final TextDirection base;

  /// Each paragraph's direction.
  final List<TextDirection> directions;

  /// The list markers, in line order.
  final List<ListMarker> markers;

  /// Model offsets where a line continues that the plan broke itself: list
  /// items' hanging indents and the lines of paragraphs running against
  /// [base].
  final List<int> wraps;

  /// What the layout inserts, sorted by offset (one per offset).
  final List<TextInsert> inserts;

  /// Model ↔ laid-out offsets.
  late final MarkerOffsets offsets;

  /// Whether some paragraph runs against the box's direction.
  bool get isMixed => directions.any((d) => d != base);
}

/// Collects a [TextPlan]'s inserts and wraps, paragraph by paragraph.
class _Builder {
  _Builder(this.data, this.width, this.base, {required this.wrap}) : chars = data.charStyles();

  final TextData data;
  final double width;
  final TextDirection base;
  final bool wrap;
  final List<SpanStyle> chars;
  final List<TextInsert> inserts = [];
  final List<int> wraps = [];

  /// A paragraph in the box's direction: its marker, and a break plus a
  /// gap where a list item wraps.
  void native(int line, int start, int end, ListMarker? m) {
    if (m == null) return;
    inserts.add(TextInsert(start, [InsertPiece.marker(m)], caret: 1, allowed: {1}));
    if (!wrap) return;
    final lines = TextWraps.linesOf(
      data,
      chars,
      data.paras[line],
      start,
      end,
      width: width - m.size.width,
      direction: base,
    );
    for (final l in lines.skip(1)) {
      wraps.add(l.start);
      inserts.add(
        TextInsert(
          l.start,
          [InsertPiece.lineBreak, InsertPiece.space(m.size)],
          caret: 2,
          allowed: {0, 2},
        ),
      );
    }
  }

  /// A paragraph running in [direction], against the box: each line
  /// broken off, isolated and padded into place.
  void against(int line, int start, int end, ListMarker? m, TextDirection direction) {
    final head = m?.size.width ?? 0;
    final lines = TextWraps.linesOf(
      data,
      chars,
      data.paras[line],
      start,
      end,
      width: wrap ? width - head : double.infinity,
      direction: direction,
      measure: width.isFinite,
    );
    final pads = [for (final l in lines) _pads(head + l.width, l.spaces, direction)];
    List<InsertPiece> open(int k) => [
      if (pads[k].lead != null) InsertPiece.space(Size(pads[k].lead!, 0)),
      InsertPiece.isolate(direction),
      if (m != null) k == 0 ? InsertPiece.marker(m) : InsertPiece.space(m.size),
    ];
    List<InsertPiece> close(int k) => [
      if (pads[k].trail != null) InsertPiece.space(Size(pads[k].trail!, 0)),
    ];
    final first = open(0);
    inserts.add(TextInsert(start, first, caret: first.length, allowed: {first.length}));
    for (var k = 1; k < lines.length; k++) {
      final at = lines[k].start;
      wraps.add(at);
      // Trailing spaces stay outside the isolate: at the line's end they
      // hang over the edge instead of pushing the text in.
      inserts.add(
        TextInsert(at - lines[k - 1].trailing, [InsertPiece.pop], caret: 0, allowed: {0}),
      );
      final pieces = [...close(k - 1), InsertPiece.lineBreak, ...open(k)];
      inserts.add(TextInsert(at, pieces, caret: pieces.length, allowed: {pieces.length}));
    }
    inserts.add(
      TextInsert(end, [InsertPiece.pop, ...close(lines.length - 1)], caret: 0, allowed: {0}),
    );
  }

  /// The padding before (lead) and after (trail) a line of [content] width
  /// followed by [spaces] that puts it where the box's alignment wants it
  /// in a paragraph running in [direction]. Null where none is needed (a
  /// trail that would not fit is left out: trailing spaces may hang over).
  ({double? lead, double? trail}) _pads(double content, double spaces, TextDirection direction) {
    if (!width.isFinite) return (lead: null, trail: null);
    final free = math.max(0.0, width - content);
    final ltr = direction == TextDirection.ltr;
    // The text's left edge.
    final x = switch (data.align) {
      TextAlignment.center => free / 2,
      TextAlignment.start => ltr ? 0.0 : free,
      TextAlignment.end => ltr ? free : 0.0,
    };
    final lead = base == TextDirection.ltr ? x : free - x;
    final trail = width - TextWraps.epsilon - lead - content - spaces;
    return (lead: lead, trail: trail > 0 ? trail : null);
  }
}
