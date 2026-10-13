import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../../data/notebook_repository.dart';
import '../../domain/notebook.dart';
import '../../domain/preferences.dart';
import '../../ui/app_theme.dart';
import '../../ui/section_label.dart';
import '../search/library_search_results.dart';
import '../settings/settings_screen.dart';
import 'cover_grid.dart';
import 'folder_row.dart';
import 'library_actions.dart';
import 'library_controller.dart';
import 'library_empty_state.dart';
import 'library_format.dart';
import 'library_header.dart';
import 'new_notebook_tile.dart';
import 'notebook_card.dart';
import 'notebook_list_tile.dart';
import 'recent_row.dart';

/// The scrolling main area of the library: header, folders, notebooks.
class LibraryContent extends StatefulWidget {
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

  /// About how wide notebook covers are in the grid (REDESIGN §3).
  static const double coverWidth = 150;

  /// The gap between the grid's columns (the folder row shares them).
  static double gridSpacingFor({required bool compact}) => compact ? Gaps.lg : Gaps.xl;

  @override
  State<LibraryContent> createState() => _LibraryContentState();
}

class _LibraryContentState extends State<LibraryContent> {
  LibraryActions get actions => widget.actions;
  TextEditingController get searchController => widget.searchController;
  FocusNode get searchFocus => widget.searchFocus;
  Widget? get headerLeading => widget.headerLeading;
  LibraryController get _c => actions.controller;

  /// The cards and rows last built, with what they showed:
  /// one whose notebook, caption and selection are unchanged is used again
  /// as it is, so a sort, a selection or a move rebuilds only the cards
  /// that changed.
  final _kept = <String, ({Widget item, Object? shown})>{};

  /// The item [id] (a notebook's card or row) showing [shown] (compared with ==; records
  /// of what it shows), from [_kept] if it showed the same.
  Widget _keep(String id, Object? shown, Widget Function() build) {
    final kept = _kept[id];
    if (kept != null && kept.shown == shown) return kept.item;
    final item = build();
    _kept[id] = (item: item, shown: shown);
    return item;
  }

  // The viewport's height sizes covers in short windows; the grid reads it
  // from its sliver constraints, the folder row (on the same columns) here.
  @override
  Widget build(BuildContext context) =>
      LayoutBuilder(builder: (context, box) => _content(context, box.maxHeight));

