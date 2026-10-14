import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The keyboard's way to what a long press or a right-click opens (a
/// context menu, a control's alternate): the Menu key or Shift+F10 while
/// focus is in [child], as on every desktop. Without [onMenu] it is just
/// [child].
///
/// Screen readers are not involved: the controls it wraps already offer
/// the same through a long press action or a ⋯ button beside them.
class ContextMenuKeys extends StatelessWidget {
  const ContextMenuKeys({super.key, required this.onMenu, required this.child});

  final VoidCallback? onMenu;
  final Widget child;

  /// The keys that open a context menu.
  static const activators = [
    SingleActivator(LogicalKeyboardKey.contextMenu),
    SingleActivator(LogicalKeyboardKey.f10, shift: true),
  ];

  /// Whether [event] asks for a context menu (for a focus node's own key
  /// handler, e.g. the canvas's).
  static bool accepts(KeyEvent event) =>
      event is! KeyUpEvent && activators.any((a) => a.accepts(event, HardwareKeyboard.instance));

  @override
  Widget build(BuildContext context) {
    final open = onMenu;
    if (open == null) return child;
    return CallbackShortcuts(bindings: {for (final a in activators) a: open}, child: child);
  }
}
