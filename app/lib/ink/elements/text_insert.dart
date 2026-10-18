import 'dart:ui';

import 'list_marker.dart';

/// What a [TextInsert] puts into the laid-out text, one character each.
enum InsertKind {
  /// A list marker's placeholder (U+FFFC).
  marker,

  /// An empty placeholder (U+FFFC): a hanging indent's gap, or the padding
  /// that aligns a line of a paragraph running against the box's direction.
  space,

  /// A line break (`\n`) where a paragraph wraps.
  lineBreak,

  /// Opens a directional isolate (U+2066 LRI or U+2067 RLI): the text up
  /// to the next [pop] runs in [InsertPiece.direction], whatever the box's.
  isolate,

  /// Closes the isolate (U+2069 PDI).
  pop,

  /// The room over a page edge in the editing field of a box flowing
  /// across pages (U+FFFC, as tall as [InsertPiece.size]); on a line of its
  /// own, ended by a [roomBreak].
  room,

  /// The line break after a [room], so small the line is as tall as the
  /// room.
  roomBreak,

  /// Paragraph spacing (U+FFFC, no wider than nothing): hung below the
  /// baseline of a paragraph's last line, [InsertPiece.size] tall, so the
  /// line reaches that far below its text (see `TextSpacing`).
  spacing,

  /// A table row (U+FFFC, [InsertPiece.size]: the table's width, the row's
  /// height) standing for the row's cells, whose text its [TextInsert]
  /// replaces (see `TableLayout`).
  row,
}

/// One character of a [TextInsert].
class InsertPiece {
  const InsertPiece._(this.kind) : size = Size.zero, marker = null, direction = null, row = null;

  InsertPiece.marker(ListMarker this.marker)
    : kind = InsertKind.marker,
      size = marker.size,
      direction = null,
      row = null;

  /// An empty placeholder of [size].
  const InsertPiece.space(this.size)
    : kind = InsertKind.space,
      marker = null,
      direction = null,
      row = null;

  /// Row [row] of the plan's table [table], [size] (see [InsertKind.row]).
  InsertPiece.row(this.size, int table, int row)
    : kind = InsertKind.row,
      marker = null,
      direction = null,
      row = (table: table, row: row);

  static const InsertPiece lineBreak = InsertPiece._(InsertKind.lineBreak);
  static const InsertPiece pop = InsertPiece._(InsertKind.pop);

  /// The room of a page break, [gap] tall.
  InsertPiece.room(double gap)
    : kind = InsertKind.room,
      size = Size(0, gap < 0 ? 0 : gap),
      marker = null,
      direction = null,
      row = null;

  static const InsertPiece roomBreak = InsertPiece._(InsertKind.roomBreak);

  /// Paragraph spacing reaching [height] below the baseline.
  InsertPiece.spacing(double height)
    : kind = InsertKind.spacing,
      size = Size(0, height < 0 ? 0 : height),
      marker = null,
      direction = null,
      row = null;

  const InsertPiece.isolate(TextDirection this.direction)
    : kind = InsertKind.isolate,
      size = Size.zero,
      marker = null,
      row = null;

  final InsertKind kind;

  /// The placeholder size of [InsertKind.marker], [InsertKind.space],
  /// [InsertKind.room] and [InsertKind.spacing].
  final Size size;
  final ListMarker? marker;
  final TextDirection? direction;

  /// Of [InsertKind.row]: which table of the plan, which of its rows.
  final ({int table, int row})? row;

  /// The character it stands for in the laid-out text.
  String get char => switch (kind) {
    InsertKind.marker ||
    InsertKind.space ||
    InsertKind.room ||
    InsertKind.spacing ||
    InsertKind.row => '\uFFFC',
    InsertKind.lineBreak || InsertKind.roomBreak => '\n',
    InsertKind.isolate => direction == TextDirection.rtl ? '\u2067' : '\u2066',
    InsertKind.pop => '\u2069',
  };

  bool get isPlaceholder =>
      kind == InsertKind.marker ||
      kind == InsertKind.space ||
      kind == InsertKind.room ||
      kind == InsertKind.spacing ||
      kind == InsertKind.row;

  /// Whether it belongs to a page break's room ([InsertKind.room] or
  /// [InsertKind.roomBreak]).
  bool get isRoom => kind == InsertKind.room || kind == InsertKind.roomBreak;

  @override
  bool operator ==(Object other) =>
      other is InsertPiece &&
      other.kind == kind &&
      other.size == size &&
      other.marker == marker &&
      other.direction == direction &&
      other.row == row;

  @override
  int get hashCode => Object.hash(kind, size, marker, direction, row);
}

/// Characters the layout inserts into a text box's text before model
/// offset [at]: list markers, hanging-indent breaks and gaps, around
/// paragraphs running against the box's direction their isolates and the
/// padding that aligns them, paragraph spacing, and in the editing field of
/// a box flowing across pages the rooms over the page edges (see
/// `TextPlan`).
///
/// The caret never rests inside an insert except at [allowed] positions
/// (0 = before its first character, [length] = after its last); model
/// offset [at] shows the caret at [caret].
///
/// A table row's insert [replaces] the model text of its cells: the
/// laid-out text holds the pieces instead of model [at, at + replaces).
class TextInsert {
  TextInsert(
    this.at,
    this.pieces, {
    required this.caret,
    required Set<int> allowed,
    this.replaces = 0,
  }) : allowed = Set.unmodifiable(allowed);

  final int at;
  final List<InsertPiece> pieces;
  final int caret;
  final Set<int> allowed;

  /// How much model text from [at] on the pieces stand for (0: they are
  /// inserted before it).
  final int replaces;

  /// Model offset after the text it replaces.
  int get end => at + replaces;

  /// Whether it is a table row (standing for its cells' text).
  bool get isRow => pieces.any((p) => p.kind == InsertKind.row);

  /// How much longer the laid-out text is for it.
  int get growth => pieces.length - replaces;

  int get length => pieces.length;

  String get text => pieces.map((p) => p.char).join();

  /// [inserts] sorted by offset (stable), those at one offset joined in
  /// order: the caret of the last one, the allowed positions of all.
  static List<TextInsert> merge(List<TextInsert> inserts) {
    final sorted = [...inserts];
    _sortByOffset(sorted);
    final out = <TextInsert>[];
    for (final i in sorted) {
      final last = out.isEmpty ? null : out.last;
      if (last == null || last.at != i.at) {
        out.add(i);
        continue;
      }
      final shift = last.length;
      out[out.length - 1] = TextInsert(
        i.at,
        [...last.pieces, ...i.pieces],
        caret: shift + i.caret,
        allowed: {...last.allowed, for (final a in i.allowed) shift + a},
        replaces: last.replaces + i.replaces,
      );
    }
    return out;
  }

  /// Insertion sort by [at]: stable, and inserts come nearly sorted.
  static void _sortByOffset(List<TextInsert> list) {
    for (var i = 1; i < list.length; i++) {
      final x = list[i];
      var j = i - 1;
      while (j >= 0 && list[j].at > x.at) {
        list[j + 1] = list[j];
        j--;
      }
      list[j + 1] = x;
    }
  }

  @override
  bool operator ==(Object other) =>
      other is TextInsert &&
      other.at == at &&
      other.caret == caret &&
      other.replaces == replaces &&
      _same(other.pieces, pieces) &&
      other.allowed.length == allowed.length &&
      other.allowed.containsAll(allowed);

  @override
  int get hashCode => Object.hash(at, caret, Object.hashAll(pieces));

  static bool _same(List<InsertPiece> a, List<InsertPiece> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
