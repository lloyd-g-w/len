import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/surface_element.dart';
import '../../../ink/selection/selection_chrome.dart';
import '../../../ink/selection/selection_controller.dart';
import '../../../ink/tool_settings.dart';
import '../../../ink/viewport.dart';
import '../../../ui/floating_panel.dart';
import 'colour_sheet.dart';

/// The floating context menu of a lasso selection, placed above it (or
/// below when there is no room). Hidden while the selection is dragged.
class SelectionMenu extends StatelessWidget {
  const SelectionMenu({
    super.key,
    required this.selection,
    required this.viewport,
    required this.tools,
    required this.onEditText,
    required this.onPaste,
  });

  final SelectionController selection;
  final ViewportController viewport;
  final ToolSettings tools;
  final ValueChanged<SurfaceElement> onEditText;
  final VoidCallback onPaste;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([selection, viewport, selection.clipboard]),
      builder: (context, _) {
        final frame = selection.frame;
        if (frame == null || selection.isEmpty || !selection.preview.isIdentity) {
          return const SizedBox.shrink();
        }
        final handles = SelectionChrome.handles(frame, viewport).values;
        final corners = frame.corners.map(viewport.toScreen);
        var box = Rect.fromPoints(corners.first, corners.first);
        for (final p in [...corners, ...handles]) {
          box = box.expandToInclude(Rect.fromCircle(center: p, radius: 10));
        }
        return CustomSingleChildLayout(
          delegate: _MenuLayout(box),
          child: _MenuBar(
            selection: selection,
            tools: tools,
            onEditText: onEditText,
            onPaste: onPaste,
          ),
        );
      },
    );
  }
}

class _MenuBar extends StatelessWidget {
  const _MenuBar({
    required this.selection,
    required this.tools,
    required this.onEditText,
    required this.onPaste,
  });

  final SelectionController selection;
  final ToolSettings tools;
  final ValueChanged<SurfaceElement> onEditText;
  final VoidCallback onPaste;

  @override
  Widget build(BuildContext context) {
    final elements = selection.elements;
    final singleText =
        selection.strokes.isEmpty &&
        elements.length == 1 &&
        elements.single.knownType == ElementType.text;
    Widget action(String label, IconData icon, VoidCallback onPressed) =>
        IconButton(tooltip: label, onPressed: onPressed, icon: Icon(icon, size: 20));
    return FloatingPanel(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (singleText)
            action('Edit text', Icons.edit_outlined, () => onEditText(elements.single)),
          action('Cut (Ctrl+X)', Icons.content_cut_rounded, selection.cut),
          action('Copy (Ctrl+C)', Icons.content_copy_rounded, selection.copy),
          action('Duplicate (Ctrl+D)', Icons.library_add_outlined, selection.duplicate),
          if (!selection.clipboard.isEmpty)
            action('Paste (Ctrl+V)', Icons.content_paste_rounded, onPaste),
          Builder(
            builder: (context) => action('Colour', Icons.palette_outlined, () async {
              final colour = await pickColour(
                context,
                title: 'Recolour selection',
                initial: _currentColour(),
                tools: tools,
              );
              if (colour != null) selection.recolor(colour);
            }),
          ),
          action('Delete (Del)', Icons.delete_outline_rounded, selection.delete),
        ],
      ),
    );
  }

  int _currentColour() {
    if (selection.strokes.isNotEmpty) return selection.strokes.first.color;
    final data = selection.elements.firstOrNull?.data['color'];
    return data is int ? data : 0xFF000000;
  }
}

/// Centres the menu above [target] (screen rect), else below it, else at
/// the top; always kept inside the layer and clear of the editor's top
/// bar ([topInset]).
class _MenuLayout extends SingleChildLayoutDelegate {
  _MenuLayout(this.target);

  final Rect target;
  static const double gap = 10, margin = 8, topInset = 84;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen().deflate(const EdgeInsets.all(margin));

  @override
  Offset getPositionForChild(Size size, Size child) {
    final double x = (target.center.dx - child.width / 2).clamp(
      margin,
      math.max(margin, size.width - child.width - margin),
    );
    var y = target.top - gap - child.height;
    if (y < topInset) y = target.bottom + gap;
    if (y + child.height > size.height - margin) y = topInset;
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_MenuLayout old) => old.target != target;
}
