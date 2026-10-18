import 'dart:math' as math;

import 'paragraph_style.dart';

/// The shape of a table inside a text box: its column widths (shares of
/// the box's width, summing to 1), whether its first row is a bold header,
/// and whether it [continued]s a table from the box on the page before
/// (a table split between rows by a page break, see `TextFlow`).
///
/// Stored on the table's first cell (`ParaStyle.cell`): `{"c": columns,
/// "w": [share, …], "h": header}` plus `"k": true` when [continued].
class TableSpec {
  /// Column [widths] are normalised (each at least [minShare], summing to 1).
  TableSpec(List<double> widths, {this.header = false, this.continued = false})
    : widths = List.unmodifiable(_normalized(widths));

  /// [columns] columns of equal width.
  factory TableSpec.even(int columns, {bool header = false}) =>
      TableSpec(List.filled(columns.clamp(1, maxColumns), 1.0), header: header);

  /// The most columns a table has.
  static const int maxColumns = 12;

  /// The narrowest a column gets, as a share of the table.
  static const double minShare = 0.04;

  /// Column widths as shares of the table's width (sum 1).
  final List<double> widths;
  final bool header;
  final bool continued;

  int get columns => widths.length;

  /// Whether the first row (laid out here) is bold: a header not left on
  /// the page before.
  bool get hasHeaderRow => header && !continued;

  /// The table with other widths, header or continuation.
  TableSpec copyWith({List<double>? widths, bool? header, bool? continued}) => TableSpec(
    widths ?? this.widths,
    header: header ?? this.header,
    continued: continued ?? this.continued,
  );

  static List<double> _normalized(List<double> widths) {
    if (widths.isEmpty) return const [1];
    final clean = [for (final w in widths) w.isFinite && w > 0 ? w : minShare];
    final sum = clean.fold(0.0, (a, b) => a + b);
    // Narrow columns are widened to [minShare], then all scaled back.
    final raised = [for (final w in clean) math.max(w / sum, minShare)];
    final total = raised.fold(0.0, (a, b) => a + b);
    final shares = [for (final s in raised) s / total];
    // Four decimals keep the stored form short; the last takes the rest.
    final rounded = [for (final s in shares) (s * 10000).roundToDouble() / 10000];
    final head = rounded.take(rounded.length - 1).fold(0.0, (a, b) => a + b);
    rounded[rounded.length - 1] = ((1 - head) * 10000).roundToDouble() / 10000;
    return rounded;
  }

  Map<String, Object?> toJson() => {
    'c': columns,
    'w': widths,
    'h': header,
    if (continued) 'k': true,
  };

