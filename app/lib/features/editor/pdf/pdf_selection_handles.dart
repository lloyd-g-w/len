import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'pdf_interaction.dart';

/// Touch targets over the two handles of a PDF text selection (painted by
/// `PdfSelectionPainter`): dragging one moves that end of the selection,
/// keeping the other. The menu hides while dragging and shows again after.
///
/// The targets take the press, so the canvas beneath doesn't ink.
///
/// The targets sit at [PdfInteraction.handleEnds] (there must be ends), laid
/// out again whenever [relayout] notifies (the view moved): no rebuild.
class PdfSelectionHandles extends StatefulWidget {
  const PdfSelectionHandles({super.key, required this.interaction, required this.relayout});

  final PdfInteraction interaction;

  /// Notifies when the ends move on screen.
  final Listenable relayout;

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

  Widget _target(bool startHandle) => LayoutId(
    id: startHandle,
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

  /// This layer's top-left in global coordinates (handles are in local ones).
  Offset _origin() {
    final box = context.findRenderObject() as RenderBox?;
    return box == null ? Offset.zero : box.localToGlobal(Offset.zero);
  }

  @override
  Widget build(BuildContext context) => CustomMultiChildLayout(
    delegate: _HandlesLayout(_pdf, relayout: widget.relayout),
    children: [_target(true), _target(false)],
  );
}

/// Centres the targets (keyed by whether they are the start's) on the
/// selection's ends.
class _HandlesLayout extends MultiChildLayoutDelegate {
  _HandlesLayout(this.pdf, {super.relayout});

  final PdfInteraction pdf;

  @override
  void performLayout(Size size) {
    const r = PdfSelectionHandles.reach;
    // Off screen in the moment between the ends going and the rebuild.
    const away = Offset(-4 * r, -4 * r);
    final ends = pdf.handleEnds;
    for (final (start, at) in [(true, ends?.$1 ?? away), (false, ends?.$2 ?? away)]) {
      layoutChild(start, BoxConstraints.tight(const Size.square(2 * r)));
      positionChild(start, at - const Offset(r, r));
    }
  }

  @override
  bool shouldRelayout(_HandlesLayout old) => true; // Rebuilt when the selection changes.
}
