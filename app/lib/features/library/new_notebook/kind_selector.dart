import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../domain/notebook.dart';
import '../../../ui/app_theme.dart';

/// Notebook or infinite canvas, as two side-by-side choice cards.
class KindSelector extends StatelessWidget {
  const KindSelector({super.key, required this.kind, required this.onChanged});

  final NotebookKind kind;
  final ValueChanged<NotebookKind> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _KindCard(
            icon: Symbols.menu_book_rounded,
            label: 'Notebook',
            description: 'Page by page',
            selected: kind == NotebookKind.paged,
            onTap: () => onChanged(NotebookKind.paged),
          ),
        ),
        const SizedBox(width: Gaps.sm),
        Expanded(
          child: _KindCard(
            icon: Symbols.all_inclusive_rounded,
            label: 'Infinite canvas',
            description: 'Endless board',
            selected: kind == NotebookKind.canvas,
            onTap: () => onChanged(NotebookKind.canvas),
          ),
        ),
      ],
    );
  }
}

class _KindCard extends StatelessWidget {
  const _KindCard({
    required this.icon,
    required this.label,
    required this.description,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final String description;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = BorderRadius.circular(Radii.sm);
    return Semantics(
      selected: selected,
      button: true,
      label: '$label: $description',
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: Motion.medium,
        curve: Motion.standard,
        decoration: BoxDecoration(
          color: selected ? scheme.primary.withValues(alpha: 0.10) : scheme.surfaceContainer,
          borderRadius: radius,
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 1.6 : 1,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: radius,
            onTap: onTap,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Gaps.md, vertical: Gaps.sm),
                child: Row(
                  children: [
                    Icon(
                      icon,
                      size: 22,
                      color: selected ? scheme.primary : scheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: Gaps.sm + 2),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            label,
                            style: theme.textTheme.titleSmall?.copyWith(
                              color: selected ? scheme.primary : null,
                            ),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            description,
                            style: theme.textTheme.bodySmall,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
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
