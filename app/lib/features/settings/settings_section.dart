import 'package:flutter/material.dart';

import '../../ui/app_theme.dart';
import '../../ui/section_label.dart';

/// A titled group of settings (DESIGN §6.4): an open ruled list on the
/// Board, no plate and no shadow. A hairline opens the section; the
/// heading (Small label, Graphite) hangs in the left margin column on wide
/// screens and sits above the rows on narrow ones; rows are separated by
/// hairlines that start at the text. An optional description says what
/// the section is for before its rows (the explanation before the form),
/// level with the heading.
///
/// The section is laid out [SettingsTile.edge] wider than the margin on
/// each side, so a row's hover and press plate overhangs the text a
/// little while icons, headings and rules keep to the margin.
class SettingsSection extends StatelessWidget {
  const SettingsSection({super.key, required this.title, required this.children, this.description});

  final String title;
  final String? description;
  final List<Widget> children;

  /// The margin column holding the headings on wide screens.
  static const double headingColumn = 160;

  /// The narrowest section whose heading hangs in the margin column.
  static const double hangsFrom = 600;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    const edge = SettingsTile.edge;
    return Padding(
      padding: const EdgeInsets.only(bottom: Gaps.xl),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final hangs =
              constraints.maxWidth >= hangsFrom && MediaQuery.textScalerOf(context).scale(1) < 1.5;
          final rows = Material(
            type: MaterialType.transparency,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (description case final text?)
                  Padding(
                    // At the rows' text; level with a hanging heading, under
                    // one above the rows.
                    padding: EdgeInsets.fromLTRB(
                      hangs ? SettingsTile.textInset : edge,
                      hangs ? Gaps.lg : 0,
                      edge,
                      Gaps.xs,
                    ),
                    child: Text(text, style: theme.textTheme.bodySmall),
                  ),
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0)
                    Divider(
                      height: Hairline.width,
                      thickness: Hairline.width,
                      indent: SettingsTile.textInset,
                      endIndent: edge,
                      color: scheme.outlineVariant,
                    ),
                  children[i],
                ],
              ],
            ),
          );
          final heading = Padding(
            padding: const EdgeInsets.fromLTRB(edge, Gaps.lg, edge, 0),
            child: SectionLabel(title),
          );
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Divider(
                height: Hairline.width,
                thickness: Hairline.width,
                indent: edge,
                endIndent: edge,
                color: scheme.outlineVariant,
              ),
              if (hangs)
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(width: edge + headingColumn, child: heading),
                    Expanded(child: rows),
                  ],
                )
              else ...[
                heading,
                const SizedBox(height: Gaps.xs),
                rows,
              ],
            ],
          );
        },
      ),
    );
  }
}

/// A settings row (DESIGN §6.4): an 18-dp leading icon, a Body title and a
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

  /// How far a row's plate overhangs its icon and its control.
  static const double edge = Gaps.sm;

  /// Where the text starts (after the icon), for hairlines.
  static const double textInset = edge + Glyphs.menu + Gaps.lg;

  /// The narrowest row whose [control] trails.
  static const double controlTrailsFrom = 520;

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
          borderRadius: BorderRadius.circular(Radii.xs),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: edge, vertical: Gaps.md),
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
