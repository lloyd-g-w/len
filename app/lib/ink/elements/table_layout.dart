import 'dart:math' as math;
import 'dart:ui';

import '../../domain/text/table_cells.dart';
import '../../domain/text/text_data.dart';
import 'text_box_layout.dart';
import 'text_wraps.dart';

/// A table of a text box laid out: each cell on its own (a one-line
/// [TextData], see [TableCells.cellData]) at its column's width less the
/// cell padding, rows as tall as their tallest cell. In the box's own
/// paragraph each row is one placeholder [width] wide and [rowHeights] tall
/// (see [InsertKind.row]); [paintRow] draws a row's cells and grid there.
///
/// Columns run in the box's [direction]: the first on the right of a
/// right-to-left box.
class TableLayout {
  TableLayout(this.data, this.table, double width, {required this.direction, List<int>? starts})
    : width = width.isFinite ? math.max(1, width - TextWraps.epsilon) : naturalWidth(data, table) {
    final lineStarts = starts ?? data.lineStarts;
    final padX = cellPadX(data), padY = cellPadY(data);
    for (var r = 0; r < table.rows; r++) {
      var tallest = 0.0;
      for (var c = 0; c < table.columns; c++) {
        final line = table.lineOf(r, c);
        final cell = line < table.end
            ? data.cellData(line, start: lineStarts[line])
            : _empty(data, header: table.spec.hasHeaderRow && r == 0);
        final layout = TextBoxLayout(cell, math.max(1, columnWidth(c) - 2 * padX));
        cells.add(layout);
        tallest = math.max(tallest, layout.height);
      }
      rowHeights.add(tallest + 2 * padY);
    }
  }

  final TextData data;
  final TextTable table;
  final TextDirection direction;

  /// The table's width, in world units.
  final double width;

  /// Each cell's layout, row by row ([index]).
  final List<TextBoxLayout> cells = [];
  final List<double> rowHeights = [];

  /// Width a table gets where the box sets none (auto-width boxes
  /// measuring their text): this many ems per column.
  static const double naturalColumnEms = 6;

  static double naturalWidth(TextData data, TextTable table) =>
      data.fontSize * naturalColumnEms * table.columns;

  /// Room between a cell's border and its text.
  static double cellPadX(TextData data) => data.fontSize * 0.4;
  static double cellPadY(TextData data) => data.fontSize * 0.25;

  /// Width of the grid's lines.
  static double lineWidthOf(TextData data) => math.max(0.5, data.fontSize / 24);

  /// The grid's colour: the text colour, faint.
  static Color gridColorOf(TextData data) {
    final c = Color(data.color);
    return c.withValues(alpha: c.a * 0.3);
  }

  int index(int row, int column) => row * table.columns + column;

  double columnWidth(int column) => table.spec.widths[column] * width;

  /// The left edge of [column] (table coordinates).
  double columnLeft(int column) {
    var x = 0.0;
    for (var c = 0; c < column; c++) {
      x += columnWidth(c);
    }
    return direction == TextDirection.rtl ? width - x - columnWidth(column) : x;
  }

  /// The column at [x] (table coordinates; clamped to the table).
  int columnAt(double x) {
    for (var c = 0; c < table.columns; c++) {
      final left = columnLeft(c);
      if (x >= left && x < left + columnWidth(c)) return c;
    }
    return (x < width / 2) == (direction == TextDirection.ltr) ? 0 : table.columns - 1;
  }

  /// The x of the border after [column] in the box's direction (table
  /// coordinates): what dragging it moves.
  double borderAfter(int column) => direction == TextDirection.rtl
      ? columnLeft(column)
      : columnLeft(column) + columnWidth(column);

  /// Cell [row], [column] in a row laid out at [rowRect].
  Rect cellRect(Rect rowRect, int row, int column) => Rect.fromLTWH(
    rowRect.left + columnLeft(column),
    rowRect.top,
    columnWidth(column),
    rowRect.height,
  );

  /// The top left of the text of cell [row], [column] in a row at [rowRect].
  Offset textOrigin(Rect rowRect, int row, int column) =>
      cellRect(rowRect, row, column).topLeft + Offset(cellPadX(data), cellPadY(data));

  /// Paints row [row] laid out at [rowRect]: its cells' text, the borders around them, and the line
  /// below unless the next row follows ([closed] false).
  void paintRow(Canvas canvas, Rect rowRect, int row, {required bool closed}) {
    for (var c = 0; c < table.columns; c++) {
      cells[index(row, c)].paint(canvas, textOrigin(rowRect, row, c));
    }
    final paint = Paint()
      ..color = gridColorOf(data)
      ..strokeWidth = lineWidthOf(data)
      ..style = PaintingStyle.stroke;
    final left = rowRect.left, right = rowRect.left + width;
    canvas.drawLine(Offset(left, rowRect.top), Offset(right, rowRect.top), paint);
    if (closed) {
      canvas.drawLine(Offset(left, rowRect.bottom), Offset(right, rowRect.bottom), paint);
    }
    // Every column's left edge, and the table's right edge.
    for (var c = 0; c <= table.columns; c++) {
      final x = c == table.columns ? right : rowRect.left + columnLeft(c);
      canvas.drawLine(Offset(x, rowRect.top), Offset(x, rowRect.bottom), paint);
    }
  }

  static TextData _empty(TextData data, {required bool header}) => TextData.rich(
    text: '',
    paras: [ParaStyle(bold: header)],
    font: data.font,
    fontSize: data.fontSize,
    color: data.color,
    align: data.align,
  );
}
