import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../ui/app_theme.dart';

/// One entry of the canvas context menu.
@immutable
class CanvasAction {
  const CanvasAction(this.icon, this.label, this.onSelected, {this.dividerBefore = false});

  final IconData icon;
  final String label;
  final VoidCallback onSelected;

  /// Starts a new group.
  final bool dividerBefore;
}

/// The menu a finger long press (or a right click) opens on the canvas,
/// placed next to the touch point and kept on screen. Tapping outside
/// dismisses it. It takes focus on its first entry (shown only to the
/// keyboard, which opens it with the Menu key): the arrows and Tab move
/// in it, Escape closes it.
class CanvasContextMenu extends StatelessWidget {
  const CanvasContextMenu({
    super.key,
    required this.at,
    required this.actions,
    required this.onDismiss,
  });

  /// The touch point, in the coordinates of the enclosing stack.
  final Offset at;
  final List<CanvasAction> actions;
  final VoidCallback onDismiss;

  static const double minWidth = 220;

  /// Escape closes; ↑ ↓ move between the entries (before the editor's
  /// own arrow keys, which turn pages).
  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final focused = FocusManager.instance.primaryFocus;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
        onDismiss();
      case LogicalKeyboardKey.arrowDown:
        focused?.nextFocus();
      case LogicalKeyboardKey.arrowUp:
        focused?.previousFocus();
      default:
        return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onDismiss,
            onSecondaryTap: onDismiss,
            onPanStart: (_) => onDismiss(),
          ),
        ),
        CustomSingleChildLayout(
          delegate: _MenuPosition(at, MediaQuery.paddingOf(context)),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: Motion.fast,
            curve: Motion.standard,
            builder: (context, t, child) => Opacity(
              opacity: t,
              child: Transform.scale(
                scale: Motion.popoverScale + (1 - Motion.popoverScale) * t,
                child: child,
              ),
            ),
            child: FocusScope(
              autofocus: true,
              onKeyEvent: _onKey,
              child: OverlaySurface(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minWidth: minWidth),
                  child: IntrinsicWidth(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: Gaps.xs + 2),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          for (final (i, action) in actions.indexed) ...[
                            if (action.dividerBefore) const Divider(height: Gaps.sm + 1),
                            MenuItemButton(
                              autofocus: i == 0,
                              leadingIcon: Icon(action.icon),
                              onPressed: () {
                                onDismiss();
                                action.onSelected();
                              },
                              child: Text(action.label),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Puts the menu below-right of the finger (clear of it), flipping to stay
/// inside the safe area.
class _MenuPosition extends SingleChildLayoutDelegate {
  _MenuPosition(this.at, this.padding);

  final Offset at;
  final EdgeInsets padding;

  static const double gap = 12, margin = 8;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(constraints.biggest).deflate(const EdgeInsets.all(margin));

  @override
  Offset getPositionForChild(Size size, Size child) {
    var x = at.dx + gap;
    var y = at.dy + gap;
    if (x + child.width > size.width - margin - padding.right) x = at.dx - gap - child.width;
    if (y + child.height > size.height - margin - padding.bottom) y = at.dy - gap - child.height;
    final minX = margin + padding.left, maxX = size.width - margin - child.width - padding.right;
    final minY = margin + padding.top, maxY = size.height - margin - child.height - padding.bottom;
    return Offset(
      x.clamp(minX, maxX < minX ? minX : maxX),
      y.clamp(minY, maxY < minY ? minY : maxY),
    );
  }

  @override
  bool shouldRelayout(_MenuPosition old) => old.at != at || old.padding != padding;
}
