import 'package:flutter/material.dart';

import '../app_theme.dart';
import '../color_dot.dart';
import '../even_grid.dart';
import '../section_label.dart';

const double _favoriteSize = 30;

/// The favourite colours (long press removes one) and an add button.
class FavoritesRow extends StatelessWidget {
  const FavoritesRow({
    super.key,
    required this.favorites,
    required this.selected,
    required this.onTap,
    required this.onAdd,
    required this.onRemove,
  });

  final List<int> favorites;
  final int selected;
  final ValueChanged<int> onTap;
  final VoidCallback onAdd;
  final ValueChanged<int>? onRemove;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SectionLabel('Favourites'),
        const SizedBox(height: Gaps.xs),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final c in favorites)
              ColorDot(
                color: c,
                size: _favoriteSize,
                selected: c == selected,
                onTap: () => onTap(c),
                onLongPress: onRemove == null ? null : () => onRemove!(c),
                tooltip: 'Long-press to remove',
              ),
            Tooltip(
              message: 'Add current colour to favourites',
              child: InkResponse(
                onTap: onAdd,
                radius: 18,
                child: Container(
                  width: _favoriteSize,
                  height: _favoriteSize,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: scheme.outline),
                  ),
                  child: Icon(Icons.add_rounded, size: 18, color: scheme.onSurfaceVariant),
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

/// One row of recently picked colours; a tap applies one.
class RecentColorsRow extends StatelessWidget {
  const RecentColorsRow({
    super.key,
    required this.colors,
    required this.selected,
    required this.onTap,
  });

  final List<int> colors;
  final int selected;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const SectionLabel('Recent'),
        const SizedBox(height: Gaps.xs),
        EvenGrid(
          itemExtent: _favoriteSize,
          maxSpacing: Gaps.sm,
          children: [
            for (final c in colors)
              ColorDot(
                color: c,
                size: _favoriteSize,
                selected: c == selected,
                onTap: () => onTap(c),
              ),
          ],
        ),
      ],
    );
  }
}
