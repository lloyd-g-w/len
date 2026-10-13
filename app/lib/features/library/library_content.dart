import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../data/notebook_repository.dart';
import '../../domain/folder.dart';
import '../../domain/notebook.dart';
import '../../domain/preferences.dart';
import '../../ui/app_theme.dart';
import '../search/library_search_results.dart';
import '../settings/settings_screen.dart';
import 'folder_tile.dart';
import 'library_actions.dart';
import 'library_controller.dart';
import 'library_empty_state.dart';
import 'library_format.dart';
import 'library_header.dart';
import 'new_notebook_tile.dart';
import 'notebook_card.dart';
import 'notebook_list_tile.dart';
import 'thumbnails/thumbnail_renderer.dart';

/// The scrolling main area of the library: header, folders, notebooks.
class LibraryContent extends StatelessWidget {
  const LibraryContent({
    super.key,
    required this.actions,
    required this.searchController,
    required this.searchFocus,
    this.headerLeading,
  });

  final LibraryActions actions;
  final TextEditingController searchController;
  final FocusNode searchFocus;

  /// Before the title (phone: the drawer button).
  final Widget? headerLeading;

  /// Whether the grid starts with a "New…" tile: on wide screens, in the
  /// library's grid. Elsewhere the "New" button floats instead (one primary
  /// action per screen).
  static bool showsNewTile(LibraryActions actions, {required bool compact}) {
    final c = actions.controller;
    return !compact &&
        c.layout == LibraryLayout.grid &&
        c.section == LibrarySection.library &&
        !c.isSearching &&
        !actions.selection.active;
  }

  LibraryController get _c => actions.controller;

  /// About how wide notebook covers are in the grid (REDESIGN §3).
  static const double coverWidth = 150;

  /// Folders as a wrapping row of compact tiles of equal width.
  Widget _folderRow(List<Folder> folders) => LayoutBuilder(
    builder: (context, constraints) {
      const spacing = Gaps.md;
      final width = constraints.maxWidth;
      double tileFor(int columns) => (width - spacing * (columns - 1)) / columns;
      var columns = math.max(2, ((width + spacing) / (FolderTile.width + spacing)).floor());
      // Large text on a phone: fewer, wider tiles rather than cut-off names.
      final minTile = FolderTile.minWidth * MediaQuery.textScalerOf(context).scale(1);
      while (columns > 1 && tileFor(columns) < minTile) {
        columns--;
      }
      final tile = tileFor(columns);
      return Wrap(
        spacing: spacing,
        runSpacing: spacing,
        children: [
          for (final f in folders)
            SizedBox(
              width: tile,
              child: FolderTile(
                key: ValueKey('folder-${f.id}'),
                folder: f,
                subtitle: _folderCaption(f),
                actions: actions,
              ),
            ),
        ],
      );
    },
  );

