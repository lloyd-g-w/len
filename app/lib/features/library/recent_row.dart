import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../domain/notebook.dart';
import '../../ui/app_theme.dart';
import '../../ui/menus.dart';
import '../../ui/mini_cover.dart';
import '../../ui/scroll_fade.dart';
import '../../ui/section_label.dart';
import 'cover_grid.dart';
import 'folder_tile.dart';
import 'library_actions.dart';
import 'notebook_card.dart';

/// The library root's Recent row (UX_AUDIT R7-6): the notebooks opened
/// lately, wherever they are filed, one tap each. Ruled like the folder
/// row: names on the covers' columns (each a small cover in its colour,
/// the title and where it lives), one line that scrolls sideways when
/// they don't all fit, a hairline under it.
class RecentRow extends StatelessWidget {
  const RecentRow({
    super.key,
    required this.notebooks,
    required this.actions,
    required this.coverWidth,
    required this.spacing,
    required this.viewportHeight,
  });

  final List<Notebook> notebooks;
  final LibraryActions actions;

  /// The grid's cover width, column spacing and viewport height: the
  /// names sit on the grid's columns.
  final double coverWidth;
  final double spacing;
  final double viewportHeight;

  /// How much of the first name past the edge shows.
  static const double _peek = 0.35;

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context);
    final minTile = FolderTile.minWidth * scaler.scale(1);
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = CoverGridDelegate.columnsFor(
          width,
          coverWidth,
          spacing,
          height: viewportHeight,
          captionHeight: NotebookCard.captionHeight(scaler),
        );
        final column = (width - spacing * (columns - 1)) / columns;
        var span = 1;
        while (span < columns && column * span + spacing * (span - 1) < minTile) {
          span++;
        }
        // A whole line per name (phones, large text) would hide the rest:
        // then names keep their narrowest width, and the line scrolls.
        var tile = span == columns
            ? math.min(minTile, width)
            : column * span + spacing * (span - 1);
        final gap = span == columns ? Gaps.sm : spacing;
        // More than fit: the next one peeks in at the edge, so the line
        // shows it scrolls.
        final fits = math.max(1, ((width + gap) / (tile + gap)).floor());
        if (notebooks.length > fits) tile = (width - gap * fits) / (fits + _peek);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Padding(
              padding: EdgeInsets.only(left: Gaps.xxs, bottom: Gaps.xxs),
              child: SectionLabel('Recent'),
            ),
            ScrollFade(
              child: Row(
                children: [
                  for (final (i, n) in notebooks.indexed) ...[
                    if (i > 0) SizedBox(width: gap),
                    SizedBox(
                      width: tile,
                      child: RecentTile(
                        key: ValueKey('recent-${n.id}'),
                        notebook: n,
                        caption: actions.controller.locationOf(n),
                        onOpen: () => unawaited(actions.openNotebook(context, n)),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: Gaps.md),
            Divider(height: Hairline.width, color: Theme.of(context).colorScheme.outlineVariant),
          ],
        );
      },
    );
  }
}

/// A notebook in the Recent row: a small cover in its colour (with the
/// darker spine), its title and where it lives; opens on tap.
class RecentTile extends StatefulWidget {
  const RecentTile({
    super.key,
    required this.notebook,
    required this.caption,
    required this.onOpen,
  });

  final Notebook notebook;
  final String caption;
  final VoidCallback onOpen;

  @override
  State<RecentTile> createState() => _RecentTileState();
}

class _RecentTileState extends State<RecentTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final radius = BorderRadius.circular(Radii.xs);
    return AnimatedContainer(
      duration: Motion.fast,
      height: math.max(52, MediaQuery.textScalerOf(context).scale(20 + 16) + Gaps.lg),
      decoration: BoxDecoration(
        color: _hovered ? Surfaces.hovered(scheme) : Colors.transparent,
        borderRadius: radius,
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: radius,
          onTap: widget.onOpen,
          onHover: (h) => setState(() => _hovered = h),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gaps.xxs),
            child: Row(
              children: [
                MiniCover(color: Color(widget.notebook.coverColor)),
                const SizedBox(width: Gaps.md), // FolderTile.textInset
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.notebook.title,
                        style: theme.textTheme.labelLarge,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        widget.caption,
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
    );
  }
}

/// Short windows' Recent (a phone held sideways): the first item of the
/// folder strip beside the title, as low as a touch target, that lists
/// the notebooks opened lately in a menu (one row of chrome has no room
/// for the Recent row).
class RecentStripTile extends StatelessWidget {
  const RecentStripTile({super.key, required this.notebooks, required this.actions});

  final List<Notebook> notebooks;
  final LibraryActions actions;

  Future<void> _open(BuildContext anchor) async {
    final chosen = await showMenuBelow<Notebook>(
      anchor,
      items: [
        for (final n in notebooks)
          MenuRow(
            value: n,
            leading: MiniCover(color: Color(n.coverColor)),
            label: n.title,
          ),
      ],
    );
    if (chosen != null && anchor.mounted) await actions.openNotebook(anchor, chosen);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final count = notebooks.length;
    return Semantics(
      button: true,
      child: SizedBox(
        height: math.max(Targets.touch, MediaQuery.textScalerOf(context).scale(20 + 16) + Gaps.sm),
        child: Builder(
          builder: (anchor) => InkWell(
            borderRadius: BorderRadius.circular(Radii.xs),
            onTap: () => unawaited(_open(anchor)),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Gaps.xxs),
              child: Row(
                children: [
                  Icon(Symbols.history_sharp, size: Glyphs.bar, color: theme.colorScheme.onSurface),
                  const SizedBox(width: Gaps.md), // FolderTile.textInset
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Recent', style: theme.textTheme.labelLarge, maxLines: 1),
                        Text(
                          count == 1 ? '1 notebook' : '$count notebooks',
                          style: theme.textTheme.bodySmall,
                          maxLines: 1,
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Symbols.expand_more_sharp,
                    size: Glyphs.menu,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
