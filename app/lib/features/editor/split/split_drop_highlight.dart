import 'package:flutter/material.dart';

import '../../../ui/app_theme.dart';
import 'split_controller.dart';

/// Marks [pane] while a selection dragged from the other pane would be
/// dropped (copied) into it.
class SplitDropHighlight extends StatelessWidget {
  const SplitDropHighlight({super.key, required this.split, required this.pane});

  final SplitController split;
  final SplitPane pane;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return IgnorePointer(
      child: ListenableBuilder(
        listenable: split,
        builder: (context, _) {
          final on = split.dropTarget == pane;
          return AnimatedSwitcher(
            duration: Motion.fast,
            child: !on
                ? const SizedBox.expand()
                : DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.primary.withValues(alpha: 0.06),
                      border: Border.all(color: scheme.primary, width: 3),
                    ),
                    child: Align(
                      alignment: const Alignment(0, -0.6),
                      child: Material(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(Radii.pill),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: Gaps.lg,
                            vertical: Gaps.sm,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.content_copy_rounded, size: 18, color: scheme.onPrimary),
                              const SizedBox(width: Gaps.sm),
                              Text(
                                'Drop to copy here',
                                style: TextStyle(
                                  color: scheme.onPrimary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
          );
        },
      ),
    );
  }
}
