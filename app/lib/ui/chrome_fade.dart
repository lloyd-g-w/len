import 'package:flutter/widgets.dart';

import 'app_theme.dart';

/// Shows or hides chrome (REDESIGN §1.5): a fade ([Motion.medium]) plus a
/// [Motion.chromeSlide] slide toward its [edge] — never a whole bar's
/// height. With reduced motion it only fades. Hidden chrome ignores input.
class ChromeFade extends StatelessWidget {
  const ChromeFade({super.key, required this.visible, required this.edge, required this.child});

  final bool visible;

  /// The direction it leaves in, e.g. `Offset(0, -1)` for a top bar.
  final Offset edge;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final slide = Motion.reduced(context) ? 0.0 : Motion.chromeSlide;
    return IgnorePointer(
      ignoring: !visible,
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: visible ? 1 : 0),
        duration: Motion.medium,
        curve: Motion.standard,
        builder: (context, t, child) => Opacity(
          opacity: t,
          child: Transform.translate(offset: edge * slide * (1 - t), child: child),
        ),
        child: child,
      ),
    );
  }
}
