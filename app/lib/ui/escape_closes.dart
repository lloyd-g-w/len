import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Escape closes the full-screen route around [child], as it closes
/// dialogs, sheets and popovers (UX_AUDIT R25-8). It asks the route
/// ([Navigator.maybePop]), so a `PopScope` still decides: the page
/// overview leaves selecting first. Nearer Escape handlers (menus, fields,
/// an inner `DismissIntent` action) win. [child] takes focus when nothing
/// in the route has it, so Escape reaches here without a click first.
///
/// With focus on a control in the page, Escape still closes it; in a text
/// field it first leaves the field (what was typed is not lost to one
/// stray key), then closes.
///
/// Only for screens Escape has no other use on: never the editor.
class EscapeCloses extends StatefulWidget {
  /// Wraps [child], the route's page.
  const EscapeCloses({super.key, required this.child});

  /// The page.
  final Widget child;

  @override
  State<EscapeCloses> createState() => _EscapeClosesState();
}

class _EscapeClosesState extends State<EscapeCloses> {
  final _node = FocusNode(debugLabel: 'EscapeCloses', skipTraversal: true);

  @override
  void dispose() {
    _node.dispose();
    super.dispose();
  }

  /// Escape bubbling up from a focused control, before the app's
  /// shortcut turns it into a `DismissIntent`. That shortcut takes only the
  /// nearest `DismissIntent` action, enabled or not, and a `Scaffold` has
  /// one (closing its drawer) that is off with no drawer open: from inside
  /// the page, Escape stopped there. A nearer action that is on (an open
  /// drawer, ours when nothing is between) keeps it; a text field is left
  /// first; else the route is asked to pop.
  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.escape) return KeyEventResult.ignored;
    if (event is! KeyDownEvent) return KeyEventResult.ignored;
    final focused = FocusManager.instance.primaryFocus;
    final context = focused?.context;
    if (focused == null || focused == _node || context == null) return KeyEventResult.ignored;
    if (context.findAncestorStateOfType<EditableTextState>() != null) {
      _node.requestFocus(); // Its toolbar, if shown, goes with the focus.
      return KeyEventResult.handled;
    }
    const intent = DismissIntent();
    final nearest = Actions.maybeFind<DismissIntent>(context, intent: intent);
    final on = switch (nearest) {
      null => false,
      final ContextAction<DismissIntent> action => action.isEnabled(intent, context),
      final action => action.isEnabled(intent),
    };
    if (on) return KeyEventResult.ignored;
    _pop();
    return KeyEventResult.handled;
  }

  void _pop() => unawaited(Navigator.of(context).maybePop());

  @override
  Widget build(BuildContext context) => Actions(
    actions: {
      DismissIntent: CallbackAction<DismissIntent>(
        onInvoke: (_) {
          _pop();
          return null;
        },
      ),
    },
    child: Focus(focusNode: _node, autofocus: true, onKeyEvent: _onKey, child: widget.child),
  );
}
