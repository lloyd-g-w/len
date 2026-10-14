import 'package:flutter/material.dart';

import '../../../ui/app_theme.dart';
import '../../../ui/floating_panel.dart';
import 'editor_tips.dart';

/// The current tip as a small card (icon and text), fading in and out. It
/// sits over the page's bottom lines, so it never takes input (pen strokes
/// go through to the page) and fades while the pen is down.
class TipBanner extends StatelessWidget {
  const TipBanner({super.key, required this.controller});

  final TipsController controller;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return IgnorePointer(
      child: ValueListenableBuilder(
        valueListenable: controller.writing,
        builder: (context, writing, child) =>
            AnimatedOpacity(opacity: writing ? 0 : 1, duration: Motion.fast, child: child),
        child: ValueListenableBuilder(
          valueListenable: controller,
          builder: (context, message, _) => AnimatedSwitcher(
            duration: Motion.medium,
            switchInCurve: Motion.emphasized,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: SlideTransition(
                position: Tween(begin: const Offset(0, 0.2), end: Offset.zero).animate(animation),
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
                      child: FloatingPanel(
                        padding: const EdgeInsets.symmetric(horizontal: Gaps.md, vertical: Gaps.sm),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(message.icon, size: Glyphs.menu, color: scheme.onSurfaceVariant),
                            const SizedBox(width: Gaps.sm),
                            Flexible(child: Text(message.text, style: theme.textTheme.bodyMedium)),
                          ],
                        ),
                      ),
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