  Widget _content(BuildContext context, double viewportHeight) {
    final compact = Breakpoints.libraryCompact(MediaQuery.sizeOf(context));
    // A phone held sideways: one row of chrome, folders beside the title
    // (or, while searching, a row of their own that scrolls sideways).
    final short = Breakpoints.short(MediaQuery.sizeOf(context));
    final gutter = compact ? Gaps.lg + Gaps.xs : Gaps.xxl;
    final gridSpacing = LibraryContent.gridSpacingFor(compact: compact);
    final folders = _c.visibleFolders;
    final notebooks = _c.visibleNotebooks;
    final empty = folders.isEmpty && notebooks.isEmpty;
    final strip = short && folders.isNotEmpty
        ? FolderRow.strip(folders: folders, actions: actions)
        : null;
    final inlineFolders = strip != null && !_c.isSearching;
    final rule = Theme.of(context).colorScheme.outlineVariant;
    // Searching the library also lists matches inside notebooks.
    final fullText = _c.isSearching && _c.section == LibrarySection.library;
    final newTile = LibraryContent.showsNewTile(actions, compact: compact);
    // Short windows have no room for it; selecting works on the grid.
    final recent = short || actions.selection.active ? const <Notebook>[] : _c.recentNotebooks;
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
              short ? Gaps.xs : (compact ? Gaps.sm : Gaps.xl),
              compact ? Gaps.sm : gutter,
              short ? Gaps.xs : Gaps.sm,
            ),
            sliver: SliverToBoxAdapter(
              child: LibraryHeader(
                actions: actions,
                searchController: searchController,
                searchFocus: searchFocus,
                compact: compact,
                short: short,
                folders: inlineFolders ? strip : null,
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
          if (inlineFolders)
            SliverPadding(
              padding: EdgeInsets.symmetric(horizontal: gutter),
              sliver: SliverToBoxAdapter(
                child: Divider(height: Hairline.width, color: rule),
              ),
            )
          else if (strip != null)
            SliverPadding(
              padding: EdgeInsets.fromLTRB(gutter, Gaps.xs, gutter, 0),
              sliver: SliverToBoxAdapter(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    strip,
                    const SizedBox(height: Gaps.xs),
                    Divider(height: Hairline.width, color: rule),
                  ],
                ),
              ),
            )
          else ...[
            if (recent.isNotEmpty)
              SliverPadding(
                padding: EdgeInsets.fromLTRB(gutter, Gaps.md, gutter, 0),
                sliver: SliverToBoxAdapter(
                  child: RecentRow(
                    notebooks: recent,
                    actions: actions,
                    coverWidth: LibraryContent.coverWidth,
                    spacing: gridSpacing,
                    viewportHeight: viewportHeight,
                  ),
                ),
              ),
            if (folders.isNotEmpty)
              SliverPadding(
                padding: EdgeInsets.fromLTRB(gutter, Gaps.md, gutter, 0),
                sliver: SliverToBoxAdapter(
                  child: FolderRow(
                    folders: folders,
                    actions: actions,
                    coverWidth: LibraryContent.coverWidth,
                    spacing: gridSpacing,
                    viewportHeight: viewportHeight,
                  ),
                ),
              ),
          ],
          if (notebooks.isNotEmpty || newTile) ...[
            SliverToBoxAdapter(
              child: SizedBox(
                height: short ? Gaps.md : (folders.isEmpty && recent.isEmpty ? Gaps.lg : Gaps.xl),
              ),
            ),
            // A search lists titles and pages alike, as rows.
            if (fullText)
              SliverPadding(
                padding: EdgeInsets.fromLTRB(gutter + Gaps.xxs, 0, gutter, Gaps.sm),
                sliver: const SliverToBoxAdapter(child: SectionLabel('Notebooks')),
              ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(gutter, 0, gutter, fullText ? 0 : endRoom),
              sliver: _c.layout == LibraryLayout.grid && !fullText
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

  /// The caption under a notebook's title; [list] rows have room to name
  /// its recordings too ("Saturday, 3 pages, 2 recordings"; cards show a
  /// mic glyph instead).
  String _subtitle(Notebook n, {bool list = false}) {
    if (n.isTrashed) return trashLeftLabel(n.trashedAt!, NotebookRepository.trashKeptFor);
    if (_c.isSearching) return _c.locationOf(n);
    final kind = n.kind == NotebookKind.canvas ? 'canvas' : pageCountLabel(_c.pageCountOf(n.id));
    final date = _c.sort == LibrarySort.created
        ? libraryDateAfter('Created', n.createdAt)
        : formatLibraryDate(n.editedAt);
    final recordings = _c.recordingCountOf(n.id);
    // Commas, not a `·` chain (DESIGN §2): "Saturday, 3 pages".
    return [
      date,
      kind,
      if (list && recordings > 0) recordings == 1 ? '1 recording' : '$recordings recordings',
    ].join(', ');
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
        coverWidth: LibraryContent.coverWidth,
        spacing: LibraryContent.gridSpacingFor(compact: compact),
        captionHeight: NotebookCard.captionHeight(MediaQuery.textScalerOf(context)),
      ),
      itemCount: notebooks.length + offset,
      findChildIndexCallback: _indexOf(notebooks, offset: offset),
      itemBuilder: (context, i) {
        if (i < offset) {
          return NewNotebookTile(
            key: const ValueKey('new-notebook-tile'),
            onPressed: () => unawaited(actions.createNotebook(context)),
          );
        }
        final notebook = notebooks[i - offset];
        final subtitle = _subtitle(notebook);
        final recordings = notebook.isTrashed ? 0 : _c.recordingCountOf(notebook.id);
        final selection = actions.selection;
        return _keep(
          'card/${notebook.id}',
          (
            notebook,
            subtitle,
            recordings,
            actions,
            selection.active,
            selection.contains(notebook.id),
          ),
          () => NotebookCard(
            key: ValueKey(notebook.id),
            notebook: notebook,
            subtitle: subtitle,
            recordings: recordings,
            actions: actions,
          ),
        );
      },
    );
  }

  /// Where the card or row keyed by a notebook's id now is: after a sort,
  /// a move or a reload, cards on screen keep their state (and cover)
  /// instead of being built anew.
  static int? Function(Key) _indexOf(List<Notebook> notebooks, {int offset = 0}) {
    Map<String, int>? index;
    return (key) {
      if (key is! ValueKey<String>) return null;
      index ??= {for (var i = 0; i < notebooks.length; i++) notebooks[i].id: i + offset};
      return index![key.value];
    };
  }

  /// The list view's widest rows: the star and ⋯ stay near the titles.
  static const double listMaxWidth = 960;

  Widget _list(List<Notebook> notebooks) {
    return SliverConstrainedCrossAxis(maxExtent: listMaxWidth, sliver: _listRows(notebooks));
  }

  Widget _listRows(List<Notebook> notebooks) {
    final indexOf = _indexOf(notebooks);
    return SliverList.separated(
      itemCount: notebooks.length,
      findItemIndexCallback: indexOf,
      // Rows are ruled like the folder row: a hairline that starts at
      // the titles.
      separatorBuilder: (context, _) => Divider(
        height: Hairline.width,
        indent: NotebookListTile.textInset,
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
      itemBuilder: (context, i) {
        final notebook = notebooks[i];
        final subtitle = _subtitle(notebook, list: true);
        final selection = actions.selection;
        return _keep(
          'row/${notebook.id}',
          (notebook, subtitle, actions, selection.active, selection.contains(notebook.id)),
          () => NotebookListTile(
            key: ValueKey(notebook.id),
            notebook: notebook,
            subtitle: subtitle,
            actions: actions,
          ),
        );
      },
    );
  }
}
