import 'package:flutter/material.dart';

import '../../domain/folder.dart';
import '../../domain/notebook.dart';
import '../../ui/app_theme.dart';
import '../../ui/scroll_fade.dart';
import 'cover_grid.dart';
import 'folder_tile.dart';
import 'library_actions.dart';
import 'notebook_card.dart';
import 'recent_row.dart';

/// The library's folders (DESIGN §6.1): a ruled row of names on the
/// covers' columns (each folder spans as many as its name needs), a
/// hairline under the row; or, with [strip] (short windows, beside the
/// title), one line that scrolls sideways.
class FolderRow extends StatelessWidget {
  const FolderRow({
    super.key,
    required this.folders,
    required this.actions,
    required this.coverWidth,
    required this.spacing,
    required this.viewportHeight,
  }) : strip = false,
       recent = const [];

  /// One scrolling line of [folders], without the hairline; [recent]
  /// notebooks first, as one Recent item that lists them.
  const FolderRow.strip({
    super.key,
    required this.folders,
    required this.actions,
    this.recent = const [],
  }) : strip = true,
       coverWidth = 0,
       spacing = 0,
       viewportHeight = 0;

  final List<Folder> folders;
  final LibraryActions actions;
  final List<Notebook> recent;
  final bool strip;

  /// The grid's cover width, column spacing and viewport height: folders
  /// sit on the grid's columns.
  final double coverWidth;
  final double spacing;
  final double viewportHeight;

  String _caption(Folder f) {
    final n = actions.controller.itemCountIn(f.id);
    return n == 0 ? 'Empty' : '$n ${n == 1 ? 'item' : 'items'}';
  }

  Widget _tile(Folder f, {bool dense = false}) => FolderTile(
    key: ValueKey('folder-${f.id}'),
    folder: f,
    subtitle: _caption(f),
    actions: actions,
    dense: dense,
  );

  @override
  Widget build(BuildContext context) {
    final minTile = FolderTile.minWidth * MediaQuery.textScalerOf(context).scale(1);
    if (strip) {
      return ScrollFade(
        child: Row(
          children: [
            if (recent.isNotEmpty) ...[
              SizedBox(
                width: minTile,
                child: RecentStripTile(notebooks: recent, actions: actions),
              ),
              const SizedBox(width: Gaps.sm),
            ],
            for (final (i, f) in folders.indexed) ...[
              if (i > 0) const SizedBox(width: Gaps.sm),
              SizedBox(width: minTile, child: _tile(f, dense: true)),
            ],
          ],
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = CoverGridDelegate.columnsFor(
          width,
          coverWidth,
          spacing,
          height: viewportHeight,
          captionHeight: NotebookCard.captionHeight(MediaQuery.textScalerOf(context)),
        );
        final column = (width - spacing * (columns - 1)) / columns;
        double spanWidth(int span) => column * span + spacing * (span - 1);
        // Large text or narrow columns: a folder spans two or more columns
        // rather than cutting its name off.
        var span = 1;
        while (span < columns && spanWidth(span) < minTile) {
          span++;
        }
        final rule = Theme.of(context).colorScheme.outlineVariant;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (span == columns)
              // One folder per line (large text, phones): ruled like list
              // rows, a hairline between them that starts at the names.
              for (final (i, f) in folders.indexed) ...[
                if (i > 0)
                  Divider(height: Hairline.width, indent: FolderTile.textInset, color: rule),
                _tile(f),
              ]
            else
              Wrap(
                spacing: spacing,
                runSpacing: Gaps.xxs,
                children: [
                  for (final f in folders) SizedBox(width: spanWidth(span), child: _tile(f)),
                ],
              ),
            const SizedBox(height: Gaps.md),
            Divider(height: Hairline.width, color: rule),
          ],
        );
      },
    );
  }
}
