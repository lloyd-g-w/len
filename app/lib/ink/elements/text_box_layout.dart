import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

import '../../domain/text/table_cells.dart';
import '../../domain/text/text_data.dart';
import '../fonts/text_fonts.dart';
import 'text_layout.dart';

/// [TextLayout] of one text box: a laid-out painter plus its list markers
/// and its [plan] (hanging indents, paragraphs of the other direction).
class TextBoxLayout {
  TextBoxLayout(TextData data, double width) : this.planned(data, width, TextPlan.of(data, width));

  /// [data] laid out by [plan] (made for it at [width]).
  TextBoxLayout.planned(this.data, double width, this.plan) {
    // Only the placeholders' sizes matter here; markers are painted
    // separately, gaps, padding, rooms and spacing stay empty.
    final dims = <PlaceholderDimensions>[];
    InlineSpan slot(Size size, PlaceholderAlignment alignment) {
      dims.add(
        PlaceholderDimensions(
          size: size,
          alignment: alignment,
          baseline: TextBaseline.alphabetic,
          baselineOffset: 0,
        ),
      );
      return WidgetSpan(
        alignment: alignment,
        baseline: TextBaseline.alphabetic,
        child: const SizedBox.shrink(),
      );
    }

    final span = TextLayout.spanOf(
      data,
      plan,
      marker: (m) {
        _markerSlots.add(dims.length);
        return slot(m.size, PlaceholderAlignment.middle);
      },
      gap: (size) => slot(size, PlaceholderAlignment.middle),
      room: (h) => slot(Size(0, h), PlaceholderAlignment.bottom),
      spacing: (h) {
        _spacingSlots.add(dims.length);
        return slot(Size(0, h), PlaceholderAlignment.belowBaseline);
      },
      row: (piece) {
        _rowSlots.add((slot: dims.length, table: piece.row!.table, row: piece.row!.row));
        return slot(piece.size, PlaceholderAlignment.bottom);
      },
    );
    painter = TextPainter(
      // An empty box still has one line's height.
      text: span.children!.isEmpty ? TextSpan(text: ' ', style: span.style) : span,
      textAlign: TextLayout.alignOf(data),
      textDirection: plan.base,
      strutStyle: TextLayout.strutOf(data),
    );
    painter.setPlaceholderDimensions(dims);
    if (width.isFinite) {
      final w = width < TextLayout.minWidth ? TextLayout.minWidth : width;
      painter.layout(minWidth: w, maxWidth: w);
    } else {
      painter.layout();
    }
  }

  final TextData data;
  final TextPlan plan;
  late final TextPainter painter;

  /// The list markers drawn, in line order (see [TextPlan.markers]).
  List<ListMarker> get markers => plan.markers;

  /// Model offsets where the plan continues a line on the next (see
  /// [TextPlan.wraps]).
  List<int> get wraps => plan.wraps;

  /// Model ↔ laid-out offsets of [painter]'s text.
  MarkerOffsets get offsets => plan.offsets;

  /// Indexes of the markers among the painter's placeholders.
  final List<int> _markerSlots = [];

  /// Indexes of the paragraph spacing among the painter's placeholders.
  final List<int> _spacingSlots = [];

  /// The table rows among the painter's placeholders.
  final List<({int slot, int table, int row})> _rowSlots = [];

  /// The tables laid out (see [TextPlan.tables]).
  List<TableLayout> get tables => plan.tables;

  /// Each table row laid out (local coordinates), in text order.
  List<({Rect rect, int table, int row})> get rows {
    final boxes = painter.inlinePlaceholderBoxes ?? const <TextBox>[];
    return [
      for (final r in _rowSlots)
        if (r.slot < boxes.length) (rect: boxes[r.slot].toRect(), table: r.table, row: r.row),
    ];
  }

  /// The cell on model line [line] if it is one: its table, where its
  /// text starts (local coordinates) and its layout.
  ({TableLayout table, int row, int column, Offset origin, TextBoxLayout layout})? cellOn(
    int line,
  ) {
    for (final t in tables) {
      if (!t.table.contains(line)) continue;
      final (:row, :column) = t.table.cellOf(line);
      final k = tables.indexOf(t);
      for (final r in rows) {
        if (r.table != k || r.row != row) continue;
        return (
          table: t,
          row: row,
          column: column,
          origin: t.textOrigin(r.rect, row, column),
          layout: t.cells[t.index(row, column)],
        );
      }
    }
    return null;
  }

  /// The table cell at [local] (box coordinates), if any: its model line
  /// and the model offset in it nearest [local].
  ({int line, int offset})? cellAt(Offset local) {
    for (final r in rows) {
      if (local.dy < r.rect.top || local.dy >= r.rect.bottom) continue;
      final t = tables[r.table];
      final column = t.columnAt(local.dx - r.rect.left);
      final line = t.table.lineOf(r.row, column);
      if (line >= t.table.end) return null;
      final cell = t.cells[t.index(r.row, column)];
      final origin = t.textOrigin(r.rect, r.row, column);
      final at = cell.painter.getPositionForOffset(local - origin).offset;
      return (line: line, offset: cell.offsets.toModel(at));
    }
    return null;
  }

