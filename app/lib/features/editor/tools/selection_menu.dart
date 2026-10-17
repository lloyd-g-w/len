import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../domain/surface_element.dart';
import '../../../ink/selection/selection_chrome.dart';
import '../../../ink/selection/selection_controller.dart';
import '../../../ink/tool_settings.dart';
import '../../../ink/viewport.dart';
import 'selection_menu_bar.dart';

/// A command the editor adds to the selection menu (links):
/// [run] gets the control it was started from, to anchor a popover.
class SelectionExtraAction {
  const SelectionExtraAction(this.label, this.icon, this.run);

  final String label;
  final IconData icon;
  final void Function(BuildContext anchor) run;
}

/// The floating context menu of a lasso selection, placed above it (or
/// below when there is no room). Hidden while the selection is dragged
/// and while a dialog or sheet is open over it (e.g. Convert to text).
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
    // The view only matters while something is selected: no rebuild per
    // pan frame otherwise (it would lay out and repaint the editor), nor
    // per move of a gesture (the menu is hidden meanwhile).
    return ListenableBuilder(
      listenable: selection.settled,
      builder: (context, _) => selection.isEmpty ? const SizedBox.shrink() : _menu(context),
    );
  }

  Widget _menu(BuildContext context) {
    final dialogOpen = AppScope.of(context).routeOwners.dialogOpen;
    return ListenableBuilder(
      listenable: Listenable.merge([selection.settled, viewport, selection.clipboard, dialogOpen]),
      builder: (context, _) {
        final frame = selection.frame;
        if (frame == null || selection.isEmpty || selection.isChanging) {
          return const SizedBox.shrink();
        }
        final shape = selection.shape;
        final handles = [
          ...SelectionChrome.handles(frame, viewport, shape: shape).values,
          if (shape != null)
            for (final h in SelectionChrome.shapeHandles(shape, viewport)) h.at,
        ];
        final corners = frame.corners.map(viewport.toScreen);
        var box = Rect.fromPoints(corners.first, corners.first);
        for (final p in [...corners, ...handles]) {
          box = box.expandToInclude(Rect.fromCircle(center: p, radius: 10));
        }
        return CustomSingleChildLayout(
          delegate: _MenuLayout(box, MediaQuery.paddingOf(context)),
          // Kept in the tree (just not shown) so the command that opened
          // the dialog can still use its anchor.
          child: Visibility.maintain(
            visible: !dialogOpen.value,
            child: SelectionMenuBar(
              selection: selection,
              tools: tools,
              onEditText: onEditText,
              onPaste: onPaste,
              onCrop: onCrop,
              onConvertToText: onConvertToText,
              convertUnavailable: convertUnavailable,
              extras: extraActions?.call() ?? const [],
            ),
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

  /// [side] keeps the bar clear of the screen's left and right edges.
  static const double gap = 10, margin = 8, side = 12;

  double get topInset => chrome.top + margin;
  double get bottomInset => chrome.bottom + margin;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      constraints.loosen().deflate(const EdgeInsets.symmetric(horizontal: side, vertical: margin));

  @override
  Offset getPositionForChild(Size size, Size child) {
    final double x = (target.center.dx - child.width / 2).clamp(
      side,
      math.max(side, size.width - child.width - side),
    );
    var y = target.top - gap - child.height;
    if (y < topInset) y = target.bottom + gap;
    if (y + child.height > size.height - bottomInset) y = topInset;
    return Offset(x, y);
  }

  @override
  bool shouldRelayout(_MenuLayout old) => old.target != target || old.chrome != chrome;
}
