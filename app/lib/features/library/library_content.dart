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
import 'library_search_field.dart';
import 'new_notebook_tile.dart';
import 'notebook_card.dart';
import 'notebook_list_tile.dart';
import 'recent_row.dart';

part 'library_content_items.dart';

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
  final LibrarySearchFocus searchFocus;

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

  /// The library's left and right margin: covers, rows, the header and
  /// the notices above them share these edges.
  static double gutterFor({required bool compact}) => compact ? Gaps.lg + Gaps.xs : Gaps.xxl;

  @override
  State<LibraryContent> createState() => _LibraryContentState();
}

class _LibraryContentState extends State<LibraryContent> {
  LibraryActions get actions => widget.actions;
  TextEditingController get searchController => widget.searchController;
  LibrarySearchFocus get searchFocus => widget.searchFocus;
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
    final gutter = LibraryContent.gutterFor(compact: compact);
    final gridSpacing = LibraryContent.gridSpacingFor(compact: compact);
    final folders = _c.visibleFolders;
    final notebooks = _c.visibleNotebooks;
    final empty = folders.isEmpty && notebooks.isEmpty;
    // Short windows have no room for the Recent row: Recent leads the strip.
    final recent = actions.selection.active ? const <Notebook>[] : _c.recentNotebooks;
    final strip = short && folders.isNotEmpty
        ? FolderRow.strip(folders: folders, actions: actions, recent: recent)
        : null;
    final inlineFolders = strip != null && !_c.isSearching;
    // Phones under the Recent row: the folders take one line that scrolls
    // sideways too, so the first covers stay above the fold (R8-7).
    final folderStrip = compact && recent.isNotEmpty;
    final rule = Theme.of(context).colorScheme.outlineVariant;
    // Searching the library also lists matches inside notebooks.
    final fullText = _c.isSearching && _c.section == LibrarySection.library;
    final newTile = LibraryContent.showsNewTile(actions, compact: compact);
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
                      Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => const SettingsScreen(showSync: true),
                        ),
                      ),
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
            if (recent.isNotEmpty && !short)
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
            if (folders.isNotEmpty && folderStrip)
              SliverPadding(
                padding: EdgeInsets.fromLTRB(gutter, Gaps.sm, gutter, 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      FolderRow.strip(folders: folders, actions: actions),
                      const SizedBox(height: Gaps.sm),
                      Divider(height: Hairline.width, color: rule),
                    ],
                  ),
                ),
              )
            else if (folders.isNotEmpty)
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
}
