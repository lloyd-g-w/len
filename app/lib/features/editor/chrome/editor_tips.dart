import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/preferences.dart';
import '../../../ui/app_theme.dart';

/// One-time hints about input that has no visible affordance.
enum EditorTip {
  /// The stylus side button (after the first stylus contact).
  penButton,

  /// Two-finger tap undo / three-finger tap redo (after the first touch or
  /// stylus edit).
  gestures,
}

/// What a shown tip says.
@immutable
class TipMessage {
  const TipMessage(this.tip, this.icon, this.text);

  final EditorTip tip;
  final IconData icon;
  final String text;
}

/// Shows each [EditorTip] once per device, one at a time (later offers
/// wait in a queue), for [visibleFor] or until dismissed. Tips that don't
/// apply to the current settings (e.g. the side button does nothing) are
/// never shown.
class TipsController extends ValueNotifier<TipMessage?> {
  TipsController({required this.seen, required this.markSeen}) : super(null);

  /// Whether a tip was already shown on this device, and recording that.
  final bool Function(String id) seen;
  final void Function(String id) markSeen;

  static const Duration visibleFor = Duration(seconds: 10);

  final List<TipMessage> _queue = [];
  Timer? _timer;

  /// Offers [tip], phrased for the current settings ([penButton],
  /// [twoFingerUndo], [threeFingerRedo]).
  void offer(
    EditorTip tip, {
    PenButtonAction penButton = PenButtonAction.eraser,
    bool twoFingerUndo = true,
    bool threeFingerRedo = true,
  }) {
    if (seen(tip.name) || value?.tip == tip || _queue.any((m) => m.tip == tip)) return;
    final message = switch (tip) {
      EditorTip.penButton => switch (penButton) {
        PenButtonAction.eraser => TipMessage(
          tip,
          Icons.draw_outlined,
          'Hold the pen’s side button to erase',
        ),
        PenButtonAction.lasso => TipMessage(
          tip,
          Icons.highlight_alt_rounded,
          'Hold the pen’s side button to select with the lasso',
        ),
        PenButtonAction.none => null,
      },
      EditorTip.gestures => switch ((twoFingerUndo, threeFingerRedo)) {
        (true, true) => TipMessage(
          tip,
          Icons.touch_app_outlined,
          'Tap with two fingers to undo, three to redo',
        ),
        (true, false) => TipMessage(tip, Icons.touch_app_outlined, 'Tap with two fingers to undo'),
        (false, true) => TipMessage(
          tip,
          Icons.touch_app_outlined,
          'Tap with three fingers to redo',
        ),
        (false, false) => null,
      },
    };
    if (message == null) return;
    if (value == null) {
      _show(message);
    } else {
      _queue.add(message);
    }
  }

  void _show(TipMessage message) {
    markSeen(message.tip.name);
    value = message;
    _timer?.cancel();
    _timer = Timer(visibleFor, dismiss);
  }

  /// Hides the current tip (and shows the next one, if any).
  void dismiss() {
    _timer?.cancel();
    value = null;
    if (_queue.isNotEmpty) _show(_queue.removeAt(0));
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }
}

/// The current tip as a small card (icon, text, close), fading in and out.
class TipBanner extends StatelessWidget {
  const TipBanner({super.key, required this.controller});

  final TipsController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return ValueListenableBuilder(
      valueListenable: controller,
      builder: (context, message, _) => AnimatedSwitcher(
        duration: Motion.medium,
        switchInCurve: Motion.emphasized,
        transitionBuilder: (child, animation) => FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween(begin: const Offset(0, -0.2), end: Offset.zero).animate(animation),
            child: child,
          ),
        ),
        child: message == null
            ? const SizedBox.shrink()
            : Semantics(
                key: ValueKey(message.tip),
                liveRegion: true,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 420),
                  child: Material(
                    color: scheme.surfaceContainerHigh,
                    elevation: 2,
                    shadowColor: Colors.black26,
                    borderRadius: BorderRadius.circular(Radii.pill),
                    child: Padding(
                      padding: const EdgeInsets.only(left: Gaps.md, right: Gaps.xxs),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(message.icon, size: 18, color: scheme.primary),
                          const SizedBox(width: Gaps.sm),
                          Flexible(
                            child: Text(
                              message.text,
                              style: theme.textTheme.bodyMedium?.copyWith(
                                color: scheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                          IconButton(
                            tooltip: 'Dismiss tip',
                            iconSize: 18,
                            visualDensity: VisualDensity.compact,
                            onPressed: controller.dismiss,
                            icon: const Icon(Icons.close_rounded),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
