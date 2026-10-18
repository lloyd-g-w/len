import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../../../domain/text/text_data.dart';
import '../../../../ink/elements/text_layout.dart';
import '../../../../ui/app_theme.dart';
import 'rich_paste.dart';
import 'rich_text_controller.dart';
import 'rich_text_field.dart';
import 'table_keys.dart';

/// The tables of the box being edited, over its field (in world units,
/// laid out as the box renders): their cells and grid painted, the cell
/// being edited in its own [RichTextField] (with [cell]), taps that edit a
/// cell, drags across cells that select a block of them, and grips on the
/// column borders that resize columns (stylus, finger or mouse; [gripWidth]
/// across, a short accent tick on the edited row's marking them).
class TableEditorLayer extends StatefulWidget {
  const TableEditorLayer({
    super.key,
    required this.box,
    required this.cell,
    required this.cellFocus,
    required this.rangeFocus,
    required this.scale,
    required this.cursorWidth,
    required this.accent,
    required this.onDone,
    this.onUndo,
    this.onRedo,
  });

  /// The box's controller and the edited cell's.
  final RichTextController box;
  final TableCellController cell;
  final FocusNode cellFocus;

  /// Has the focus while a block of cells is selected (its keys).
  final FocusNode rangeFocus;

  /// Screen pixels per world unit.
  final double scale;
  final double cursorWidth;
  final Color accent;
  final VoidCallback onDone;
  final VoidCallback? onUndo, onRedo;

  /// Width of a column border's grip in screen pixels, by input as shape
  /// handles are: a fingertip's on touch-first devices, else a pointer's.
  /// Taps on a grip still go to the cell under it, so a wide grip never
  /// keeps a tap off the text beside the border.
  static double get gripWidth => Targets.touchFirst ? 24 : 16;

  @override
  State<TableEditorLayer> createState() => _TableEditorLayerState();
}

/// A cell under a point: its table (index and layout), row, column, line
/// and the model offset in it nearest the point.
typedef _Hit = ({int table, int row, int column, int line, int offset});

class _TableEditorLayerState extends State<TableEditorLayer> {
  List<({Rect rect, int table, int row})> _rows = const [];
  List<TableLayout> _tables = const [];

  /// The cell a pointer went down on (null: none, or a column grip).
  _Hit? _down;

  /// The cell under a column grip a pointer went down on, and where:
  /// entered on a tap (no drag).
  ({_Hit? cell, Offset at})? _downOnGrip;
  bool _downInActive = false;
  bool _selecting = false;

  /// Column resizing: the table's widths when the drag began, and where.
  List<double>? _dragWidths;
  int _dragTable = 0;
  double _dragX = 0;

  RichTextController get _box => widget.box;

  double get _grip => TableEditorLayer.gripWidth / widget.scale;

  _Hit? _hit(Offset local) {
    for (final r in _rows) {
      if (local.dy < r.rect.top || local.dy >= r.rect.bottom) continue;
      final t = _tables[r.table];
      final column = t.columnAt(local.dx - r.rect.left);
      final line = t.table.lineOf(r.row, column);
      if (line >= t.table.end) return null;
      final cell = t.cells[t.index(r.row, column)];
      final at = cell.painter.getPositionForOffset(local - t.textOrigin(r.rect, r.row, column));
      return (
        table: r.table,
        row: r.row,
        column: column,
        line: line,
        offset: cell.offsets.toModel(at.offset),
      );
    }
    return null;
  }

  bool _onGrip(Offset local) {
    for (final r in _rows) {
      if (!r.rect.contains(local)) continue;
      final t = _tables[r.table];
      for (var c = 0; c + 1 < t.table.columns; c++) {
        if ((local.dx - r.rect.left - t.borderAfter(c)).abs() <= _grip / 2) return true;
      }
    }
    return false;
  }

  void _pointerDown(PointerDownEvent e) {
    _selecting = false;
    _downOnGrip = null;
    if (_onGrip(e.localPosition)) {
      _down = null;
      _downOnGrip = (cell: _hit(e.localPosition), at: e.position);
      return;
    }
    _down = _hit(e.localPosition);
    _downInActive = _down != null && _down!.line == _box.activeCell;
  }

