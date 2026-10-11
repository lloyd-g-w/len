import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'app_theme.dart';

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

/// The app's snack bar: floating, at most [messageMaxWidth] wide, clear of
/// [MessageInsets]. Copy is a short sentence; a single fragment ("Page 3
/// deleted") has no full stop.
SnackBar appSnackBar(
  BuildContext context,
  String message, {
  SnackBarAction? action,
  Duration? duration,
}) {
  final width = MediaQuery.sizeOf(context).width;
  final side = ((width - messageMaxWidth) / 2).clamp(Gaps.lg, double.infinity);
  return SnackBar(
    content: Text(message),
    action: action,
    behavior: SnackBarBehavior.floating,
    duration: duration ?? const Duration(milliseconds: 4000),
    margin: EdgeInsets.fromLTRB(side, 0, side, Gaps.lg + MessageInsets.of(context)),
  );
}

/// Shows a short message at the bottom of the screen (replacing any shown).
void showMessage(
  BuildContext context,
  String message, {
  SnackBarAction? action,
  Duration? duration,
}) {
  ScaffoldMessenger.maybeOf(context)
    ?..removeCurrentSnackBar()
    ..showSnackBar(appSnackBar(context, message, action: action, duration: duration));
}
