import 'package:flutter/material.dart';

import '../../domain/tag.dart';
import '../../ui/app_theme.dart';

/// A tag's colour as a small dot (cards, sidebar, menus).
class TagDot extends StatelessWidget {
  const TagDot(this.color, {super.key, this.size = 10});

  final int color;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(
      color: Color(color),
      shape: BoxShape.circle,
      border: Border.all(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
        width: size > 8 ? 1.5 : 1,
      ),
    ),
  );
}

/// The tags of a notebook as overlapping dots, with a tooltip naming them.
class TagDots extends StatelessWidget {
  const TagDots(this.tags, {super.key, this.size = 10, this.max = 4});

  final List<Tag> tags;
  final double size;

  /// At most this many dots are drawn.
  final int max;

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();
    final shown = tags.take(max).toList();
    final step = size * 0.7;
    return Tooltip(
      message: tags.map((t) => t.name).join(', '),
      child: SizedBox(
        width: size + step * (shown.length - 1),
        height: size,
        child: Stack(
          children: [
            for (var i = 0; i < shown.length; i++)
              Positioned(
                left: step * i,
                child: TagDot(shown[i].color, size: size),
              ),
          ],
        ),
      ),
    );
  }
}

/// A tag as a filter chip: dot, name and an optional count.
class TagFilterChip extends StatelessWidget {
  const TagFilterChip({
    super.key,
    required this.tag,
    required this.selected,
    required this.onSelected,
    this.count,
  });

  final Tag tag;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final int? count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = Color(tag.color);
    return FilterChip(
      key: ValueKey('tag-chip-${tag.id}'),
      showCheckmark: false,
      selected: selected,
      onSelected: onSelected,
      avatar: TagDot(tag.color, size: 10),
      selectedColor: color.withValues(alpha: 0.18),
      side: BorderSide(color: selected ? color : scheme.outlineVariant),
      visualDensity: VisualDensity.compact,
      labelPadding: const EdgeInsets.only(right: Gaps.xxs),
      label: Text(count == null ? tag.name : '${tag.name}  $count'),
    );
  }
}