  String _folderCaption(Folder f) {
    final n = _c.itemCountIn(f.id);
    return n == 0 ? 'Empty' : '$n ${n == 1 ? 'item' : 'items'}';
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < Breakpoints.medium;
    final gutter = compact ? Gaps.lg + Gaps.xs : Gaps.xxl;
    final folders = _c.visibleFolders;
    final notebooks = _c.visibleNotebooks;
    final empty = folders.isEmpty && notebooks.isEmpty;
    // Searching the library also lists matches inside notebooks.
    final fullText = _c.isSearching && _c.section == LibrarySection.library;
    final newTile = showsNewTile(actions, compact: compact);
    // Room after the last row: clear of the phone's ⊕ and of a snack bar
    // above it (an Undo after trashing the last card), or of a snack bar.
    final endRoom = compact ? 160.0 : 120.0;
    return CustomScrollView(
      key: PageStorageKey('library-${_c.section.name}-${_c.folderId}'),
      // Builds half a screen ahead, so covers render before they scroll in.
      scrollCacheExtent: const ScrollCacheExtent.viewport(0.5),
      slivers: [
        SliverSafeArea(
          bottom: false,
          sliver: SliverPadding(
            padding: EdgeInsets.fromLTRB(
              compact ? Gaps.sm : gutter,
              compact ? Gaps.sm : Gaps.xl,
              compact ? Gaps.sm : gutter,
              Gaps.sm,
            ),
            sliver: SliverToBoxAdapter(
              child: LibraryHeader(
                actions: actions,
                searchController: searchController,
                searchFocus: searchFocus,
                compact: compact,
                leading: headerLeading,
              ),
            ),
          ),
        ),
        if (empty && !fullText)
          SliverFillRemaining(
            hasScrollBody: false,
            child: LibraryEmptyState(
              section: _c.section,
              inFolder: _c.folderId != null,
              query: _c.query,
              onCreate: () => unawaited(actions.createNotebook(context)),
              onClearSearch: () {
                searchController.clear();
                _c.query = '';
              },
              onImportPdf: () => unawaited(actions.importPdf(context)),
              onSetUpSync: _c.services.sync.isConfigured
                  ? null
                  : () => unawaited(
                      Navigator.of(context)
                          .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen())),
                    ),
            ),
          )
        else ...[
          if (folders.isNotEmpty)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(gutter, Gaps.md, gutter, 0),
              sliver: SliverToBoxAdapter(child: _folderRow(folders)),
            ),
          if (notebooks.isNotEmpty || newTile) ...[
            SliverToBoxAdapter(child: SizedBox(height: folders.isEmpty ? Gaps.lg : Gaps.xl)),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(gutter, 0, gutter, fullText ? 0 : endRoom),
              sliver: _c.layout == LibraryLayout.grid
                  ? _grid(context, notebooks, compact, newTile: newTile)
                  : _list(notebooks),
            ),
          ] else if (!fullText)
            SliverToBoxAdapter(child: SizedBox(height: endRoom)),
          // Full-text matches in text boxes and PDF pages.
          if (fullText)
            LibrarySearchResults(
              query: _c.query.trim(),
              padding: EdgeInsets.symmetric(horizontal: gutter),
              onOpen: (context, notebook, hit) => unawaited(
                openSearchResult(
                  context,
                  notebook,
                  hit,
                  query: _c.query,
                  open: actions.openNotebook,
                ),
              ),
              whenEmpty: empty
                  ? LibraryEmptyState(
                      section: _c.section,
                      inFolder: _c.folderId != null,
                      query: _c.query,
                      onCreate: () => unawaited(actions.createNotebook(context)),
                      onClearSearch: () {
                        searchController.clear();
                        _c.query = '';
                      },
                    )
                  : null,
            ),
          // Keeps the last result clear of the FAB.
          if (fullText) SliverToBoxAdapter(child: SizedBox(height: endRoom)),
        ],
      ],
    );
  }

  String _subtitle(Notebook n) {
    if (n.isTrashed) return trashLeftLabel(n.trashedAt!, NotebookRepository.trashKeptFor);
    if (_c.isSearching) return _c.locationOf(n);
    final kind = n.kind == NotebookKind.canvas ? 'Canvas' : pageCountLabel(_c.pageCountOf(n.id));
    final date = _c.sort == LibrarySort.created
        ? libraryDateAfter('Created', n.createdAt)
        : formatLibraryDate(n.editedAt);
    return '$date · $kind';
  }

  Widget _grid(
    BuildContext context,
    List<Notebook> notebooks,
    bool compact, {
    required bool newTile,
  }) {
    final offset = newTile ? 1 : 0;
    return SliverGrid.builder(
      // Columns from the width in the delegate, not a layout builder: a
      // builder above the grid would rebuild every card on every scroll frame.
      gridDelegate: CoverGridDelegate(
        coverWidth: coverWidth,
        spacing: compact ? Gaps.lg : Gaps.xl,
        captionHeight: NotebookCard.captionHeight(MediaQuery.textScalerOf(context)),
      ),
      itemCount: notebooks.length + offset,
      itemBuilder: (context, i) {
        if (i < offset) {
          return NewNotebookTile(
            key: const ValueKey('new-notebook-tile'),
            onPressed: () => unawaited(actions.createNotebook(context)),
          );
        }
        final notebook = notebooks[i - offset];
        return NotebookCard(
          key: ValueKey(notebook.id),
          notebook: notebook,
          subtitle: _subtitle(notebook),
          actions: actions,
        );
      },
    );
  }

  Widget _list(List<Notebook> notebooks) {
    return SliverList.separated(
      itemCount: notebooks.length,
      separatorBuilder: (_, _) => const SizedBox(height: Gaps.xxs),
      itemBuilder: (context, i) => NotebookListTile(
        key: ValueKey(notebooks[i].id),
        notebook: notebooks[i],
        subtitle: _subtitle(notebooks[i]),
        actions: actions,
      ),
    );
  }
}

/// The notebook grid's layout: covers of about [coverWidth] (at least two
/// columns, stretched to the width) at [ThumbnailRenderer.aspect], with
/// [captionHeight] below each for the title and caption.
class CoverGridDelegate extends SliverGridDelegate {
  const CoverGridDelegate({
    required this.coverWidth,
    required this.spacing,
    required this.captionHeight,
  });

  final double coverWidth;
  final double spacing;
  final double captionHeight;

  @override
  SliverGridLayout getLayout(SliverConstraints constraints) {
    final width = constraints.crossAxisExtent;
    final columns = math.max(2, ((width + spacing) / (coverWidth + spacing)).floor());
    final tile = (width - spacing * (columns - 1)) / columns;
    final height = tile / ThumbnailRenderer.aspect + captionHeight;
    return SliverGridRegularTileLayout(
      crossAxisCount: columns,
      mainAxisStride: height + Gaps.lg,
      crossAxisStride: tile + spacing,
      childMainAxisExtent: height,
      childCrossAxisExtent: tile,
      reverseCrossAxis: axisDirectionIsReversed(constraints.crossAxisDirection),
    );
  }

  @override
  bool shouldRelayout(CoverGridDelegate old) =>
      old.coverWidth != coverWidth || old.spacing != spacing || old.captionHeight != captionHeight;
}