  void _pointerMove(PointerMoveEvent e) {
    final down = _down;
    if (down == null) return;
    final now = _hit(e.localPosition);
    if (now == null || now.table != down.table) return;
    if (!_selecting && now.line == down.line) return;
    _selecting = true;
    final t = _tables[down.table].table;
    _box.selectCells(
      TableRange(t.line, (row: down.row, column: down.column), (row: now.row, column: now.column)),
    );
    widget.rangeFocus.requestFocus();
  }

  void _pointerUp(PointerUpEvent e) {
    final onGrip = _downOnGrip;
    _downOnGrip = null;
    if (onGrip != null) {
      final cell = onGrip.cell;
      final tap = (e.position - onGrip.at).distance < computeHitSlop(e.kind, null);
      if (tap && cell != null) _box.enterCell(cell.line, offset: cell.offset);
      return;
    }
    final down = _down;
    _down = null;
    if (down == null || _selecting || _downInActive) return;
    _box.enterCell(down.line, offset: down.offset);
  }

  void _dragStart(TableLayout t, DragStartDetails d) {
    _dragWidths = [...t.table.spec.widths];
    _dragTable = t.table.line;
    _dragX = _local(d.globalPosition).dx;
  }

  void _dragUpdate(TableLayout t, int column, DragUpdateDetails d) {
    final start = _dragWidths;
    if (start == null) return;
    var share = (_local(d.globalPosition).dx - _dragX) / t.width;
    if (t.direction == TextDirection.rtl) share = -share;
    final pair = start[column] + start[column + 1];
    final a = (start[column] + share).clamp(TableSpec.minShare, pair - TableSpec.minShare);
    final widths = [...start]
      ..[column] = a
      ..[column + 1] = pair - a;
    _box.previewWidths(t.table.line, widths);
  }

  void _dragEnd() {
    final start = _dragWidths;
    if (start == null) return;
    _dragWidths = null;
    // A border dragged back where it was is no step to undo.
    final now = _box.tableAt(_dragTable)?.spec.widths;
    if (now != null && listEquals(now, start)) return;
    _box.commitWidths();
  }

  /// [character] typed with a block of cells selected: it replaces the
  /// block's first cell, which is then edited.
  void _typeOver(String character) {
    final r = _box.cellRange;
    final t = r == null ? null : _box.tableAt(r.table);
    if (r == null || t == null) return;
    _box.enterCell(t.lineOf(r.top, r.left));
    final cell = widget.cell;
    if (cell.line == null) return;
    cell.value = TextEditingValue(
      text: character,
      selection: TextSelection.collapsed(offset: character.length),
    );
  }

