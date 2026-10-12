import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'pdf_interaction.dart';
import 'pdf_text_selection.dart';

/// Touch targets over the two handles of a PDF text selection (painted by
/// `PdfSelectionPainter`): dragging one moves that end of the selection,
/// keeping the other. The menu hides while dragging and shows again after.
///
/// The targets take the press, so the canvas beneath doesn't ink.
class PdfSelectionHandles extends StatefulWidget {
  const PdfSelectionHandles({super.key, required this.interaction, required this.ends});

  final PdfInteraction interaction;

  /// Where the start and end handles are (from [PdfInteraction.handleEnds]).
  final (Offset, Offset) ends;

  /// Screen distance within which a press grabs a handle.
  static const double reach = 24;

  @override
  State<PdfSelectionHandles> createState() => _PdfSelectionHandlesState();
}

class _PdfSelectionHandlesState extends State<PdfSelectionHandles> {
  PdfInteraction get _pdf => widget.interaction;

  /// The glyph the dragged handle's other end stays at.
  int? _anchor;

  void _start(bool startHandle) {
    final selection = _pdf.selection;
    _anchor = startHandle ? selection.end - 1 : selection.start;
    selection.showsMenu = false;
  }

  void _move(Offset screen) {
    final selection = _pdf.selection;
    final anchor = _anchor;
    final page = selection.page;
    if (anchor == null || page == null) return;
    final index = _pdf.doc.pages.indexWhere((p) => p.id == page.id);
    final frame = index < 0 ? null : _pdf.doc.layout.frameOf(index);
    final bg = page.background;
    final glyphs = bg == null ? null : _pdf.info.glyphs(bg.blob, bg.pageIndex);
    if (frame == null || glyphs == null) return;
    final world = _pdf.doc.viewport.toWorld(screen) - frame.topLeft;
    final focus = glyphs.nearestIndex(Offset(world.dx / frame.width, world.dy / frame.height));
    if (focus == null) return;
    final (a, b) = focus >= anchor ? (anchor, focus + 1) : (focus, anchor + 1);
    selection.select(page, glyphs, a, b);
  }

  void _end() {
    _anchor = null;
    if (!_pdf.selection.isEmpty) _pdf.selection.showsMenu = true;
  }

  Widget _target(Offset at, bool startHandle) {
    const r = PdfSelectionHandles.reach;
    return Positioned(
      left: at.dx - r,
      top: at.dy - r,
      width: 2 * r,
      height: 2 * r,
      child: GestureDetector(
        key: ValueKey(startHandle ? 'pdf-handle-start' : 'pdf-handle-end'),
        behavior: HitTestBehavior.opaque,
        dragStartBehavior: DragStartBehavior.down,
        onPanStart: (_) => _start(startHandle),
        onPanUpdate: (d) => _move(d.globalPosition - _origin()),
        onPanEnd: (_) => _end(),
        onPanCancel: _end,
      ),
    );
  }

  /// This layer's top-left in global coordinates (handles are in local ones).
  Offset _origin() {
    final box = context.findRenderObject() as RenderBox?;
    return box == null ? Offset.zero : box.localToGlobal(Offset.zero);
  }

  @override
  Widget build(BuildContext context) =>
      Stack(children: [_target(widget.ends.$1, true), _target(widget.ends.$2, false)]);
}
