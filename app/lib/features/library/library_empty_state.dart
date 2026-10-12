import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../domain/notebook.dart';
import '../../ui/app_theme.dart';
import 'library_controller.dart';
import 'notebook_cover.dart';

/// Friendly placeholder for an empty library view, tailored to [section].
class LibraryEmptyState extends StatelessWidget {
  const LibraryEmptyState({
    super.key,
    required this.section,
    required this.inFolder,
    required this.query,
    this.onCreate,
    this.onClearSearch,
  });

  final LibrarySection section;
  final bool inFolder;
  final String query;
  final VoidCallback? onCreate;

  /// Offered when a search found nothing.
  final VoidCallback? onClearSearch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final searching = query.trim().isNotEmpty;
    final (Widget art, String title, String message) = switch (section) {
      _ when searching => (
        const _IconArt(Symbols.search_off_rounded),
        'No results',
        'Nothing matches “${query.trim()}”.',
      ),
      LibrarySection.library when inFolder => (
        const _IconArt(Symbols.folder_open_rounded),
        'This folder is empty',
        'Create a notebook here, or drag notebooks onto this folder.',
      ),
      LibrarySection.library => (
        const _CoverFan(),
        'Nothing here yet',
        'Create a notebook or an infinite canvas to start writing.',
      ),
      LibrarySection.favorites => (
        const _IconArt(Symbols.star_rounded),
        'No favourites yet',
        'Star notebooks you use often to find them here.',
      ),
      LibrarySection.trash => (
        const _IconArt(Symbols.delete_rounded),
        'Trash is empty',
        'Deleted notebooks stay here until you delete them forever.',
      ),
    };
    final showCreate = onCreate != null && !searching && section == LibrarySection.library;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(Gaps.xxl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 360),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: Motion.slow,
            curve: Motion.emphasized,
            builder: (context, t, child) => Opacity(
              opacity: t,
              child: Transform.translate(offset: Offset(0, 12 * (1 - t)), child: child),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                art,
                const SizedBox(height: Gaps.xl),
                Text(title, style: theme.textTheme.titleLarge, textAlign: TextAlign.center),
                const SizedBox(height: Gaps.sm),
                Text(
                  message,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                ),
                if (showCreate) ...[
                  const SizedBox(height: Gaps.xl),
                  FilledButton.icon(
                    onPressed: onCreate,
                    icon: const Icon(Symbols.add_rounded),
                    label: Text(inFolder ? 'New notebook here' : 'New notebook'),
                  ),
                ],
                if (searching && onClearSearch != null) ...[
                  const SizedBox(height: Gaps.xl),
                  OutlinedButton.icon(
                    onPressed: onClearSearch,
                    icon: const Icon(Symbols.close_rounded),
                    label: const Text('Clear search'),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _IconArt extends StatelessWidget {
  const _IconArt(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 96,
      height: 96,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: scheme.surfaceContainerHigh,
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Icon(icon, size: Glyphs.empty, color: scheme.onSurfaceVariant),
    );
  }
}

/// Three fanned-out notebook covers.
class _CoverFan extends StatelessWidget {
  const _CoverFan();

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    Widget cover(int color, double angle, Offset offset) => Transform.translate(
      offset: offset,
      child: Transform.rotate(
        angle: angle,
        child: Container(
          width: 72,
          height: 100,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(Radii.sm),
            boxShadow: Shadows.low(brightness),
          ),
          child: NotebookCover(color: color, kind: NotebookKind.paged),
        ),
      ),
    );
    return SizedBox(
      width: 200,
      height: 128,
      child: Stack(
        alignment: Alignment.center,
        children: [
          cover(Palette.covers[1], -0.22, const Offset(-48, 8)),
          cover(Palette.covers[2], 0.22, const Offset(48, 8)),
          cover(Palette.covers[0], 0, Offset.zero),
        ],
      ),
    );
  }
}
