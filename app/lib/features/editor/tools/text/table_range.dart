import '../../../../domain/text/text_data.dart';

/// A block of cells selected in a table of the box being edited: from the
/// [anchor] cell (where the selection began) to the [extent] cell, of the
/// table whose first cell is on line [table].
class TableRange {
  const TableRange(this.table, this.anchor, this.extent);

  /// The line of the table's first cell.
  final int table;
  final ({int row, int column}) anchor, extent;

  int get top => anchor.row < extent.row ? anchor.row : extent.row;
  int get bottom => anchor.row > extent.row ? anchor.row : extent.row;
  int get left => anchor.column < extent.column ? anchor.column : extent.column;
  int get right => anchor.column > extent.column ? anchor.column : extent.column;

  bool contains(int row, int column) =>
      row >= top && row <= bottom && column >= left && column <= right;

  /// The lines of its cells in [t] (the table it selects in), row by row.
  List<int> lines(TextTable t) => [
    for (var r = top; r <= bottom; r++)
      for (var c = left; c <= right; c++)
        if (t.lineOf(r, c) < t.end) t.lineOf(r, c),
  ];

  /// The same block with its extent at [row], [column].
  TableRange extendedTo(int row, int column) =>
      TableRange(table, anchor, (row: row, column: column));

  @override
  bool operator ==(Object other) =>
      other is TableRange &&
      other.table == table &&
      other.anchor == anchor &&
      other.extent == extent;

  @override
  int get hashCode => Object.hash(table, anchor, extent);
}
