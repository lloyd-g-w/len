import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../../../../ink/elements/text_layout.dart';

/// The tables of the box being edited for screen readers (UX_AUDIT
/// R26-16): a table node per table, a row node per row and a cell node per
/// cell (a column header in a header row) where it is laid out, reading
/// the cell's text and its row and column; tapping one edits it. The cell
/// being edited has no node here: its field is the node (see
/// [cellLabel]). Coordinates are the layer's (the box's, world units).
class TableEditorSemantics extends StatelessWidget {
  const TableEditorSemantics({
    super.key,
    required this.tables,
    required this.rows,
    required this.lines,
    required this.active,
    required this.onEnter,
  });

  final List<TableLayout> tables;
  final List<({Rect rect, int table, int row})> rows;

  /// The box's lines (a cell's text is its line).
  final List<String> lines;

  /// The line of the cell being edited, if any.
  final int? active;

  /// Edits the cell on a line.
  final ValueChanged<int> onEnter;

  /// What a cell's node (or the edited cell's field) is called besides its
  /// text: its row and column, and whether it heads its column.
  static String cellLabel(int row, int column, {required bool header}) =>
      header ? 'Column ${column + 1} header' : 'Row ${row + 1}, column ${column + 1}';

  @override
  Widget build(BuildContext context) => Stack(
    clipBehavior: Clip.none,
    children: [
      for (final (k, t) in tables.indexed)
        if (rows.where((r) => r.table == k).toList() case final own when own.isNotEmpty)
          Positioned.fromRect(
            rect: own.map((r) => r.rect).reduce((a, b) => a.expandToInclude(b)),
            child: Semantics(
              role: SemanticsRole.table,
              container: true,
              explicitChildNodes: true,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  for (final r in own)
                    Positioned.fromRect(
                      rect: r.rect.shift(-own.first.rect.topLeft),
                      child: _row(t, r),
                    ),
                ],
              ),
            ),
          ),
    ],
  );

  Widget _row(TableLayout t, ({Rect rect, int table, int row}) r) => Semantics(
    role: SemanticsRole.row,
    container: true,
    explicitChildNodes: true,
    child: Stack(
      clipBehavior: Clip.none,
      children: [
        for (var c = 0; c < t.table.columns; c++)
          if (t.table.lineOf(r.row, c) case final line when line != active)
            Positioned.fromRect(
              rect: t.cellRect(r.rect, r.row, c).shift(-r.rect.topLeft),
              child: _cell(t, r.row, c, line),
            ),
      ],
    ),
  );

  Widget _cell(TableLayout t, int row, int column, int line) {
    final header = t.table.spec.hasHeaderRow && row == 0;
    final text = line < t.table.end ? lines[line] : '';
    return Semantics(
      role: header ? SemanticsRole.columnHeader : SemanticsRole.cell,
      container: true,
      label: text,
      hint: cellLabel(row, column, header: header),
      onTap: line < t.table.end ? () => onEnter(line) : null,
      child: const SizedBox.expand(),
    );
  }
}
