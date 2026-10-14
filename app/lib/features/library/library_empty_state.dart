import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../domain/notebook.dart';
import '../../ui/app_theme.dart';
import 'library_controller.dart';
import 'notebook_cover.dart';

/// What an empty library view says and offers, tailored to [section].
class LibraryEmptyState extends StatelessWidget {
  const LibraryEmptyState({
    super.key,
    required this.section,
    required this.inFolder,
    required this.query,
    this.onCreate,
    this.onClearSearch,
    this.onImportPdf,
    this.onSetUpSync,
  });

  final LibrarySection section;
  final bool inFolder;
  final String query;
  final VoidCallback? onCreate;

  /// Offered when a search found nothing.
  final VoidCallback? onClearSearch;

  /// First launch: the other ways to start, under New notebook.
  final VoidCallback? onImportPdf;
  final VoidCallback? onSetUpSync;

  /// Windows shorter than this leave the picture out.
  static const double artFrom = 520;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final searching = query.trim().isNotEmpty;
    final (Widget art, String title, String message) = switch (section) {
      _ when searching => (
        const _IconArt(Symbols.search_off_sharp),
        'No results',
        'Nothing matches “${query.trim()}”',
      ),
      LibrarySection.library when inFolder => (
        const _IconArt(Symbols.folder_open_sharp),
        'This folder is empty',
        Targets.touchFirst
            ? 'Create a notebook here, or move notebooks into it with Move to folder'
            : 'Create a notebook here, or drag notebooks onto this folder',
      ),
      LibrarySection.library => (
        const _CoverRow(),
        'No notebooks yet',
        'Create a notebook to start writing, or import a PDF to write on',
      ),
      LibrarySection.favorites => (
        const _IconArt(Symbols.star_sharp),
        'No favourites yet',
        'Add notebooks you use often to favourites, and find them here',
      ),
      LibrarySection.trash => (
        const _IconArt(Symbols.delete_sharp),
        'Trash is empty',
        'Deleted notebooks stay here for 30 days, then they’re deleted forever',
      ),
    };
    final showCreate = onCreate != null && !searching && section == LibrarySection.library;
    final firstLaunch = showCreate && !inFolder;
    final secondary = [
      if (firstLaunch && onImportPdf != null)
        TextButton.icon(
          onPressed: onImportPdf,
          icon: const Icon(Symbols.picture_as_pdf_sharp, size: Glyphs.menu),
          label: const Text('Import PDF…'),
        ),
      if (firstLaunch && onSetUpSync != null)
        TextButton.icon(
          onPressed: onSetUpSync,
          icon: const Icon(Symbols.sync_sharp, size: Glyphs.menu),
          label: const Text('Set up sync…'),
        ),
    ];
    // Short windows (a phone held sideways): no picture, so the button
    // shows without scrolling.
    final short = MediaQuery.sizeOf(context).height < artFrom;
    // A little above the middle, where the eye expects it (the header
    // already sits above it).
    return Align(
      alignment: short ? Alignment.center : const Alignment(0, -0.2),
      child: Padding(
        padding: EdgeInsets.all(short ? Gaps.lg : Gaps.xxl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 400),
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: Motion.slow,
            curve: Motion.standard,
            // A fade only: nothing slides in on its own (DESIGN §5).
            builder: (context, t, child) => Opacity(opacity: t, child: child),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (!short) ...[art, const SizedBox(height: Gaps.xl)],
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
                    icon: const Icon(Symbols.add_sharp),
                    label: const Text('New notebook'),
                  ),
                  if (secondary.isNotEmpty) ...[
                    const SizedBox(height: Gaps.sm),
                    Wrap(alignment: WrapAlignment.center, spacing: Gaps.sm, children: secondary),
                  ],
                ],
                if (searching && onClearSearch != null) ...[
                  const SizedBox(height: Gaps.xl),
                  // Quiet: the least important act on the screen.
                  TextButton.icon(
                    onPressed: onClearSearch,
                    icon: const Icon(Symbols.close_sharp),
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

/// The section's glyph, bare (no disc; DESIGN §6 dialog glyphs).
class _IconArt extends StatelessWidget {
  const _IconArt(this.icon);

  final IconData icon;

  @override
  Widget build(BuildContext context) =>
      Icon(icon, size: Glyphs.empty, color: Theme.of(context).colorScheme.onSurfaceVariant);
}

/// Three upright notebook covers in a row: the shelf the library becomes.
class _CoverRow extends StatelessWidget {
  const _CoverRow();

  static const double _width = 56;

  @override
  Widget build(BuildContext context) {
    final brightness = Theme.of(context).brightness;
    Widget cover(int index) => Container(
      width: _width,
      height: _width / 0.72,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Radii.sm),
        boxShadow: Shadows.low(brightness),
      ),
      child: NotebookCover(color: Palette.covers[index], kind: NotebookKind.paged),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: Gaps.md,
      children: [for (var i = 0; i < 3; i++) cover(i)],
    );
  }
}
