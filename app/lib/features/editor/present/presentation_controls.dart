import 'package:flutter/material.dart';

import '../../../ui/app_theme.dart';
import '../../../ui/floating_panel.dart';
import '../chrome/peeking.dart';
import '../document/document_controller.dart';
import 'presentation.dart';

/// The only chrome of presentation mode: a small bar at the bottom —
/// previous / next page and the page number (paged notebooks) and Stop —
/// that shows while [activity] notifies (the pointer near the bottom, a
/// touch, a page turn) and fades away after a moment.
class PresentationControls extends StatelessWidget {
  const PresentationControls({
    super.key,
    required this.presentation,
    required this.activity,
    this.doc,
  });

  final Presentation presentation;
  final Listenable activity;
  final DocumentController? doc;

  @override
  Widget build(BuildContext context) {
    final doc = this.doc;
    final theme = Theme.of(context);
    final safe = MediaQuery.paddingOf(context);
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.only(bottom: safe.bottom + Gaps.lg),
        child: Peeking(
          activity: Listenable.merge([activity, ?doc]),
          linger: const Duration(seconds: 3),
          child: FloatingPanel(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (doc != null)
                  ListenableBuilder(
                    listenable: doc,
                    builder: (context, _) => Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: 'Previous page (←)',
                          onPressed: doc.currentPage > 0 ? () => presentation.turn(-1) : null,
                          icon: const Icon(Icons.chevron_left_rounded),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: Gaps.xs),
                          child: Text(
                            '${doc.currentPage + 1} / ${doc.pages.length}',
                            style: theme.textTheme.labelLarge?.copyWith(
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Next page (→)',
                          onPressed: doc.currentPage < doc.pages.length - 1
                              ? () => presentation.turn(1)
                              : null,
                          icon: const Icon(Icons.chevron_right_rounded),
                        ),
                        Container(
                          width: 1,
                          height: 24,
                          margin: const EdgeInsets.symmetric(horizontal: Gaps.xs),
                          color: theme.colorScheme.outlineVariant,
                        ),
                      ],
                    ),
                  ),
                TextButton.icon(
                  onPressed: presentation.stop,
                  icon: const Icon(Icons.close_rounded),
                  label: const Text('Stop presenting'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
