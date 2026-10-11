import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../domain/notebook.dart';
import '../../domain/preferences.dart';
import '../../ui/app_theme.dart';
import '../../ui/section_label.dart';
import '../search/library_search_results.dart';
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
    this.headerTrailing = const [],
  });

  final LibraryActions actions;
  final TextEditingController searchController;
  final FocusNode searchFocus;
  final List<Widget> headerTrailing;

  LibraryController get _c => actions.controller;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < Breakpoints.medium;
    final gutter = compact
        ? Gaps.lg + 4
        : (width >= Breakpoints.expanded ? Gaps.xxl + 8 : Gaps.xxl);
    final folders = _c.visibleFolders;
    final notebooks = _c.visibleNotebooks;
    final empty = folders.isEmpty && notebooks.isEmpty;
    // Searching the library also lists matches inside notebooks.
    final fullText = _c.isSearching && _c.section == LibrarySection.library;
    // The grid starts with a "New…" tile where notebooks are created.
    final newTile =
        _c.layout == LibraryLayout.grid &&
        _c.section == LibrarySection.library &&
        !_c.isSearching &&
        !actions.selection.active;
    Widget label(String text) => SliverPadding(
      padding: EdgeInsets.fromLTRB(gutter + Gaps.xxs, Gaps.xl, gutter, Gaps.md),
      sliver: SliverToBoxAdapter(child: SectionLabel(text)),
    );

    return CustomScrollView(
      key: PageStorageKey('library-${_c.section.name}-${_c.folderId}'),
      slivers: [
        SliverSafeArea(
          bottom: false,
          sliver: SliverPadding(
            padding: EdgeInsets.fromLTRB(gutter, compact ? Gaps.lg : Gaps.xxl, gutter, Gaps.sm),
            sliver: SliverToBoxAdapter(
              child: LibraryHeader(
                actions: actions,
                searchController: searchController,
                searchFocus: searchFocus,
                compact: compact,
                trailing: headerTrailing,
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
            ),
          )
        else ...[
          if (folders.isNotEmpty) ...[
            label('Folders'),
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: gutter),
              sliver: SliverGrid.builder(
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: 300,
                  // Two lines of text grow with the text scale.
                  mainAxisExtent: 28 + MediaQuery.textScalerOf(context).scale(38),
                  mainAxisSpacing: Gaps.md,
                  crossAxisSpacing: Gaps.md,
                ),
                itemCount: folders.length,
                itemBuilder: (context, i) {
                  final f = folders[i];
                  final n = _c.itemCountIn(f.id);
                  return FolderTile(
                    key: ValueKey('folder-${f.id}'),
                    folder: f,
                    subtitle: n == 0 ? 'Empty' : '$n ${n == 1 ? 'item' : 'items'}',
                    actions: actions,
                  );
                },
              ),
            ),
          ],
          if (notebooks.isNotEmpty || newTile) ...[
            if (folders.isNotEmpty)
              label('Notebooks')
            else
              const SliverToBoxAdapter(child: SizedBox(height: Gaps.lg)),
            SliverPadding(
              // Bottom padding keeps the last row clear of the FAB.
              padding: EdgeInsets.fromLTRB(gutter, 0, gutter, fullText ? 0 : 120),
              sliver: _c.layout == LibraryLayout.grid
                  ? _grid(context, notebooks, compact, newTile: newTile)
                  : _list(notebooks),
            ),
          ] else if (!fullText)
            const SliverToBoxAdapter(child: SizedBox(height: 120)),
          // Full-text matches in text boxes and PDF pages.
          if (fullText)
            LibrarySearchResults(
              query: _c.query,
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
                    )
                  : null,
            ),
          // Keeps the last result clear of the FAB.
          if (fullText) const SliverToBoxAdapter(child: SizedBox(height: 120)),
        ],
      ],
    );
  }

  String _subtitle(Notebook n) {
    if (n.isTrashed) return libraryDateAfter('Deleted', n.trashedAt!);
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
    final maxTile = compact ? 172.0 : 184.0;
    final spacing = compact ? Gaps.lg : Gaps.xl + 4;
    return SliverLayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.crossAxisExtent;
        final columns = math.max(2, ((width + spacing) / (maxTile + spacing)).ceil());
        final tile = (width - spacing * (columns - 1)) / columns;
        return SliverGrid.builder(
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            crossAxisSpacing: spacing,
            mainAxisSpacing: spacing + Gaps.xs,
            mainAxisExtent:
                tile / ThumbnailRenderer.aspect + 18 + MediaQuery.textScalerOf(context).scale(36),
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
