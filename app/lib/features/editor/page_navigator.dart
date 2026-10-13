import 'package:flutter/material.dart';

import '../../ui/app_theme.dart';
import '../../ui/floating_panel.dart';

/// A quiet page indicator that peeks while pages move. Tap to jump to a
/// page; long-press to open the overview. Page insertion lives in Insert ⊕.
class PageNavigator extends StatelessWidget {
  const PageNavigator({
    super.key,
    required this.index,
    required this.count,
    required this.onGoTo,
    required this.onOverview,
    this.bookmarked = false,
  });

  final int index;
  final int count;
  final VoidCallback onGoTo;
  final VoidCallback onOverview;
  final bool bookmarked;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme.labelLarge;
    final label = '${index + 1} / $count';
    return Tooltip(
      message: 'Go to page',
      child: FloatingPanel(
        radius: Radii.pill,
        padding: EdgeInsets.zero,
        child: Semantics(
          button: true,
          label: 'Page ${index + 1} of $count${bookmarked ? ', bookmarked' : ''}',
          hint: 'Tap to go to a page; long-press for all pages',
          child: InkWell(
            key: const ValueKey('page-indicator'),
            borderRadius: BorderRadius.circular(Radii.pill),
            onTap: onGoTo,
            onLongPress: onOverview,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minWidth: 64, minHeight: 48),
              child: Center(
                widthFactor: 1,
                heightFactor: 1,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Gaps.md),
                  child: Text(label, style: text?.copyWith(fontFeatures: AppTheme.tabularFigures)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
