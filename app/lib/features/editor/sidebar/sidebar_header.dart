import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/app_theme.dart';
import '../chrome/bar_button.dart';
import 'sidebar_metrics.dart';

/// The column's head: how many pages, and the way to hide it.
class SidebarHeader extends StatelessWidget {
  const SidebarHeader({super.key, required this.count, required this.rtl, required this.onClose});

  final int count;
  final bool rtl;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: Targets.barHit(context),
      child: Row(
        children: [
          const SizedBox(width: SidebarMetrics.side + Gaps.sm),
          Expanded(
            child: Text(
              count == 1 ? '1 page' : '$count pages',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(fontFeatures: AppTheme.tabularFigures),
            ),
          ),
          BarButton(
            icon: rtl ? Symbols.right_panel_close_rounded : Symbols.left_panel_close_rounded,
            tooltip: Targets.touchFirst ? 'Hide pages' : 'Hide pages (F4)',
            onPressed: onClose,
          ),
          const SizedBox(width: Gaps.xs),
        ],
      ),
    );
  }
}
