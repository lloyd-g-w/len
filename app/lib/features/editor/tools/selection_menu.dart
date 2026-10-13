import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../domain/surface_element.dart';
import '../../../ink/selection/selection_chrome.dart';
import '../../../ink/selection/selection_controller.dart';
import '../../../ink/tool_settings.dart';
import '../../../ink/viewport.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/floating_panel.dart';
import '../../../ui/menus.dart';
import '../../../ui/messages.dart';
import 'selection_style_panel.dart';

/// A command the editor adds to the selection menu (links):
/// [run] gets the control it was started from, to anchor a popover.
class SelectionExtraAction {
  const SelectionExtraAction(this.label, this.icon, this.run);

  final String label;
  final IconData icon;
  final void Function(BuildContext anchor) run;
}

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
    this.extraActions,
  });

  final SelectionController selection;
  final ViewportController viewport;

  /// More commands for the current selection, placed after Duplicate.
  final List<SelectionExtraAction> Function()? extraActions;
  final ToolSettings tools;
  final ValueChanged<SurfaceElement> onEditText;
  final VoidCallback onPaste;

  /// Asked to crop an image (shown for a single selected image).
  final ValueChanged<SurfaceElement>? onCrop;

  /// "Convert to text" (offered when ink is selected). Where recognition
  /// is unavailable ([convertUnavailable] set), choosing it says why.
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
            extras: extraActions?.call() ?? const [],
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
    this.extras = const [],
  });

  final SelectionController selection;
  final ToolSettings tools;
  final List<SelectionExtraAction> extras;
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
    // Only ink and text have a colour and a style.
    final styleable =
        selection.strokes.isNotEmpty || elements.any((e) => e.knownType == ElementType.text);
    final convertible =
        onConvertToText != null && selection.strokes.any((s) => !s.tool.isHighlighter);
    // The pill (REDESIGN §2.6): Style · Cut · Copy · Delete · ⋯, with
    // Edit text first for a single text box. The rest is in ⋯; what the
    // pill has no room for moves there too.
    final primary = <_Action>[
      if (singleText) _Action('Edit text', Symbols.edit_rounded, () => onEditText(elements.single)),
      if (styleable)
        _Action.anchored(
          'Style',
          Symbols.palette_rounded,
          (anchor) => showSelectionStyle(anchor, selection: selection, tools: tools),
        ),
      _Action('Cut', Symbols.content_cut_rounded, selection.cut, shortcut: 'Ctrl+X'),
      _Action('Copy', Symbols.content_copy_rounded, selection.copy, shortcut: 'Ctrl+C'),
    ];
    final secondary = <_Action>[
      _Action('Duplicate', Symbols.library_add_rounded, selection.duplicate, shortcut: 'Ctrl+D'),
      if (!selection.clipboard.isEmpty)
        _Action('Paste', Symbols.content_paste_rounded, onPaste, shortcut: 'Ctrl+V'),
      if (convertible)
        if (convertUnavailable case final reason?)
          // Chosen where it can't work, it says why (a disabled row in a
          // menu couldn't).
          _Action.anchored(
            'Convert to text',
            Symbols.spellcheck_rounded,
            (anchor) => showMessage(anchor, reason),
          )
        else
          _Action('Convert to text', Symbols.spellcheck_rounded, onConvertToText),
      for (final x in extras) _Action.anchored(x.label, x.icon, x.run),
      if (singleImage && onCrop != null)
        _Action('Crop', Symbols.crop_rounded, () => onCrop!(elements.single)),
      if (elements.isNotEmpty) ...[
        _Action('Bring to front', Symbols.flip_to_front_rounded, selection.bringToFront),
        _Action('Send to back', Symbols.flip_to_back_rounded, selection.sendToBack),
      ],
    ];
    final delete = _Action('Delete', Symbols.delete_rounded, selection.delete, shortcut: 'Del');
    return LayoutBuilder(
      builder: (context, constraints) {
        // Buttons are 48 dp; the panel adds 6 dp on each side.
        final fits = ((constraints.maxWidth - 12) / 48).floor();
        // Delete and ⋯ always show; the primary actions as room allows.
        final keep = (fits - 2).clamp(0, primary.length);
        final shown = primary.sublist(0, keep);
        final more = [...primary.sublist(keep), ...secondary];
        return FloatingPanel(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final a in shown) a.button(),
              delete.button(),
              if (more.isNotEmpty)
                Builder(
                  builder: (anchor) => MenuIconButton<_Action>(
                    tooltip: 'More',
                    icon: const Icon(Symbols.more_horiz_rounded, size: Glyphs.bar),
                    onSelected: (a) => a.run(anchor),
                    items: () => [
                      for (final a in more)
                        MenuRow<_Action>(
                          value: a,
                          icon: a.icon,
                          label: a.label,
                          enabled: a.enabled,
                          shortcut: a.shortcut,
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
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
  const _Action(this.label, this.icon, VoidCallback? onPressed, {this.shortcut})
    : _onPressed = onPressed,
      onPressedAt = null;

  /// An action whose popover anchors to the control it was started from.
  const _Action.anchored(this.label, this.icon, this.onPressedAt)
    : _onPressed = null,
      shortcut = null;

  final String label;
  final IconData icon;
  final VoidCallback? _onPressed;
  final void Function(BuildContext anchor)? onPressedAt;

  /// Runs the action from the control at [anchor].
  void run(BuildContext anchor) => onPressedAt != null ? onPressedAt!(anchor) : _onPressed?.call();

  /// Keyboard shortcut shown in the tooltip, e.g. "Ctrl+C".
  final String? shortcut;

  bool get enabled => _onPressed != null || onPressedAt != null;

  Widget button() {
    final hint = shortcut == null ? label : '$label ($shortcut)';
    return Tooltip(
      message: hint,
      child: Builder(
        builder: (anchor) => IconButton(
          onPressed: enabled ? () => run(anchor) : null,
          icon: Icon(icon, size: Glyphs.bar),
        ),
      ),
    );
  }
}
