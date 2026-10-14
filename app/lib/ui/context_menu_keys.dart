import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// The keyboard's way to a menu that a long press or a right-click opens:
/// the Menu key or Shift+F10 while [child] has focus (as on every desktop),
/// and a screen-reader action named [label]. Without [onMenu] it is just
/// [child].
class ContextMenuKeys extends StatelessWidget {
  const ContextMenuKeys({
    super.key,
    required this.onMenu,
    this.label = 'Options',
    required this.child,
  });

  final VoidCallback? onMenu;

  /// The screen-reader action's name.
  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final open = onMenu;
    if (open == null) return child;
    return Semantics(
      customSemanticsActions: {CustomSemanticsAction(label: label): open},
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.contextMenu): open,
          const SingleActivator(LogicalKeyboardKey.f10, shift: true): open,
        },
        child: child,
      ),
    );
  }
}
