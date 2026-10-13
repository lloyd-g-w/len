import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/notebook.dart';
import '../../ui/app_theme.dart';
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

/// A notebook's cover at glyph size: flat colour, a darker spine band
/// (DESIGN §6.1), in the space of a [Glyphs.bar] icon. Paper, so it keeps
/// the contact shadow.
class MiniCover extends StatelessWidget {
  const MiniCover({super.key, required this.color});

  final Color color;

  /// A cover's proportions at glyph height, and its spine band (as dark
  /// as the big covers' plain spines).
  static const double _width = Glyphs.bar * 0.8;
  static const double _spine = 3;
  static const double _spineShade = 0.18;

  @override
  Widget build(BuildContext context) => Container(
    width: _width,
    height: Glyphs.bar,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: color,
      borderRadius: BorderRadius.circular(Radii.xs),
      boxShadow: Shadows.low(Theme.of(context).brightness),
    ),
    alignment: Alignment.centerLeft,
    child: Container(width: _spine, color: Color.lerp(color, Colors.black, _spineShade)),
  );
}
