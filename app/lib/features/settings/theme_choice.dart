import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../domain/preferences.dart';
import '../../ui/app_theme.dart';

/// System / light / dark as three miniature app previews.
class ThemeChoice extends StatelessWidget {
  const ThemeChoice({super.key, required this.value, required this.onChanged});

  final ThemePreference value;
  final ValueChanged<ThemePreference> onChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        for (final (i, (mode, label)) in const [
          (ThemePreference.system, 'System'),
          (ThemePreference.light, 'Light'),
          (ThemePreference.dark, 'Dark'),
        ].indexed) ...[
          if (i > 0) const SizedBox(width: Gaps.md),
          Expanded(
            child: _ThemeCard(
              mode: mode,
              label: label,
              selected: value == mode,
              onTap: () => onChanged(mode),
            ),
          ),
        ],
      ],
    );
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.mode,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final ThemePreference mode;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final light = AppTheme.scheme(Brightness.light);
    final dark = AppTheme.scheme(Brightness.dark);
    final preview = switch (mode) {
      ThemePreference.light => _Mock(scheme: light),
      ThemePreference.dark => _Mock(scheme: dark),
      ThemePreference.system => Row(
        children: [
          Expanded(
            child: ClipRect(
              child: Align(
                alignment: Alignment.centerLeft,
                widthFactor: 0.5,
                child: _Mock(scheme: light),
              ),
            ),
          ),
          Expanded(
            child: ClipRect(
              child: Align(
                alignment: Alignment.centerRight,
                widthFactor: 0.5,
                child: _Mock(scheme: dark),
              ),
            ),
          ),
        ],
      ),
    };
    return Semantics(
      button: true,
      selected: selected,
      label: '$label theme',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(Radii.sm),
        child: Column(
          children: [
            AnimatedContainer(
              duration: Motion.fast,
              height: 76,
              padding: const EdgeInsets.all(3),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(Radii.sm),
                border: Border.all(
                  color: selected ? scheme.primary : scheme.outlineVariant,
                  width: selected ? 2.5 : 1,
                ),
              ),
              child: ClipRRect(borderRadius: BorderRadius.circular(Radii.xs), child: preview),
            ),
            const SizedBox(height: Gaps.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (selected) ...[
                  Icon(Symbols.check_circle_rounded, fill: 1, size: 16, color: scheme.primary),
                  const SizedBox(width: Gaps.xs),
                ],
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelLarge?.copyWith(
                      color: selected ? scheme.primary : scheme.onSurface,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// A tiny library: a sidebar strip, a title bar and two covers.
class _Mock extends StatelessWidget {
  const _Mock({required this.scheme});

  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    Widget bar(double width, Color color) => Container(
      width: width,
      height: 6,
      decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(3)),
    );
    return ColoredBox(
      color: scheme.surface,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(width: 18, color: scheme.surfaceContainerLow),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.all(Gaps.sm),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  bar(36, scheme.onSurface.withValues(alpha: 0.7)),
                  const SizedBox(height: Gaps.sm),
                  Expanded(
                    child: ClipRect(
                      child: OverflowBox(
                        alignment: Alignment.topLeft,
                        maxWidth: double.infinity,
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            for (final c in [scheme.primary, const Color(0xFFF08C00)]) ...[
                              Container(
                                width: 22,
                                height: 30,
                                decoration: BoxDecoration(
                                  color: c,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                              const SizedBox(width: Gaps.xs),
                            ],
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