  Offset _local(Offset global) => (context.findRenderObject()! as RenderBox).globalToLocal(global);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _box,
    builder: (context, _) {
      final plan = _box.plan;
      if (plan.tables.isEmpty) return const SizedBox.shrink();
      final layout = TextBoxLayout.planned(_box.data, _box.wrapWidth, plan);
      _rows = layout.rows;
      layout.dispose();
      _tables = plan.tables;
      final active = _box.activeCell;
      final place = active == null ? null : _placeOf(active);
      final range = _box.cellRange;
      return TextFieldTapRegion(
        child: Focus(
          focusNode: widget.rangeFocus,
          onKeyEvent: (node, event) => TableKeys.range(
            _box,
            event,
            undo: widget.onUndo ?? () => _box.undo(),
            redo: widget.onRedo ?? () => _box.redo(),
            paste: ({required plain}) => pasteIntoCells(widget.cell, plain: plain),
            type: _typeOver,
          ),
          child: Listener(
            behavior: HitTestBehavior.translucent,
            onPointerDown: _pointerDown,
            onPointerMove: _pointerMove,
            onPointerUp: _pointerUp,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                // The rows take their own taps (not the field below).
                for (final r in _rows)
                  Positioned.fromRect(
                    rect: r.rect,
                    child: const MouseRegion(
                      cursor: SystemMouseCursors.text,
                      child: Listener(behavior: HitTestBehavior.opaque, child: SizedBox.expand()),
                    ),
                  ),
                Positioned.fill(
                  child: IgnorePointer(
                    child: CustomPaint(
                      painter: _TablesPainter(
                        _tables,
                        _rows,
                        active: place,
                        range: range,
                        highlight: widget.accent.withValues(alpha: 0.18),
                        accent: widget.accent,
                        scale: widget.scale,
                      ),
                    ),
                  ),
                ),
                if (place != null) _field(place),
                ..._grips(),
              ],
            ),
          ),
        ),
      );
    },
  );

  /// Where the cell on [line] is laid out: its table, row, column, rect.
  ({int table, int row, int column, Rect rowRect})? _placeOf(int line) {
    for (final r in _rows) {
      final t = _tables[r.table].table;
      if (!t.contains(line)) continue;
      final (:row, :column) = t.cellOf(line);
      if (row == r.row) return (table: r.table, row: row, column: column, rowRect: r.rect);
    }
    return null;
  }

  Widget _field(({int table, int row, int column, Rect rowRect}) p) {
    final t = _tables[p.table];
    final origin = t.textOrigin(p.rowRect, p.row, p.column);
    final width = math.max(1.0, t.columnWidth(p.column) - 2 * TableLayout.cellPadX(t.data));
    return Positioned(
      left: origin.dx,
      top: origin.dy,
      width: width + RichTextField.caretMargin(widget.cursorWidth),
      child: Semantics(
        label: 'Row ${p.row + 1}, column ${p.column + 1}',
        child: RichTextField(
          controller: widget.cell,
          focusNode: widget.cellFocus,
          cursorWidth: widget.cursorWidth,
          cursorColor: widget.accent,
          onDone: widget.onDone,
          onUndo: widget.onUndo,
          onRedo: widget.onRedo,
          onKey: (node, event) => TableKeys.cell(_box, widget.cell, event),
        ),
      ),
    );
  }

  /// Grips on the borders between columns.
  List<Widget> _grips() => [
    for (final r in _rows)
      for (var c = 0; c + 1 < _tables[r.table].table.columns; c++)
        Positioned(
          left: r.rect.left + _tables[r.table].borderAfter(c) - _grip / 2,
          top: r.rect.top,
          width: _grip,
          height: r.rect.height,
          child: MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: GestureDetector(
              key: ValueKey('table-border-${r.table}-$c-${r.row}'),
              behavior: HitTestBehavior.opaque,
              onHorizontalDragStart: (d) => _dragStart(_tables[r.table], d),
              onHorizontalDragUpdate: (d) => _dragUpdate(_tables[r.table], c, d),
              onHorizontalDragEnd: (_) => _dragEnd(),
              onHorizontalDragCancel: _dragEnd,
            ),
          ),
        ),
  ];
}

/// Paints the tables' rows (but the cell edited in its field), the block
/// of cells selected and a tick on each column border of the edited row
/// (where its grips are).
class _TablesPainter extends CustomPainter {
  _TablesPainter(
    this.tables,
    this.rows, {
    required this.active,
    required this.range,
    required this.highlight,
    required this.accent,
    required this.scale,
  });

  final List<TableLayout> tables;
  final List<({Rect rect, int table, int row})> rows;
  final ({int table, int row, int column, Rect rowRect})? active;
  final TableRange? range;
  final Color highlight, accent;
  final double scale;

  @override
  void paint(Canvas canvas, Size size) {
    for (final r in rows) {
      final t = tables[r.table];
      final a = active;
      final skip = a != null && a.table == r.table && a.row == r.row ? a.column : null;
      t.paintRow(canvas, r.rect, r.row, closed: r.row == t.table.rows - 1, skipColumn: skip);
      if (skip != null) _paintTicks(canvas, t, r.rect);
      final b = range;
      if (b == null || b.table != t.table.line) continue;
      for (var c = 0; c < t.table.columns; c++) {
        if (b.contains(r.row, c)) {
          canvas.drawRect(t.cellRect(r.rect, r.row, c), Paint()..color = highlight);
        }
      }
    }
  }

  /// A short accent tick on each border between columns of [rowRect].
  void _paintTicks(Canvas canvas, TableLayout t, Rect rowRect) {
    final half = math.min(Gaps.md / scale, rowRect.height * 0.6) / 2;
    final tick = Paint()
      ..color = accent
      ..strokeWidth = Hairline.rule / scale;
    for (var c = 0; c + 1 < t.table.columns; c++) {
      final x = rowRect.left + t.borderAfter(c);
      canvas.drawLine(
        Offset(x, rowRect.center.dy - half),
        Offset(x, rowRect.center.dy + half),
        tick,
      );
    }
  }

  @override
  bool shouldRepaint(_TablesPainter old) => true;
}
