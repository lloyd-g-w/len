import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../ui/app_theme.dart';
import 'library_actions.dart';
import 'library_drag.dart';

/// "Library › School › Maths": every segment but the last navigates, and
/// accepts dropped items.
class LibraryBreadcrumbs extends StatelessWidget {
  const LibraryBreadcrumbs({super.key, required this.actions});

  final LibraryActions actions;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final path = actions.controller.breadcrumbs;
    final segments = <({String? id, String name})>[
      (id: null, name: 'Library'),
      for (final f in path.take(path.length - 1)) (id: f.id, name: f.name),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (final s in segments) ...[
            LibraryDropTarget(
              canAccept: (item) => actions.canDrop(item, s.id),
              onAccept: (item) => actions.drop(context, item, s.id),
              builder: (context, active) => AnimatedContainer(
                duration: Motion.fast,
                decoration: BoxDecoration(
                  color: active ? scheme.primary.withValues(alpha: 0.12) : Colors.transparent,
                  borderRadius: BorderRadius.circular(Radii.xs),
                ),
                child: TextButton(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 32),
                    padding: const EdgeInsets.symmetric(horizontal: Gaps.sm),
                    foregroundColor: scheme.onSurfaceVariant,
                    textStyle: theme.textTheme.labelLarge,
                  ),
                  onPressed: () => actions.controller.openFolder(s.id),
                  child: Text(s.name),
                ),
              ),
            ),
            Icon(Symbols.chevron_right_sharp, size: Glyphs.menu, color: scheme.outline),
          ],
        ],
      ),
    );
  }
}
