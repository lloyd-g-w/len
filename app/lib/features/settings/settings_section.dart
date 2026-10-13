import 'package:flutter/material.dart';

import '../../ui/app_theme.dart';
import '../../ui/section_label.dart';

/// A titled group of settings (REDESIGN §4): a quiet heading, the rows on
/// one rounded plate separated by hairlines, then an optional description.
class SettingsSection extends StatelessWidget {
  const SettingsSection({super.key, required this.title, required this.children, this.description});

  final String title;
  final String? description;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    return Padding(
      padding: const EdgeInsets.only(bottom: Gaps.xl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(Gaps.lg, 0, Gaps.lg, Gaps.sm),
            child: SectionLabel(title),
          ),
          // No card without rows (a section can be only its caption).
          if (children.isNotEmpty)
            DecoratedBox(
              decoration: BoxDecoration(
                color: dark ? scheme.surfaceContainerLow : scheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(Radii.md),
                // No outlines in light mode (REDESIGN §1.1): a soft raise instead.
                border: dark ? Border.all(color: scheme.outlineVariant) : null,
                boxShadow: dark ? null : Shadows.low(theme.brightness),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(Radii.md),
                child: Material(
                  type: MaterialType.transparency,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var i = 0; i < children.length; i++) ...[
                        if (i > 0)
                          Divider(
                            height: 1,
                            indent: SettingsTile.textInset,
                            color: scheme.outlineVariant.withValues(alpha: 0.6),
                          ),
                        children[i],
                      ],
                    ],
                  ),
                ),
              ),
            ),
          if (description case final text?)
            Padding(
              padding: const EdgeInsets.fromLTRB(Gaps.lg, Gaps.sm, Gaps.lg, 0),
              child: Text(text, style: theme.textTheme.bodySmall),
            ),
        ],
      ),
    );
  }
}

/// A settings row (REDESIGN §4): an 18-dp leading icon, a Body title and a
/// Caption subtitle. Its [control] (a segmented button, a switch) trails on
/// wide rows and goes below the text on narrow ones; [trailing] always
/// trails and [below] always goes below.
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.control,
    this.below,
    this.onTap,
    this.icon,
  });

  /// Where the text starts (after the icon), for hairlines.
  static const double textInset = Gaps.lg + Glyphs.menu + Gaps.lg;

  /// The narrowest row whose [control] trails.
  static const double controlTrailsFrom = 560;

  /// Leading symbol, aligned with the title.
  final IconData? icon;

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? control;
  final Widget? below;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.bodyMedium),
        if (subtitle != null) ...[
          const SizedBox(height: Gaps.xxs),
          Text(subtitle!, style: theme.textTheme.bodySmall),
        ],
      ],
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // Large text: a control beside the title would squeeze it (or
        // overflow), so it goes below.
        final controlTrails =
            constraints.maxWidth >= controlTrailsFrom &&
            MediaQuery.textScalerOf(context).scale(1) < 1.5;
        final trailing = this.trailing ?? (controlTrails ? control : null);
        final below = this.below ?? (controlTrails ? null : control);
        final tile = InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gaps.lg, vertical: Gaps.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: Targets.bar - Gaps.xs),
                  child: Row(
                    children: [
                      SizedBox(
                        width: Glyphs.menu,
                        child: icon == null
                            ? null
                            : Icon(
                                icon,
                                size: Glyphs.menu,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                      ),
                      const SizedBox(width: Gaps.lg),
                      Expanded(child: text),
                      if (trailing != null) ...[const SizedBox(width: Gaps.lg), trailing],
                    ],
                  ),
                ),
                if (below != null) ...[
                  const SizedBox(height: Gaps.md),
                  Padding(
                    padding: const EdgeInsets.only(left: Glyphs.menu + Gaps.lg),
                    child: below,
                  ),
                ],
              ],
            ),
          ),
        );
        // A row that toggles its switch (or opens a page) when tapped reads
        // as one control: its title names the switch.
        return onTap != null && below == null ? MergeSemantics(child: tile) : tile;
      },
    );
  }
}
