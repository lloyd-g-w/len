import 'dart:async';

import 'package:flutter/widgets.dart';

/// Escape closes the full-screen route around [child], as it closes
/// dialogs, sheets and popovers (UX_AUDIT R25-8). It asks the route
/// ([Navigator.maybePop]), so a `PopScope` still decides: the page
/// overview leaves selecting first. Nearer Escape handlers (menus, fields,
/// an inner `DismissIntent` action) win. [child] takes focus when nothing
/// in the route has it, so Escape reaches here without a click first.
///
/// Only for screens Escape has no other use on: never the editor.
class EscapeCloses extends StatelessWidget {
  /// Wraps [child], the route's page.
  const EscapeCloses({super.key, required this.child});

  /// The page.
  final Widget child;

  @override
  Widget build(BuildContext context) => Actions(
    actions: {
      DismissIntent: CallbackAction<DismissIntent>(
        onInvoke: (_) {
          unawaited(Navigator.of(context).maybePop());
          return null;
        },
      ),
    },
    child: Focus(autofocus: true, skipTraversal: true, child: child),
  );
}
