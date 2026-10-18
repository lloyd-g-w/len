import 'text_table.dart';

export 'text_table.dart';

/// The kind of list a paragraph belongs to. Stored by [name] (except
/// [none], which is not stored).
enum ListKind {
  none,
  bullet,
  number,

  /// A to-do item with a checkbox (tap to toggle).
  check;

  static ListKind parse(Object? value) =>
      values.firstWhere((k) => k != none && k.name == value, orElse: () => none);
}

/// Formatting of one paragraph (line) of a text box.
///
/// Stored compactly (only set attributes): `h` heading level (1 or 2),
/// `l` list kind (`bullet`, `number`, `check`), `x` checked (true),
/// `n` list indent level (1..[maxIndent]); a table cell `tb` (the
/// table's first, with its [TableSpec]) or `tc` (`true`, the others).
class ParaStyle {
  const ParaStyle({
    this.heading = 0,
    this.list = ListKind.none,
    this.checked = false,
    this.indent = 0,
    this.cell,
    this.bold = false,
  });

  static const ParaStyle body = ParaStyle();

  /// Deepest list nesting.
  static const int maxIndent = 4;

  /// 0 = body text, 1 = heading 1, 2 = heading 2.
  final int heading;
  final ListKind list;

  /// Whether a [ListKind.check] item is ticked.
  final bool checked;

  /// Nesting level of a list item, 0..[maxIndent].
  final int indent;

  /// Set on a table cell (see [TextTableCell]; a cell has no other format).
  final TextTableCell? cell;

  /// The whole paragraph is bold: a header cell laid out on its own (not
  /// stored).
  final bool bold;

  bool get isList => list != ListKind.none;

  bool get isCell => cell != null;

  /// Font size factor of the heading level.
  double get sizeFactor => switch (heading) {
    1 => 1.6,
    2 => 1.3,
    _ => 1,
  };

  factory ParaStyle.fromJson(Object? json) {
    if (json is! Map) return body;
    if (json.containsKey('tb')) {
      final spec = TableSpec.fromJson(json['tb']);
      if (spec != null) return ParaStyle(cell: TextTableCell(spec, first: true));
    }
    if (json['tc'] == true) return ParaStyle(cell: TextTableCell.loose);
    final h = json['h'], n = json['n'];
    final list = ListKind.parse(json['l']);
    return ParaStyle(
      // (`1.0` from another JSON writer is a heading too, not a TypeError.)
      heading: h is num && (h == 1 || h == 2) ? h.toInt() : 0,
      list: list,
      checked: list == ListKind.check && json['x'] == true,
      indent: list != ListKind.none && n is int ? n.clamp(0, maxIndent) : 0,
    );
  }

  /// One style per line of [text] (unmodifiable), or none when all are
  /// [body] (the stored form); tables made consistent
  /// ([TextTables.normalize]).
  static List<ParaStyle> normalize(List<ParaStyle> paras, String text) {
    final lines = '\n'.allMatches(text).length + 1;
    if (paras.every((p) => p == ParaStyle.body)) return const [];
    return List.unmodifiable(
      TextTables.normalize([
        for (var i = 0; i < lines; i++) i < paras.length ? paras[i] : ParaStyle.body,
      ]),
    );
  }

  Map<String, Object?> toJson() => {
    if (cell case final cell?) ...{
      if (cell.first) 'tb': cell.spec.toJson() else 'tc': true,
    } else ...{
      if (heading != 0) 'h': heading,
      if (isList) 'l': list.name,
      if (checked) 'x': true,
      if (indent != 0) 'n': indent,
    },
  };

  /// A copy with other formats; a table cell stays a cell without them
  /// (use [withCell] to make it a paragraph).
  ParaStyle copyWith({int? heading, ListKind? list, bool? checked, int? indent}) {
    if (cell != null) return this;
    final l = list ?? this.list;
    return ParaStyle(
      heading: heading ?? this.heading,
      list: l,
      checked: l == ListKind.check && (checked ?? this.checked),
      indent: l == ListKind.none ? 0 : (indent ?? this.indent).clamp(0, maxIndent),
      bold: bold,
    );
  }

  /// A table cell [cell] (no other format), or body text when null.
  ParaStyle withCell(TextTableCell? cell) => cell == null ? body : ParaStyle(cell: cell);

  @override
  bool operator ==(Object other) =>
      other is ParaStyle &&
      other.heading == heading &&
      other.list == list &&
      other.checked == checked &&
      other.indent == indent &&
      other.cell == cell &&
      other.bold == bold;

  @override
  int get hashCode => Object.hash(heading, list, checked, indent, cell, bold);

  @override
  String toString() => 'ParaStyle(${toJson()})';
}
