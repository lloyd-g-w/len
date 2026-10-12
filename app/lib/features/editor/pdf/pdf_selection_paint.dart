import 'package:flutter/material.dart';

import '../../../ui/app_theme.dart';
import 'pdf_interaction.dart';
import 'pdf_page_info.dart';
import 'pdf_text_tool.dart';

/// Places the selection's menu above the [selected] lines (screen box),
/// below them if the top of the screen (above [roomAbove]) is too close,
/// kept on screen whatever its size.
class PdfMenuPlacement extends SingleChildLayoutDelegate {
  PdfMenuPlacement(this.selected, {required this.roomAbove});

  final Rect selected;
  final double roomAbove;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) => constraints.loosen();

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final maxLeft = size.width - childSize.width - Gaps.sm;
    final left = (selected.left - 24).clamp(Gaps.sm, maxLeft < Gaps.sm ? Gaps.sm : maxLeft);
    final above = selected.top - childSize.height - 24;
    final below = selected.bottom + 20;
    final maxTop = size.height - childSize.height - Gaps.sm;
    return Offset(left, above >= roomAbove ? above : (below < maxTop ? below : maxTop));
  }

  @override
  bool shouldRelayout(PdfMenuPlacement old) =>
      old.selected != selected || old.roomAbove != roomAbove;
}

/// Paints the selected lines (and, with the Select text tool, the handles).
class PdfSelectionPainter extends CustomPainter {
  PdfSelectionPainter(this.pdf, this.color, {required this.handles});

  final PdfInteraction pdf;
  final Color color;
  final bool handles;

  @override
  void paint(Canvas canvas, Size size) {
    final selection = pdf.selection;
    final page = selection.page;
    if (page == null || selection.isEmpty) return;
    final doc = pdf.doc;
    final index = doc.pages.indexWhere((p) => p.id == page.id);
    final frame = index < 0 ? null : doc.layout.frameOf(index);
    if (frame == null) return;
    final fill = Paint()..color = color.withValues(alpha: 0.28);
    for (final r in selection.rects) {
      final a = doc.viewport.toScreen(
        frame.topLeft + Offset(r.left * frame.width, r.top * frame.height),
      );
      final b = doc.viewport.toScreen(
        frame.topLeft + Offset(r.right * frame.width, r.bottom * frame.height),
      );
      canvas.drawRect(Rect.fromPoints(a, b), fill);
    }
    final ends = PdfTextTool.handleEnds(pdf);
    if (!handles || ends == null) return;
    final solid = Paint()
      ..color = color
      ..strokeWidth = 2;
    final lines = selection.lines;
    final scale = doc.viewport.scale;
    // Bars across the line (from the top of its letters to their bottom),
    // knobs beyond: the start's above the text, the end's below.
    Offset bar(PdfTextLine line) {
      final side = line.direction.vertical ? frame.width : frame.height;
      return line.direction.down * (line.thickness * side * scale);
    }

    final first = lines.first, last = lines.last;
    canvas
      ..drawLine(ends.$1, ends.$1 + bar(first), solid)
      ..drawCircle(ends.$1 - first.direction.down * 5, 6, solid)
      ..drawLine(ends.$2, ends.$2 - bar(last), solid)
      ..drawCircle(ends.$2 + last.direction.down * 5, 6, solid);
  }

  @override
  bool shouldRepaint(PdfSelectionPainter old) => true; // Repainted by the builder's listenables.
}
