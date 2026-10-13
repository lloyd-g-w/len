import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../app_services.dart';
import '../../ui/app_theme.dart';

/// Puts a notice above the library's [child] while something needs the
/// user's attention: files that won't be kept (a browser that refused
/// storage, UX_AUDIT P0-1).
class LibraryNotices extends StatelessWidget {
  const LibraryNotices({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final services = AppScope.of(context);
    if (services.blobsArePersistent) return child;
    return Column(
      children: [
        const SafeArea(
          bottom: false,
          child: LibraryNotice(
            icon: Symbols.cloud_off_rounded,
            title: 'Files you add won\'t be kept in this browser window',
            body:
                'This browser doesn\'t let Len store files, so PDFs, images and recordings '
                'are lost when the tab closes (your handwriting is kept). Use a normal '
                'window, allow site data, or turn on sync.',
          ),
        ),
        Expanded(
          child: MediaQuery.removePadding(context: context, removeTop: true, child: child),
        ),
      ],
    );
  }
}

/// A calm, error-tinted banner: an icon, a title and a sentence or two.
class LibraryNotice extends StatelessWidget {
  const LibraryNotice({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.action,
  });

  final IconData icon;
  final String title;
  final String body;

  /// A button at the end (e.g. "Settings").
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.fromLTRB(Gaps.md, Gaps.md, Gaps.md, 0),
        padding: const EdgeInsets.fromLTRB(Gaps.md, Gaps.md, Gaps.md, Gaps.md),
        decoration: BoxDecoration(
          color: scheme.error.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: Glyphs.menu, color: scheme.error),
            const SizedBox(width: Gaps.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.labelLarge),
                  const SizedBox(height: Gaps.xxs),
                  Text(body, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
            if (action case final action?) ...[const SizedBox(width: Gaps.sm), action],
          ],
        ),
      ),
    );
  }
}
