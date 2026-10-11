import 'dart:async';

import 'package:flutter/material.dart';

import '../../../ui/app_theme.dart';

/// A short-lived message for gestures without other visible feedback
/// ("Undo", "Redo", "Nothing to undo").
@immutable
class HudMessage {
  const HudMessage(this.icon, this.label, {this.count = 1});

  final IconData icon;
  final String label;

  /// How many times in a row it was shown ("Undo ×3"), so each repeated
  /// tap gets visible feedback.
  final int count;
}

/// Shows one [HudMessage] at a time for [visibleFor].
class HudController extends ValueNotifier<HudMessage?> {
  HudController() : super(null);

  static const Duration visibleFor = Duration(milliseconds: 900);
  Timer? _timer;

  /// Shows [label]; repeated while visible, it counts up (unless not
  /// [counts], e.g. "Nothing to undo").
  void show(IconData icon, String label, {bool counts = true}) {
    final current = value;
    value = HudMessage(
      icon,
      label,
      count: counts && current != null && current.label == label ? current.count + 1 : 1,
    );
    _timer?.cancel();
    _timer = Timer(visibleFor, () => value = null);
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// The HUD pill (centred near the top of the canvas), fading in and out.
class GestureHud extends StatelessWidget {
  const GestureHud({super.key, required this.controller});

  final HudController controller;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme.labelLarge;
    return IgnorePointer(
      child: ValueListenableBuilder(
        valueListenable: controller,
        builder: (context, message, _) => AnimatedSwitcher(
          duration: Motion.medium,
          switchInCurve: Motion.emphasized,
          switchOutCurve: Motion.exit,
          transitionBuilder: (child, animation) => FadeTransition(
            opacity: animation,
            child: ScaleTransition(
              scale: Tween(begin: 0.92, end: 1.0).animate(animation),
              child: child,
            ),
          ),
          child: message == null
              ? const SizedBox.shrink()
              : Container(
                  key: ValueKey(message.label),
                  padding: const EdgeInsets.symmetric(horizontal: Gaps.lg, vertical: Gaps.sm + 2),
                  decoration: BoxDecoration(
                    color: scheme.inverseSurface.withValues(alpha: 0.88),
                    borderRadius: BorderRadius.circular(Radii.pill),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(message.icon, size: 18, color: scheme.onInverseSurface),
                      const SizedBox(width: Gaps.sm),
                      Text(message.label, style: text?.copyWith(color: scheme.onInverseSurface)),
                      if (message.count > 1)
                        Padding(
                          padding: const EdgeInsets.only(left: Gaps.xs),
                          child: _Count(message.count, style: text, color: scheme.onInverseSurface),
                        ),
                    ],
                  ),
                ),
        ),
      ),
    );
  }
}

/// "×3", popping in as it counts up.
class _Count extends StatelessWidget {
  const _Count(this.count, {required this.style, required this.color});

  final int count;
  final TextStyle? style;
  final Color color;

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    key: ValueKey(count),
    tween: Tween(begin: 1.25, end: 1),
    duration: Motion.medium,
    curve: Motion.emphasized,
    builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
    child: Text(
      '×$count',
      style: style?.copyWith(
        color: color.withValues(alpha: 0.75),
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    ),
  );
}