  /// The room paragraph spacing leaves below each paragraph but the last
  /// (local coordinates): as wide as nothing, [TextData.paragraphGap] tall,
  /// ending at the bottom of the paragraph's last line.
  List<Rect> get spacing {
    final boxes = painter.inlinePlaceholderBoxes ?? const <TextBox>[];
    final gap = data.paragraphGap;
    return [
      for (final i in _spacingSlots)
        if (i < boxes.length)
          Rect.fromLTRB(boxes[i].left, boxes[i].bottom - gap, boxes[i].right, boxes[i].bottom),
    ];
  }

  /// How much of the line ending at [bottom] (local y) is paragraph
  /// spacing below its text (0 for most lines).
  double spacingAbove(double bottom) {
    for (final r in spacing) {
      if ((r.bottom - bottom).abs() < 0.5) return r.height;
    }
    return 0;
  }

  /// [box] (local coordinates, of text on one line) without the paragraph
  /// spacing below its line, which line-height boxes take in.
  Rect withoutSpacing(Rect box) {
    for (final r in spacing) {
      if (box.top < r.top && box.bottom > r.top) {
        return Rect.fromLTRB(box.left, box.top, box.right, r.top);
      }
    }
    return box;
  }

  /// The laid-out boxes of the model text [start, end) (without what the
  /// plan inserts into it).
  List<TextBox> boxesOf(
    int start,
    int end, {
    ui.BoxHeightStyle boxHeightStyle = ui.BoxHeightStyle.tight,
  }) => [
    for (final (from, to) in offsets.displayRanges(start, end))
      ...painter.getBoxesForSelection(
        TextSelection(baseOffset: from, extentOffset: to),
        boxHeightStyle: boxHeightStyle,
      ),
    if (tables.isNotEmpty) ..._cellBoxes(start, end, boxHeightStyle),
  ];

  /// [boxesOf] the table cells' text in [start, end).
  List<TextBox> _cellBoxes(int start, int end, ui.BoxHeightStyle style) {
    final out = <TextBox>[];
    final starts = data.lineStarts;
    for (final t in tables) {
      for (var line = t.table.line; line < t.table.end; line++) {
        final from = starts[line];
        final to = line + 1 < starts.length ? starts[line + 1] - 1 : data.text.length;
        if (to < start || from >= end || (from == to)) continue;
        final cell = cellOn(line);
        if (cell == null) continue;
        final a = math.max(start, from) - from, b = math.min(end, to) - from;
        if (b <= a) continue;
        for (final box in cell.layout.boxesOf(a, b, boxHeightStyle: style)) {
          final r = box.toRect().shift(cell.origin);
          out.add(TextBox.fromLTRBD(r.left, r.top, r.right, r.bottom, box.direction));
        }
      }
    }
    return out;
  }

  double get height => painter.height;

  /// The placeholder box of each of [markers] (local coordinates).
  List<Rect> get markerBoxes {
    final boxes = painter.inlinePlaceholderBoxes ?? const <TextBox>[];
    return [
      for (final i in _markerSlots)
        if (i < boxes.length) boxes[i].toRect(),
    ];
  }

  /// Paints the text with its top left at [origin].
  void paint(Canvas canvas, Offset origin) {
    painter.paint(canvas, origin);
    final laid = rows;
    for (var i = 0; i < laid.length; i++) {
      final r = laid[i];
      final t = tables[r.table];
      t.paintRow(canvas, r.rect.shift(origin), r.row, closed: r.row == t.table.rows - 1);
    }
    final boxes = markerBoxes;
    for (var i = 0; i < markers.length && i < boxes.length; i++) {
      markers[i].paint(
        canvas,
        boxes[i].shift(origin),
        number: (label, column) => paintNumber(canvas, markers[i], label, column),
      );
    }
  }

  /// The line of the checkbox at [local] (box coordinates), if any.
  int? checkboxAt(Offset local) {
    final boxes = markerBoxes;
    for (var i = 0; i < markers.length && i < boxes.length; i++) {
      final m = markers[i];
      if (m.para.list != ListKind.check) continue;
      if (m.checkbox(boxes[i]).inflate(m.fontSize * 0.3).contains(local)) return m.line;
    }
    return null;
  }

  /// Paints a numbered item's [label] in [column], next to the text.
  static void paintNumber(Canvas canvas, ListMarker marker, String label, Rect column) {
    final p = numberPainter(marker, label);
    p.paint(canvas, numberOrigin(marker, p, column));
    p.dispose();
  }

  /// Lays out a number label (the caller disposes it).
  static TextPainter numberPainter(ListMarker marker, String label) => TextPainter(
    text: TextSpan(
      text: label,
      style: TextStyle(
        inherit: false,
        fontFamily: TextFonts.familyOf(marker.font),
        fontFamilyFallback: TextLayout.fallback,
        fontSize: marker.fontSize,
        height: 1,
        color: Color(marker.color),
      ),
    ),
    // ("1." reads ".1" in a right-to-left paragraph.)
    textDirection: marker.direction,
  )..layout();

  /// Top left of a number label: at the column's text side (its right in a
  /// left-to-right paragraph), vertically centred.
  static Offset numberOrigin(ListMarker marker, TextPainter label, Rect column) {
    final inset = marker.fontSize * 0.35;
    return Offset(
      marker.direction == TextDirection.rtl
          ? column.left + inset
          : column.right - inset - label.width,
      column.center.dy - label.height / 2,
    );
  }

  void dispose() => painter.dispose();
}
