import 'package:flutter/widgets.dart';

import '../../../ui/app_theme.dart';

/// Whether the chrome under it recedes: the other pane of a split view is
/// in use (`SplitController.isDimmed`). [Receding] reads it.
class RecedeScope extends InheritedWidget {
  const RecedeScope({super.key, required this.dimmed, required super.child});

  final bool dimmed;

  static bool of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<RecedeScope>()?.dimmed ?? false;

  @override
  bool updateShouldNotify(RecedeScope old) => old.dimmed != dimmed;
}

/// What sits on a bar or palette (icons, text, the tools), fading to
/// [opacity] while its [RecedeScope] is dimmed ([Motion.fast]). The bars'
/// surfaces stay as they are: a whole bar at partial opacity reads as grey
/// over a light page in dark mode.
class Receding extends StatelessWidget {
  const Receding({super.key, required this.child});

  final Widget child;

  /// The content's opacity while receded.
  static const double opacity = 0.6;

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
    opacity: RecedeScope.of(context) ? opacity : 1,
    duration: Motion.fast,
    curve: Motion.standard,
    child: child,
  );
}
