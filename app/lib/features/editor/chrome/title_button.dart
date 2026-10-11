import 'package:flutter/material.dart';

import '../../../ui/app_theme.dart';

/// The notebook title in the top bar (start-aligned, with an optional
/// quiet subtitle); tap to rename.
class TitleButton extends StatelessWidget {
  const TitleButton({super.key, required this.title, required this.onRename, this.subtitle});

  final String title;

  /// A quiet second line (e.g. "Page 3 of 12").
  final String? subtitle;
  final VoidCallback onRename;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Tooltip(
      message: 'Rename',
      child: InkWell(
        onTap: onRename,
        borderRadius: BorderRadius.circular(Radii.sm),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360, minHeight: 40),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gaps.sm, vertical: Gaps.xxs),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall?.copyWith(color: scheme.onSurface),
                ),
                if (subtitle case final subtitle?)
                  Text(
                    subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
