import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../domain/surface_element.dart';
import '../../../ink/selection/selection_chrome.dart';
import '../../../ink/selection/selection_controller.dart';
import '../../../ink/tool_settings.dart';
import '../../../ink/viewport.dart';
import '../../../ui/floating_panel.dart';
import '../../../ui/menus.dart';
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
    this.onCrop,
    this.onConvertToText,
    this.convertUnavailable,
  });

  final SelectionController selection;
  final ViewportController viewport;
  final ToolSettings tools;
  final ValueChanged<SurfaceElement> onEditText;
  final VoidCallback onPaste;

  /// Asked to crop an image (shown for a single selected image).
  final ValueChanged<SurfaceElement>? onCrop;

  /// "Convert to text" (shown when ink is selected); disabled, with
  /// [convertUnavailable] as its tooltip, if that is set.
  final VoidCallback? onConvertToText;
  final String? convertUnavailable;

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
          delegate: _MenuLayout(box, MediaQuery.paddingOf(context)),
          child: _MenuBar(
            selection: selection,
            tools: tools,
            onEditText: onEditText,
            onPaste: onPaste,
            onCrop: onCrop,
            onConvertToText: onConvertToText,
            convertUnavailable: convertUnavailable,
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
    this.onCrop,
    this.onConvertToText,
    this.convertUnavailable,
  });

  final SelectionController selection;
  final ToolSettings tools;
  final ValueChanged<SurfaceElement> onEditText;
  final VoidCallback onPaste;
  final ValueChanged<SurfaceElement>? onCrop;
  final VoidCallback? onConvertToText;
  final String? convertUnavailable;

  @override
  Widget build(BuildContext context) {
    final elements = selection.elements;
    final single = selection.strokes.isEmpty && elements.length == 1 ? elements.single : null;
    final singleText = single?.knownType == ElementType.text;
    final singleImage = single?.knownType == ElementType.image;
    // Only ink and text have a colour.
    final colourable =
        selection.strokes.isNotEmpty || elements.any((e) => e.knownType == ElementType.text);
    final convertible =
        onConvertToText != null && selection.strokes.any((s) => !s.tool.isHighlighter);
    Future<void> recolour() async {
      final colour = await pickColour(
        context,
        title: 'Recolour selection',
        initial: _currentColour(),
        tools: tools,
      );
      if (colour != null) selection.recolor(colour);
    }

    // In order of importance: what doesn't fit goes into "More", except
    // Delete, which always stays last in the bar.
    final actions = <_Action>[
      if (singleText) _Action('Edit text', Icons.edit_outlined, () => onEditText(elements.single)),
      if (singleImage && onCrop != null)
        _Action('Crop', Icons.crop_rounded, () => onCrop!(elements.single)),
      if (convertible)
        _Action(
          'Convert to text',
          Icons.spellcheck_rounded,
          convertUnavailable == null ? onConvertToText : null,
          tooltip: convertUnavailable,
        ),
      _Action('Cut', Icons.content_cut_rounded, selection.cut, shortcut: 'Ctrl+X'),
      _Action('Copy', Icons.content_copy_rounded, selection.copy, shortcut: 'Ctrl+C'),
      _Action('Duplicate', Icons.library_add_outlined, selection.duplicate, shortcut: 'Ctrl+D'),
      if (!selection.clipboard.isEmpty)
        _Action('Paste', Icons.content_paste_rounded, onPaste, shortcut: 'Ctrl+V'),
      if (colourable) _Action('Colour', Icons.palette_outlined, recolour),
      if (elements.isNotEmpty) ...[
        _Action('Bring to front', Icons.flip_to_front_rounded, selection.bringToFront),
        _Action('Send to back', Icons.flip_to_back_rounded, selection.sendToBack),
      ],
    ];
    final delete = _Action(
      'Delete',
      Icons.delete_outline_rounded,
      selection.delete,
      shortcut: 'Del',
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // Buttons are 48 dp; the panel adds 6 dp on each side.
        final fits = ((constraints.maxWidth - 12) / 48).floor();
        var shown = actions;
        var more = const <_Action>[];
        if (actions.length + 1 > fits) {
          final keep = (fits - 2).clamp(0, actions.length);
          shown = actions.sublist(0, keep);
          more = actions.sublist(keep);
        }
        return FloatingPanel(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final a in shown) a.button(),
              if (more.isNotEmpty)
                PopupMenuButton<_Action>(
                  tooltip: 'More',
                  icon: const Icon(Icons.more_horiz_rounded, size: 20),
                  onSelected: (a) => a.onPressed?.call(),
                  itemBuilder: (_) => [
                    for (final a in more)
                      MenuRow<_Action>(value: a, icon: a.icon, label: a.label, enabled: a.enabled),
                  ],
                ),
              delete.button(),
            ],
          ),
        );
      },
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
/// chrome ([chrome], the screen edges the editor's bars cover).
class _MenuLayout extends SingleChildLayoutDelegate {
  _MenuLayout(this.target, this.chrome);

  final Rect target;
  final EdgeInsets chrome;
  static const double gap = 10, margin = 8;

  double get topInset => chrome.top + margin;
  double get bottomInset => chrome.bottom + margin;

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
    if (y + child.height > size.height - bottomInset) y = topInset;
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_MenuLayout old) => old.target != target || old.chrome != chrome;
}

/// One command of the selection menu.
class _Action {
  const _Action(this.label, this.icon, this.onPressed, {this.shortcut, this.tooltip});

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  /// Keyboard shortcut shown in the tooltip, e.g. "Ctrl+C".
  final String? shortcut;

  /// Overrides the tooltip (e.g. why the action is unavailable).
  final String? tooltip;

  bool get enabled => onPressed != null;

  Widget button() {
    final hint = tooltip ?? (shortcut == null ? label : '$label ($shortcut)');
    return Tooltip(
      message: hint,
      child: IconButton(onPressed: onPressed, icon: Icon(icon, size: 20)),
    );
  }
}
