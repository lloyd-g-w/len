import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../../domain/text/text_data.dart';
import '../../../../ink/elements/text_layout.dart';
import 'rich_text_controller.dart';

/// Keys moving between table cells while one is edited, and keys of a block
/// of cells selected:
///
/// - Tab / Shift+Tab: the next / previous cell (Tab in the last cell adds a
///   row);
/// - Enter: the cell below (from the last row, the line after the table);
/// - arrows at a cell's edge (its first or last line, its start or end):
///   the cell beyond, or the text before or after the table; with Shift
///   they select a block of cells;
/// - with a block selected: Ctrl+C / Ctrl+X copy and cut it (an HTML table
///   and tab-separated text), Delete / Backspace empty its cells, Shift +
///   arrows grow it, arrows or Esc go back to editing a cell, Ctrl+B / I /
///   U format every cell, Ctrl+Z undoes.
abstract final class TableKeys {
  static bool get _shift => HardwareKeyboard.instance.isShiftPressed;
  static bool get _command =>
      HardwareKeyboard.instance.isControlPressed || HardwareKeyboard.instance.isMetaPressed;
  static bool get _alt => HardwareKeyboard.instance.isAltPressed;

  /// A key in the field of the cell [cell] edits in the box of [box].
  static KeyEventResult cell(RichTextController box, TableCellController cell, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
    final line = box.activeCell;
    final t = line == null ? null : box.tableAt(line);
    if (line == null || t == null || _command || _alt) return KeyEventResult.ignored;
    final composing = cell.value.composing;
    if (composing.isValid && !composing.isCollapsed) return KeyEventResult.ignored;
    final (:row, :column) = t.cellOf(line);
    final s = cell.selection;
    final key = event.logicalKey;
    final handled = switch (key) {
      LogicalKeyboardKey.tab => _shift ? _step(box, t, row, column, -1) : _tab(box, t, row, column),
      LogicalKeyboardKey.enter ||
      LogicalKeyboardKey.numpadEnter when !_shift => _down(box, t, row, column),
      LogicalKeyboardKey.arrowUp when _edge(cell, up: true) => _vertical(box, t, row, column, -1),
      LogicalKeyboardKey.arrowDown when _edge(cell, up: false) => _vertical(box, t, row, column, 1),
      LogicalKeyboardKey.arrowLeft || LogicalKeyboardKey.arrowRight => _sideways(
        box,
        cell,
        t,
        row,
        column,
        forward:
            (key == LogicalKeyboardKey.arrowRight) == (cell.extentDirection == TextDirection.ltr),
        visualRight: key == LogicalKeyboardKey.arrowRight,
        selection: s,
      ),
      _ => false,
    };
    return handled ? KeyEventResult.handled : KeyEventResult.ignored;
  }

  /// Tab: the next cell; in the last one a new row's first cell.
  static bool _tab(RichTextController box, TextTable t, int row, int column) {
    if (row == t.rows - 1 && column == t.columns - 1) {
      box.insertRow(below: true);
      final next = box.tableAt(t.line);
      if (next != null) box.enterCell(next.lineOf(row + 1, 0));
      return true;
    }
    return _step(box, t, row, column, 1);
  }

  /// The cell [delta] cells on in reading order (none past the ends).
  static bool _step(RichTextController box, TextTable t, int row, int column, int delta) {
    final k = row * t.columns + column + delta;
    if (k < 0 || k >= t.cells) return true;
    box.enterCell(t.line + k);
    return true;
  }

  /// Enter: the cell below, from the last row the line after the table.
  static bool _down(RichTextController box, TextTable t, int row, int column) {
    if (row + 1 < t.rows) {
      box.enterCell(t.lineOf(row + 1, column).clamp(t.line, t.end - 1));
      return true;
    }
    box.leaveTable(t, after: true);
    return true;
  }

  static bool _vertical(RichTextController box, TextTable t, int row, int column, int delta) {
    if (_shift) return _extend(box, t, row, column, row + delta, column);
    final r = row + delta;
    if (r < 0 || r >= t.rows) {
      box.leaveTable(t, after: delta > 0);
      return true;
    }
    box.enterCell(t.lineOf(r, column).clamp(t.line, t.end - 1), atEnd: delta < 0);
    return true;
  }

