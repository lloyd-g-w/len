import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'pdf_interaction.dart';

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

  /// The character the dragged handle's other end stays at.
  PdfTextPoint? _anchor;

  void _start(bool startHandle) {
    final selection = _pdf.selection;
    final spans = selection.spans.where((s) => !s.isEmpty).toList();
    if (spans.isEmpty) return;
    // Dragging the start keeps the end (the last page's last character),
    // and the other way round.
    final span = startHandle ? spans.last : spans.first;
    final index = _pdf.doc.pages.indexWhere((p) => p.id == span.page.id);
    if (index < 0) return;
    _anchor = (
      index: index,
      page: span.page,
      glyphs: span.glyphs,
      glyph: startHandle ? span.end - 1 : span.start,
    );
    selection.showsMenu = false;
  }

  void _move(Offset screen) {
    final anchor = _anchor;
    if (anchor == null) return;
    // On any PDF page: the selection may run across pages.
    final focus = _pdf.textPointAt(screen);
    if (focus == null) return;
    _pdf.selectRange(anchor, focus);
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
