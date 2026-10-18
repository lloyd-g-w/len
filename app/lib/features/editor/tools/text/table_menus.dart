import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../../domain/text/text_data.dart';
import '../../../../ui/adaptive_popover.dart';
import '../../../../ui/app_theme.dart';
import '../../../../ui/menus.dart';
import 'rich_text_controller.dart';

/// What the table menu does to the table edited.
enum TableCommand {
  rowAbove('Insert row above', Symbols.add_row_above_sharp),
  rowBelow('Insert row below', Symbols.add_row_below_sharp),
  columnLeft('Insert column left', Symbols.add_column_left_sharp),
  columnRight('Insert column right', Symbols.add_column_right_sharp),
  header('Header row', Symbols.title_sharp),
  deleteRow('Delete row', Symbols.table_rows_narrow_sharp),
  deleteColumn('Delete column', Symbols.view_week_sharp),
  deleteTable('Delete table', Symbols.delete_sharp);

  const TableCommand(this.label, this.icon);

  final String label;
  final IconData icon;

  /// Runs it on [box] (the box's controller).
  void run(RichTextController box) => switch (this) {
    rowAbove => box.insertRow(below: false),
    rowBelow => box.insertRow(below: true),
    columnLeft => box.insertColumn(right: false),
    columnRight => box.insertColumn(right: true),
    header => box.toggleHeader(),
    deleteRow => box.removeRow(),
    deleteColumn => box.removeColumn(),
    deleteTable => box.removeTable(),
  };
}

/// The table menu's rows for the table [box] edits (destructive last).
List<PopupMenuEntry<TableCommand>> tableMenuItems(RichTextController box) {
  final place = box.activeCell ?? box.cellRange?.table;
  final t = place == null ? null : box.tableAt(place);
  final full = (t?.columns ?? 0) >= TableSpec.maxColumns;
  return [
    for (final c in TableCommand.values) ...[
      if (c == TableCommand.deleteRow) const PopupMenuDivider(),
      MenuRow(
        value: c,
        icon: c.icon,
        label: c.label,
        checked: c == TableCommand.header && (t?.spec.header ?? false),
        destructive: c.index >= TableCommand.deleteRow.index,
        enabled: !(full && (c == TableCommand.columnLeft || c == TableCommand.columnRight)),
      ),
    ],
  ];
}

/// The format bar's table button: outside a table it picks the size of a
/// new one ([showTablePicker]); in a table it opens the table menu.
class TableButton extends StatelessWidget {
  const TableButton({super.key, required this.box, required this.refocus});

  /// The box's controller.
  final RichTextController box;
  final VoidCallback refocus;

  @override
  Widget build(BuildContext context) {
    if (box.inTable) {
      return MenuIconButton<TableCommand>(
        key: const ValueKey('table-menu'),
        tooltip: 'Table',
        icon: const Icon(Symbols.table_sharp, size: Glyphs.bar, fill: 1),
        items: () => tableMenuItems(box),
        onSelected: (c) {
          c.run(box);
          refocus();
        },
      );
    }
    return IconButton(
      key: const ValueKey('insert-table'),
      tooltip: 'Insert table',
      icon: const Icon(Symbols.table_sharp, size: Glyphs.bar),
      onPressed: () => insertTableFromPicker(context, box, refocus),
    );
  }
}

/// Asks for a table's size and inserts it at [box]'s caret.
Future<void> insertTableFromPicker(
  BuildContext context,
  RichTextController box,
  VoidCallback refocus,
) async {
  final size = await showTablePicker(context);
  if (size != null) box.insertTable(size.rows, size.columns);
  refocus();
}

/// A grid to pick a new table's rows × columns from (a popover; a sheet
/// on phones).
Future<({int rows, int columns})?> showTablePicker(BuildContext context, {Rect? anchor}) =>
    showAdaptivePopover<({int rows, int columns})>(
      context: context,
      anchor: anchor,
      width: 280,
      builder: (context) => const TablePicker(),
    );

/// Rows × columns as a grid of cells: hovering (or dragging over) marks a
/// size, a tap picks it.
class TablePicker extends StatefulWidget {
  const TablePicker({super.key});

  static const int rows = 8, columns = 8;

  @override
  State<TablePicker> createState() => _TablePickerState();
}

class _TablePickerState extends State<TablePicker> {
  int _rows = 2, _columns = 2;

  /// Whether the grid shows the keyboard's focus.
  bool _highlight = false;

  void _mark(Offset local, double cell) {
    final r = (local.dy ~/ cell + 1).clamp(1, TablePicker.rows);
    final c = (local.dx ~/ cell + 1).clamp(1, TablePicker.columns);
    if (r == _rows && c == _columns) return;
    setState(() {
      _rows = r;
      _columns = c;
    });
  }

