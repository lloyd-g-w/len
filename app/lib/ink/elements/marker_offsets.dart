import '../../domain/text/text_data.dart';
import 'text_insert.dart';
import 'text_plan.dart';

/// Maps offsets between a text box's text (model offsets) and the laid-out
/// (display) text, which adds the [TextInsert]s of its `TextPlan`:
///
/// - one placeholder character (U+FFFC) before each list line, where its
///   marker sits,
/// - at each *wrap* of a list item a line break plus a placeholder as wide
///   as the marker column ([wrapText]), so the continuation line hangs
///   under the item's text, and
/// - around paragraphs running against the box's direction, isolates and
///   the placeholders that align their lines (with a break at each wrap),
///   and
/// - at each page break of a box flowing across pages (`FlowBreak`, in the
///   editing field only) a line holding a placeholder as tall as the room
///   to the next page.
///
/// The model offset at a wrap or page break maps to the start of the
/// continuation line.
class MarkerOffsets {
  MarkerOffsets(List<TextInsert> inserts) : _inserts = inserts;

  /// The offsets of [data] laid out in a box [width] wide (see [TextPlan]).
  factory MarkerOffsets.of(TextData data, [double width = double.infinity]) =>
      TextPlan.of(data, width).offsets;

  /// What is inserted at the wrap of a list item running in the box's
  /// direction.
  static const String wrapText = '\n\uFFFC';

  /// Sorted by offset, one per offset.
  final List<TextInsert> _inserts;

  bool get isEmpty => _inserts.isEmpty;

  /// Display offset of model offset [m] as a caret position: after the
  /// marker of its line, at a wrap at the start of the continuation line,
  /// at the end of a paragraph before its closing isolate; inside a table
  /// row's cells, before the row.
  int toDisplay(int m) {
    var d = m;
    for (final i in _inserts) {
      if (i.at > m) break;
      if (i.at == m || m < i.end) return d - (m - i.at) + i.caret;
      d += i.growth;
    }
    return d;
  }

  /// Display offset of the character at model offset [m] (after every
  /// insert in front of it; inside a table row, the row's).
  int charAt(int m) {
    var d = m;
    for (final i in _inserts) {
      if (i.at > m) break;
      if (m < i.end) return d - (m - i.at) + i.length - 1;
      d += i.growth;
    }
    return d;
  }

  /// Model offset of display offset [d] (inside an insert: its offset;
  /// after a table row: the end of its cells).
  int toModel(int d) {
    var shift = 0;
    for (final i in _inserts) {
      final start = i.at + shift;
      if (d <= start) break;
      if (d < start + i.length) return i.at;
      shift += i.growth;
    }
    return d - shift;
  }

  /// The insert at display position [d] (0 ≤ index ≤ its length), if any.
  ({TextInsert insert, int index})? _around(int d) {
    var shift = 0;
    for (final i in _inserts) {
      final start = i.at + shift;
      if (d < start) return null;
      if (d <= start + i.length) return (insert: i, index: d - start);
      shift += i.growth;
    }
    return null;
  }

  /// The inserted character at display offset [d], if it is one.
  InsertPiece? pieceAt(int d) {
    final a = _around(d);
    if (a == null || a.index == a.insert.length) return null;
    return a.insert.pieces[a.index];
  }

  /// Whether display character [d] is a list marker.
  bool isMarker(int d) => pieceAt(d)?.kind == InsertKind.marker;

  /// Whether display offset [d] lies inside a page break's room (on the
  /// line of the room over a page edge, or just before it).
  bool isPageBreak(int d) => pieceAt(d)?.isRoom ?? false;

  /// Display offset of the room placeholder of the page break at model
  /// offset [at], if there is one.
  int? roomOf(int at) {
    var shift = 0;
    for (final i in _inserts) {
      if (i.at > at) break;
      if (i.at == at) {
        final k = i.pieces.indexWhere((p) => p.kind == InsertKind.room);
        if (k >= 0) return i.at + shift + k;
      }
      shift += i.growth;
    }
    return null;
  }

  /// Whether display character [d] was inserted by the layout.
  bool isInserted(int d) => pieceAt(d) != null;

  /// Whether the caret must not rest at display offset [d]: just before a
  /// marker, between a wrap's break and its indent, around isolates and
  /// alignment padding.
  bool isHidden(int d) {
    final a = _around(d);
    return a != null && !a.insert.allowed.contains(a.index);
  }

  /// The nearest display offset to [d] (in a text of [length]) where the
  /// caret may rest: searching backwards first ([step] -1), forwards first
  /// ([step] 1), or after a jump (0) the caret position of the insert's own
  /// model offset (a click or Home in the padding before a line lands on
  /// that line, End after a closing isolate stays at its paragraph's end).
  int allowedNear(int d, int length, {int step = 0}) {
    if (!isHidden(d)) return d;
    if (step == 0) return toDisplay(toModel(d));
    int? back() {
      for (var p = d - 1; p >= 0; p--) {
        if (!isHidden(p)) return p;
      }
      return null;
    }

    int? forth() {
      for (var p = d + 1; p <= length; p++) {
        if (!isHidden(p)) return p;
      }
      return null;
    }

    if (step < 0) return back() ?? forth() ?? d;
    return forth() ?? back() ?? d;
  }

  /// The display ranges holding the model text [start, end), without the
  /// inserts inside it (nor table cells, which a row replaces).
  List<(int, int)> displayRanges(int start, int end) {
    final out = <(int, int)>[];
    var from = start;
    for (final i in _inserts) {
      if (i.end <= from && i.replaces > 0) continue;
      if (i.at <= from) {
        if (i.replaces > 0 && from < i.end) from = i.end;
        continue;
      }
      if (i.at >= end) break;
      out.add((charAt(from), charAt(from) + i.at - from));
      from = i.replaces > 0 ? i.end : i.at;
    }
    if (end > from) out.add((charAt(from), charAt(from) + end - from));
    return out;
  }

  /// The table rows' inserts (those replacing model text).
  Iterable<TextInsert> get rows => _inserts.where((i) => i.isRow);

  /// Whether model offset [m] is inside a table row's cells (their ends
  /// included).
  bool isInRow(int m) => _inserts.any((i) => i.isRow && m >= i.at && m <= i.end);

  /// The laid-out text of [text].
  String display(String text) {
    if (_inserts.isEmpty) return text;
    final out = StringBuffer();
    var last = 0;
    for (final i in _inserts) {
      out
        ..write(text.substring(last, i.at))
        ..write(i.text);
      last = i.end;
    }
    out.write(text.substring(last));
    return out.toString();
  }
}
