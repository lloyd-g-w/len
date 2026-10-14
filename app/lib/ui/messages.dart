import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_theme.dart';
import 'chrome_fade.dart';

/// Widest a snack bar gets: on tablets and desktops it is centred rather
/// than spanning the window.
const double messageMaxWidth = 560;

/// Room taken along the bottom edge by floating chrome (the editor's
/// toolbar and page navigator): messages shown from below stay above it.
/// The owner updates [bottom] as its chrome moves.
class MessageInsets extends InheritedWidget {
  const MessageInsets({super.key, required this.bottom, required super.child});

  final ValueListenable<double> bottom;

  /// The current inset below [context] (0 outside any [MessageInsets]).
  static double of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<MessageInsets>()?.bottom.value ?? 0;

  @override
  bool updateShouldNotify(MessageInsets old) => old.bottom != bottom;
}

/// Marks the part of the window that messages belong to (the library's
/// content beside its sidebar): snack bars shown from its route centre on
/// it rather than on the window.
class MessagePane extends StatefulWidget {
  const MessagePane({super.key, required this.child});

  final Widget child;

  static final _panes = <_MessagePaneState>{};

  /// The global rect of the pane on [context]'s route; null if none.
  static Rect? rectOf(BuildContext context) {
    if (_panes.isEmpty) return null;
    final route = ModalRoute.of(context);
    for (final pane in _panes) {
      if (!pane.mounted || ModalRoute.of(pane.context) != route) continue;
      final box = pane.context.findRenderObject();
      if (box is RenderBox && box.hasSize) return box.localToGlobal(Offset.zero) & box.size;
    }
    return null;
  }

  @override
  State<MessagePane> createState() => _MessagePaneState();
}

class _MessagePaneState extends State<MessagePane> {
  @override
  void initState() {
    super.initState();
    MessagePane._panes.add(this);
  }

  @override
  void dispose() {
    MessagePane._panes.remove(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// The app's snack bar: floating, at most [messageMaxWidth] wide, clear of
/// [MessageInsets] and centred on the [MessagePane] if any. Copy is a short sentence; a single fragment ("Page 3
/// deleted") has no full stop.
SnackBar appSnackBar(
  BuildContext context,
  String message, {
  SnackBarAction? action,
  Duration? duration,
}) {
  final width = MediaQuery.sizeOf(context).width;
  final pane = MessagePane.rectOf(context);
  final left = pane == null ? 0.0 : pane.left.clamp(0.0, width);
  final right = pane == null ? width : pane.right.clamp(left, width);
  final side = ((right - left - messageMaxWidth) / 2).clamp(Gaps.lg, double.infinity);
  return SnackBar(
    content: Text(message),
    action: action,
    behavior: SnackBarBehavior.floating,
    duration: duration ?? const Duration(milliseconds: 4000),
    // Flutter keeps snack bars with an action until dismissed; ours are
    // short notes (an Undo is a convenience, Ctrl+Z still works): they go.
    persist: false,
    margin: EdgeInsets.fromLTRB(
      left + side,
      0,
      width - right + side,
      Gaps.lg + MessageInsets.of(context),
    ),
  );
}

/// Shows a short message at the bottom of the screen (replacing any shown).
void showMessage(
  BuildContext context,
  String message, {
  SnackBarAction? action,
  Duration? duration,
}) {
  final messenger = ScaffoldMessenger.maybeOf(context)?..removeCurrentSnackBar();
  if (messenger == null) return;
  MessageQueue.show(messenger, appSnackBar(context, message, action: action, duration: duration));
}

/// The snack bars up (shown or waiting) on each messenger, so standing
/// notices step aside while one shows ([MessageQueue.stepAside]): one
/// message at a time. Show snack bars through [show] (or [showMessage]).
abstract final class MessageQueue {
  static final _counts = Expando<int>();
  static final _changes = ValueNotifier(0);
  static final _anyUp = ValueNotifier(false);
  static int _up = 0;

  /// Whether a snack bar is up anywhere (the editor's tips keep away).
  static ValueListenable<bool> get anyShowing => _anyUp;

  /// Shows [bar] on [messenger], counting it until it closes.
  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason> show(
    ScaffoldMessengerState messenger,
    SnackBar bar,
  ) {
    final shown = messenger.showSnackBar(bar);
    _counts[messenger] = (_counts[messenger] ?? 0) + 1;
    _anyUp.value = ++_up > 0;
    _changes.value++;
    unawaited(
      shown.closed.whenComplete(() {
        _counts[messenger] = (_counts[messenger] ?? 1) - 1;
        _anyUp.value = --_up > 0;
        _changes.value++;
      }),
    );
    return shown;
  }

  /// Whether a snack bar is up on [context]'s messenger.
  static bool showingIn(BuildContext context) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    return messenger != null && (_counts[messenger] ?? 0) > 0;
  }

  /// [child] (a standing notice) fades away while a snack bar is up on its
  /// messenger and comes back once it has gone.
  static Widget stepAside({required Widget child}) => ListenableBuilder(
    listenable: _changes,
    builder: (context, child) =>
        ChromeFade(visible: !showingIn(context), edge: const Offset(0, -1), child: child!),
    child: child,
  );
}