  void _pick() => Navigator.of(context).pop((rows: _rows, columns: _columns));

  static const Map<ShortcutActivator, Intent> _keys = {
    SingleActivator(LogicalKeyboardKey.arrowUp): _GrowIntent(-1, 0),
    SingleActivator(LogicalKeyboardKey.arrowDown): _GrowIntent(1, 0),
    SingleActivator(LogicalKeyboardKey.arrowLeft): _GrowIntent(0, -1),
    SingleActivator(LogicalKeyboardKey.arrowRight): _GrowIntent(0, 1),
  };

  void _grow(_GrowIntent g) => setState(() {
    _rows = (_rows + g.rows).clamp(1, TablePicker.rows);
    _columns = (_columns + g.columns).clamp(1, TablePicker.columns);
  });

  Widget _grid(double cell, ColorScheme scheme) => MouseRegion(
    onHover: (e) => _mark(e.localPosition, cell),
    child: GestureDetector(
      key: const ValueKey('table-picker-grid'),
      onTapDown: (d) => _mark(d.localPosition, cell),
      onTapUp: (_) => _pick(),
      onPanUpdate: (d) => _mark(d.localPosition, cell),
      onPanEnd: (_) => _pick(),
      child: SizedBox(
        width: cell * TablePicker.columns,
        height: cell * TablePicker.rows,
        child: CustomPaint(
          painter: _GridPainter(
            rows: _rows,
            columns: _columns,
            cell: cell,
            line: scheme.outlineVariant,
            fill: Surfaces.selected(scheme),
            mark: scheme.onSurface,
            focus: _highlight ? scheme.primary : null,
          ),
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final cell = Targets.touchFirst ? 30.0 : 26.0;
    // (The popover or sheet gives the room around it.)
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '$_rows × $_columns table',
          key: const ValueKey('table-picker-size'),
          style: theme.textTheme.labelLarge?.copyWith(fontFeatures: AppTheme.tabularFigures),
        ),
        const SizedBox(height: Gaps.sm),
        // Keyboards: arrows size the table, Enter picks it.
        FocusableActionDetector(
          autofocus: true,
          onShowFocusHighlight: (on) => setState(() => _highlight = on),
          shortcuts: _keys,
          actions: {
            _GrowIntent: CallbackAction<_GrowIntent>(onInvoke: _grow),
            ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => _pick()),
          },
          child: Semantics(
            label: 'Table size',
            value: '$_rows × $_columns',
            onTap: _pick,
            excludeSemantics: true,
            child: _grid(cell, scheme),
          ),
        ),
        const SizedBox(height: Gaps.sm),
        // Screen readers and keyboards: common sizes as buttons.
        Wrap(
          spacing: Gaps.xs,
          children: [
            for (final (r, c) in const [(2, 2), (3, 3), (4, 3)])
              TextButton(
                onPressed: () => Navigator.of(context).pop((rows: r, columns: c)),
                child: Text('$r × $c'),
              ),
          ],
        ),
      ],
    );
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter({
    required this.rows,
    required this.columns,
    required this.cell,
    required this.line,
    required this.fill,
    required this.mark,
    this.focus,
  });

  final int rows, columns;
  final double cell;
  final Color line, fill, mark;

  /// The keyboard focus ring's colour, when it shows.
  final Color? focus;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = line
      ..style = PaintingStyle.stroke
      ..strokeWidth = Hairline.width;
    final on = Paint()..color = fill;
    final edge = Paint()
      ..color = mark
      ..style = PaintingStyle.stroke
      ..strokeWidth = Hairline.width;
    for (var r = 0; r < TablePicker.rows; r++) {
      for (var c = 0; c < TablePicker.columns; c++) {
        final rect = Rect.fromLTWH(c * cell + 2, r * cell + 2, cell - 4, cell - 4);
        final picked = r < rows && c < columns;
        if (picked) canvas.drawRect(rect, on);
        canvas.drawRect(rect, picked ? edge : stroke);
      }
    }
    final ring = focus;
    if (ring != null) {
      canvas.drawRect(
        (Offset.zero & size).deflate(Hairline.rule / 2),
        Paint()
          ..color = ring
          ..style = PaintingStyle.stroke
          ..strokeWidth = Hairline.rule,
      );
    }
  }

  @override
  bool shouldRepaint(_GridPainter old) =>
      old.rows != rows || old.columns != columns || old.focus != focus;
}

class _GrowIntent extends Intent {
  const _GrowIntent(this.rows, this.columns);

  final int rows, columns;
}
