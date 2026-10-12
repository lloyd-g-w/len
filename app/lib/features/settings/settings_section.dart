import 'package:flutter/material.dart';

import '../../ui/app_theme.dart';

/// A titled group of settings rendered as one rounded card. Under
/// [SettingsSection.untitled] the title row is left out (the two-pane
/// layout's selected list entry names the section already).
class SettingsSection extends StatelessWidget {
  const SettingsSection({
    super.key,
    required this.title,
    required this.icon,
    required this.children,
    this.description,
  });

  final String title;
  final IconData icon;
  final String? description;
  final List<Widget> children;

  /// Sections in [child] show no title row.
  static Widget untitled({required Widget child}) => _UntitledScope(child: child);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final titled = context.dependOnInheritedWidgetOfExactType<_UntitledScope>() == null;
    return Padding(
      padding: const EdgeInsets.only(bottom: Gaps.xxl),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (titled)
            Padding(
              padding: const EdgeInsets.only(left: Gaps.xs, bottom: Gaps.md),
              child: Row(
                children: [
                  Icon(icon, size: 20, color: scheme.primary),
                  const SizedBox(width: Gaps.sm),
                  Text(title, style: theme.textTheme.titleMedium),
                ],
              ),
            ),
          if (description != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(Gaps.xs, 0, Gaps.xs, Gaps.md),
              child: Text(
                description!,
                style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: theme.brightness == Brightness.dark
                  ? scheme.surfaceContainerLow
                  : scheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(Radii.card),
              border: Border.all(color: scheme.outlineVariant),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(Radii.card),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (var i = 0; i < children.length; i++) ...[
                    if (i > 0) const Divider(indent: Gaps.lg, endIndent: Gaps.lg),
                    children[i],
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _UntitledScope extends InheritedWidget {
  const _UntitledScope({required super.child});

  @override
  bool updateShouldNotify(_UntitledScope old) => false;
}

/// A settings row with a title, optional subtitle and a trailing control,
/// or with a control below the text when [below] is set.
class SettingsTile extends StatelessWidget {
  const SettingsTile({
    super.key,
    required this.title,
    this.subtitle,
    this.trailing,
    this.below,
    this.onTap,
    this.icon,
  });

  /// Leading symbol, aligned with the title.
  final IconData? icon;

  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Widget? below;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final text = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: theme.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w500,
            letterSpacing: 0.1,
          ),
        ),
        if (subtitle != null) ...[
          const SizedBox(height: Gaps.xxs),
          Text(subtitle!, style: theme.textTheme.bodySmall),
        ],
      ],
    );
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: Gaps.lg + 2, vertical: Gaps.md + 2),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                if (icon != null) ...[
                  Icon(icon, size: 22, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: Gaps.lg),
                ],
                Expanded(child: text),
                if (trailing != null) ...[const SizedBox(width: Gaps.lg), trailing!],
              ],
            ),
            if (below != null) ...[
              const SizedBox(height: Gaps.md),
              Padding(
                padding: EdgeInsets.only(left: icon == null ? 0 : 22 + Gaps.lg),
                child: below,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