  /// A spec this app wrote (tolerant); null if [json] is none.
  static TableSpec? fromJson(Object? json) {
    if (json is! Map) return null;
    final w = json['w'];
    if (w is! List || w.isEmpty || w.length > maxColumns) return null;
    return TableSpec(
      [for (final v in w) v is num ? v.toDouble() : 0],
      header: json['h'] == true,
      continued: json['k'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is TableSpec &&
      other.header == header &&
      other.continued == continued &&
      _same(other.widths, widths);

  @override
  int get hashCode => Object.hash(header, continued, Object.hashAll(widths));

  static bool _same(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  @override
  String toString() => 'TableSpec(${toJson()})';
}

/// A line of a text box that is a table cell: the table's [spec] (on every
/// cell in memory, stored on the first only) and whether it is the table's
/// [first] cell. [header]: in the bold first row of a table with a header
/// (derived, not stored).
class TextTableCell {
  const TextTableCell(this.spec, {this.first = false, this.header = false});

  final TableSpec spec;
  final bool first;
  final bool header;

  /// A cell read before its table's spec is known (`{"tc": true}`), linked
  /// by [TextTables.normalize].
  static final TextTableCell loose = TextTableCell(TableSpec(const [1]));

  TextTableCell copyWith({TableSpec? spec, bool? first, bool? header}) =>
      TextTableCell(spec ?? this.spec, first: first ?? this.first, header: header ?? this.header);

  @override
  bool operator ==(Object other) =>
      other is TextTableCell &&
      other.spec == spec &&
      other.first == first &&
      other.header == header;

  @override
  int get hashCode => Object.hash(spec, first, header);
}

/// A table of a text box: from line [line] on, [rows] × `spec.columns`
/// lines, one per cell in row-major order (the last row may lack cells in
/// text not written by this app: they lay out empty).
class TextTable {
  const TextTable(this.line, this.cells, this.spec);

  /// The line of its first cell.
  final int line;

  /// How many cells (lines) it has.
  final int cells;
  final TableSpec spec;

  int get columns => spec.columns;
  int get rows => (cells + columns - 1) ~/ columns;

  /// The line after its last cell.
  int get end => line + cells;

  /// The line of the cell at [row], [column] (may be past [end] in a
  /// short last row).
  int lineOf(int row, int column) => line + row * columns + column;

  bool contains(int l) => l >= line && l < end;

  /// Row and column of line [l] (inside the table).
  ({int row, int column}) cellOf(int l) =>
      (row: (l - line) ~/ columns, column: (l - line) % columns);

  @override
  bool operator ==(Object other) =>
      other is TextTable && other.line == line && other.cells == cells && other.spec == spec;

  @override
  int get hashCode => Object.hash(line, cells, spec);

  @override
  String toString() => 'TextTable(line $line, $cells cells, $spec)';
}

/// Finding and normalising the tables of a text box's paragraphs.
abstract final class TextTables {
  /// The tables of [paras] (one per line), in line order.
  static List<TextTable> of(List<ParaStyle> paras) {
    final out = <TextTable>[];
    var l = 0;
    while (l < paras.length) {
      final cell = paras[l].cell;
      if (cell == null) {
        l++;
        continue;
      }
      var e = l + 1;
      while (e < paras.length && paras[e].cell != null && !paras[e].cell!.first) {
        e++;
      }
      out.add(TextTable(l, e - l, cell.spec));
      l = e;
    }
    return out;
  }

  /// The table holding [line], if any.
  static TextTable? at(List<TextTable> tables, int line) {
    for (final t in tables) {
      if (t.contains(line)) return t;
    }
    return null;
  }

  /// Whether any line of [paras] is a table cell.
  static bool any(List<ParaStyle> paras) => paras.any((p) => p.cell != null);

  /// [paras] with every table consistent: a cell not following a cell
  /// starts a table, cells take the spec of their table's first cell (so
  /// loose cells read from storage get theirs), cells of a header row are
  /// marked [TextTableCell.header], and cells have no other paragraph format.
  /// [paras] itself when nothing changes.
  static List<ParaStyle> normalize(List<ParaStyle> paras) {
    if (!any(paras)) return paras;
    final out = <ParaStyle>[];
    TableSpec? spec;
    var index = 0; // Of the cell in its table.
    var changed = false;
    for (final p in paras) {
      final cell = p.cell;
      if (cell == null) {
        spec = null;
        out.add(p);
        continue;
      }
      final first = cell.first || spec == null;
      final TableSpec current;
      if (first) {
        current = identical(cell, TextTableCell.loose) ? TableSpec(const [1]) : cell.spec;
        index = 0;
      } else {
        current = spec;
      }
      spec = current;
      final header = current.hasHeaderRow && index < current.columns;
      final next = ParaStyle(
        cell: TextTableCell(current, first: first, header: header),
      );
      changed = changed || next != p;
      out.add(next);
      index++;
    }
    return changed ? out : paras;
  }

  /// The plain text of [text] (lines styled [paras]) as other apps take
  /// it: the cells of a table row joined by tabs, rows by line breaks.
  static String plainText(String text, List<ParaStyle> paras) {
    if (!any(paras)) return text;
    final lines = text.split('\n');
    final tables = of(paras);
    final out = StringBuffer();
    var l = 0;
    for (final t in tables) {
      for (; l < t.line; l++) {
        out
          ..write(lines[l])
          ..write('\n');
      }
      for (var r = 0; r < t.rows; r++) {
        for (var c = 0; c < t.columns; c++) {
          final k = t.lineOf(r, c);
          if (c > 0) out.write('\t');
          if (k < t.end) out.write(lines[k]);
        }
        out.write('\n');
      }
      l = t.end;
    }
    for (; l < lines.length; l++) {
      out.write(lines[l]);
      if (l + 1 < lines.length) out.write('\n');
    }
    var s = out.toString();
    if (l == lines.length && tables.isNotEmpty && tables.last.end == lines.length) {
      s = s.substring(0, s.length - 1); // No break after a final table.
    }
    return s;
  }
}