  static bool _sideways(
    RichTextController box,
    TableCellController cell,
    TextTable t,
    int row,
    int column, {
    required bool forward,
    required bool visualRight,
    required TextSelection selection,
  }) {
    if (!selection.isValid) return false;
    final atEdge = forward
        ? selection.extentOffset >= cell.text.length
        : selection.extentOffset <= 0;
    if (!atEdge || (!_shift && !selection.isCollapsed)) return false;
    // Columns run in the box's direction.
    final rtl = box.plan.base == TextDirection.rtl;
    final nextColumn = column + ((visualRight != rtl) ? 1 : -1);
    if (_shift) {
      if (nextColumn < 0 || nextColumn >= t.columns) return true;
      return _extend(box, t, row, column, row, nextColumn);
    }
    final k = row * t.columns + column + (forward ? 1 : -1);
    if (k < 0 || k >= t.cells) {
      box.leaveTable(t, after: forward);
      return true;
    }
    box.enterCell(t.line + k, atEnd: !forward);
    return true;
  }

  /// Shift+arrow past a cell's edge: a block from it to the cell beyond.
  static bool _extend(RichTextController box, TextTable t, int row, int column, int r, int c) {
    if (r < 0 || r >= t.rows || c < 0 || c >= t.columns) return true;
    box.selectCells(TableRange(t.line, (row: row, column: column), (row: r, column: c)));
    return true;
  }

  /// Whether the caret of [cell] is on its first (or last) laid-out line.
  static bool _edge(TableCellController cell, {required bool up}) {
    final s = cell.selection;
    if (!s.isValid) return false;
    final layout = TextBoxLayout.planned(cell.data, cell.wrapWidth, cell.plan);
    final lines = layout.painter.computeLineMetrics();
    final y = layout.painter.getOffsetForCaret(TextPosition(offset: s.extentOffset), Rect.zero).dy;
    final height = layout.height;
    layout.dispose();
    if (lines.length < 2) return true;
    return up ? y < lines.first.height - 0.5 : y >= height - lines.last.height - 0.5;
  }

  /// A key while a block of cells of [box] is selected; Ctrl+Z / Ctrl+Y
  /// [undo] and [redo].
  static KeyEventResult range(
    RichTextController box,
    KeyEvent event, {
    required VoidCallback undo,
    required VoidCallback redo,
  }) {
    final r = box.cellRange;
    if (r == null || (event is! KeyDownEvent && event is! KeyRepeatEvent)) {
      return KeyEventResult.ignored;
    }
    final t = box.tableAt(r.table);
    if (t == null) return KeyEventResult.ignored;
    final key = event.logicalKey;
    if (_command) {
      switch (key) {
        case LogicalKeyboardKey.keyC:
          box.copySelection();
        case LogicalKeyboardKey.keyX:
          box.copySelection(cut: true);
        case LogicalKeyboardKey.keyB:
          box.toggleBold();
        case LogicalKeyboardKey.keyI:
          box.toggleItalic();
        case LogicalKeyboardKey.keyU:
          box.toggleUnderline();
        case LogicalKeyboardKey.keyZ:
          _shift ? redo() : undo();
        case LogicalKeyboardKey.keyY:
          redo();
        default:
          return KeyEventResult.ignored;
      }
      return KeyEventResult.handled;
    }
    final e = r.extent;
    final rtl = box.plan.base == TextDirection.rtl;
    final (dr, dc) = switch (key) {
      LogicalKeyboardKey.arrowUp => (-1, 0),
      LogicalKeyboardKey.arrowDown => (1, 0),
      LogicalKeyboardKey.arrowLeft => (0, rtl ? 1 : -1),
      LogicalKeyboardKey.arrowRight => (0, rtl ? -1 : 1),
      _ => (0, 0),
    };
    if (dr != 0 || dc != 0) {
      final row = (e.row + dr).clamp(0, t.rows - 1),
          column = (e.column + dc).clamp(0, t.columns - 1);
      if (_shift) {
        box.selectCells(r.extendedTo(row, column));
      } else {
        box.enterCell(t.lineOf(row, column).clamp(t.line, t.end - 1));
      }
      return KeyEventResult.handled;
    }
    switch (key) {
      case LogicalKeyboardKey.delete || LogicalKeyboardKey.backspace:
        box.clearCells();
      case LogicalKeyboardKey.escape:
        box.enterCell(t.lineOf(r.anchor.row, r.anchor.column).clamp(t.line, t.end - 1));
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }
}
