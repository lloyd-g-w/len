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
///
/// A table going on from the page before ([TableSpec.continued]) whose
/// header row the box repeats (`TextFlow.header`) draws that row in a
/// [band] at the top of its first row, above its cells (display only).
class TableLayout {
  TableLayout(this.data, this.table, double width, {required this.direction, List<int>? starts})
    : width = width.isFinite ? math.max(1, width - TextWraps.epsilon) : naturalWidth(data, table) {
    final lineStarts = starts ?? data.lineStarts;
    final padX = cellPadX(data), padY = cellPadY(data);
    final repeat = data.flow?.header ?? const [];
    if (table.line == 0 && table.spec.continued && table.spec.header) {
      if (repeat.length == table.columns) {
        var tallest = 0.0;
        for (var c = 0; c < table.columns; c++) {
          final cell = TextData.rich(
            text: repeat[c].text,
            spans: repeat[c].spans,
            paras: const [ParaStyle(bold: true)],
            font: data.font,
            fontSize: data.fontSize,
            color: data.color,
            align: data.align,
          );
          final layout = TextBoxLayout(cell, math.max(1, columnWidth(c) - 2 * padX));
          headerCells.add(layout);
          tallest = math.max(tallest, layout.height);
        }
        band = tallest + 2 * padY;
      }
    }
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
      rowHeights.add(tallest + 2 * padY + (r == 0 ? band : 0));
    }
  }

  /// The header row repeated above the first row (see the class doc), one
  /// layout per column; none if not repeated.
  final List<TextBoxLayout> headerCells = [];

  /// The height of the header row repeated (0: none).
  double band = 0;

  /// The height of the table's header row, laid out here or repeated
  /// ([band]); 0 if neither.
  double get headerHeight => band > 0
      ? band
      : table.spec.hasHeaderRow && rowHeights.isNotEmpty
      ? rowHeights.first
      : 0;

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

  /// Cell [row], [column] in a row laid out at [rowRect] (below the
  /// header [band] in the first row).
  Rect cellRect(Rect rowRect, int row, int column) {
    final above = row == 0 ? band : 0.0;
    return Rect.fromLTWH(
      rowRect.left + columnLeft(column),
      rowRect.top + above,
      columnWidth(column),
      rowRect.height - above,
    );
  }

  /// The top left of the text of cell [row], [column] in a row at [rowRect].
  Offset textOrigin(Rect rowRect, int row, int column) =>
      cellRect(rowRect, row, column).topLeft + Offset(cellPadX(data), cellPadY(data));

  /// Paints row [row] laid out at [rowRect]: its cells' text (but
  /// [skipColumn]'s), the borders around them, and the line
  /// below unless the next row follows ([closed] false).
  void paintRow(Canvas canvas, Rect rowRect, int row, {required bool closed, int? skipColumn}) {
    if (row == 0) {
      for (var c = 0; c < headerCells.length; c++) {
        final at =
            Offset(rowRect.left + columnLeft(c), rowRect.top) +
            Offset(cellPadX(data), cellPadY(data));
        headerCells[c].paint(canvas, at);
      }
    }
    for (var c = 0; c < table.columns; c++) {
      if (c == skipColumn) continue; // (Edited in its own field.)
      cells[index(row, c)].paint(canvas, textOrigin(rowRect, row, c));
    }
    final paint = Paint()
      ..color = gridColorOf(data)
      ..strokeWidth = lineWidthOf(data)
      ..style = PaintingStyle.stroke;
    final left = rowRect.left, right = rowRect.left + width;
    canvas.drawLine(Offset(left, rowRect.top), Offset(right, rowRect.top), paint);
    if (row == 0 && band > 0) {
      final y = rowRect.top + band;
      canvas.drawLine(Offset(left, y), Offset(right, y), paint);
    }
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
