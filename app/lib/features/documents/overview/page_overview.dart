import 'package:flutter/material.dart';

import '../../../data/surface_copier.dart';
import '../../../domain/notebook_page.dart';
import '../../../ink/images/element_images.dart';
import '../../../ui/app_theme.dart';
import '../../editor/document/page_backgrounds.dart';
import '../../editor/document/page_thumbnail.dart';
import 'overview_parts.dart';
import 'page_commands.dart';
import 'page_tile.dart';

export 'overview_parts.dart' show OverviewFilter;
export 'page_commands.dart';

/// Grid of live page thumbnails: go to, reorder (long-press and drag),
/// insert, duplicate, delete, bookmark, and a selection mode for acting on
/// several pages at once. Pops with the index of the page to show, if any.
class PageOverview extends StatefulWidget {
  const PageOverview({
    super.key,
    required this.handlers,
    required this.copier,
    required this.currentPage,
    this.backgrounds,
    this.images,
    this.changes,
    this.outline,
    this.initialFilter = OverviewFilter.all,
  });

  final OverviewHandlers handlers;
  final SurfaceCopier copier;
  final int currentPage;
  final PageBackgrounds? backgrounds;

  /// Decoded bitmaps for image elements.
  final ElementImages? images;

  /// Notifies when pages change elsewhere (e.g. "Undo" in a snack bar, or
  /// a sync); the overview then reloads.
  final Listenable? changes;

  /// Builds the Outline filter's view; [goTo] shows a page (closing the
  /// overview). Null: no Outline filter.
  final Widget Function(BuildContext context, ValueChanged<int> goTo)? outline;

  /// The filter shown first.
  final OverviewFilter initialFilter;

  @override
  State<PageOverview> createState() => _PageOverviewState();
}

class _PageOverviewState extends State<PageOverview> {
  late final ThumbnailCache _cache = ThumbnailCache(widget.copier, images: widget.images);
  late List<NotebookPage> _pages = widget.handlers.load();
  late OverviewFilter _filter =
      widget.outline == null && widget.initialFilter == OverviewFilter.outline
      ? OverviewFilter.all
      : widget.initialFilter;

  bool get _bookmarksOnly => _filter == OverviewFilter.bookmarked;

  /// Ids of selected pages; null outside selection mode.
  Set<String>? _selection;

  bool get _selecting => _selection != null;

  @override
  void initState() {
    super.initState();
    widget.changes?.addListener(_reload);
  }

  @override
  void dispose() {
    widget.changes?.removeListener(_reload);
    _cache.dispose();
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _pages = widget.handlers.load();
      final ids = {for (final p in _pages) p.id};
      _selection?.removeWhere((id) => !ids.contains(id));
    });
  }

  Future<void> _run(PageCommand command, NotebookPage page) async {
    await widget.handlers.command(context, command, page);
    if (mounted) _reload();
  }

  void _move(NotebookPage page, int toIndex) {
    widget.handlers.move(page, toIndex);
    _reload();
  }

  void _toggle(NotebookPage page) => setState(() {
    final s = _selection ??= {};
    if (!s.remove(page.id)) s.add(page.id);
  });

  /// The pages the filter shows: what "Select all" picks.
  List<NotebookPage> get _shownPages => [
    for (final p in _pages)
      if (!_bookmarksOnly || p.bookmarked) p,
  ];

  /// Changes the filter; selected pages it hides are deselected (else
  /// Delete or Export would act on pages out of sight).
  void _setFilter(OverviewFilter filter) => setState(() {
    _filter = filter;
    final shown = {for (final p in _shownPages) p.id};
    _selection?.retainWhere(shown.contains);
  });

  List<NotebookPage> get _selected => [
    for (final p in _pages)
      if (_selection?.contains(p.id) ?? false) p,
  ];

  Future<void> _runOnSelection(SelectionAction action) async {
    final pages = _selected;
    if (pages.isEmpty) return;
    switch (action) {
      case SelectionAction.bookmark:
        // Bookmark all, or clear them if all are bookmarked already.
        final clear = pages.every((p) => p.bookmarked);
        final many = widget.handlers.bookmarkMany;
        if (many != null) {
          many(pages, on: !clear);
        } else {
          for (final p in pages.where((p) => p.bookmarked == clear)) {
            await widget.handlers.command(context, PageCommand.bookmark, p);
          }
        }
      case SelectionAction.duplicate:
        if (widget.handlers.duplicateMany case final many?) {
          await many(context, pages);
        } else {
          for (final p in pages.reversed) {
            if (!mounted) return;
            await widget.handlers.command(context, PageCommand.duplicate, p);
          }
        }
      case SelectionAction.send:
        await widget.handlers.sendMany?.call(context, pages);
        if (mounted) setState(() => _selection = null);
      case SelectionAction.template:
        await widget.handlers.templateMany?.call(context, pages);
      case SelectionAction.export:
        await widget.handlers.exportMany?.call(context, pages);
      case SelectionAction.delete:
        if (pages.length >= _pages.length) {
          showOverviewMessage(context, 'A notebook needs at least one page');
          return;
        }
        final many = widget.handlers.deleteMany;
        if (many != null) {
          await many(context, pages);
        } else {
          for (final p in pages) {
            if (!mounted) return;
            await widget.handlers.command(context, PageCommand.delete, p);
          }
        }
        if (mounted) setState(() => _selection = null);
    }
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final shown = [
      for (var i = 0; i < _pages.length; i++)
        if (!_bookmarksOnly || _pages[i].bookmarked) i,
    ];
    final compact = MediaQuery.sizeOf(context).width < Breakpoints.medium;
    final addTile = !_bookmarksOnly && !_selecting && _pages.isNotEmpty;
    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _selection = null);
      },
      child: Scaffold(
        // Selecting keeps the bar (the filter still narrows the pages); the
        // selection's own bar floats at the bottom, as in the library.
        appBar: OverviewAppBar(
          pageCount: _pages.length,
          filter: _filter,
          compact: compact,
          outline: widget.outline != null,
          textScale: MediaQuery.textScalerOf(context).scale(1),
          onFilter: _setFilter,
          onSelect: _filter == OverviewFilter.outline || _selecting
              ? null
              : () => setState(() => _selection = {}),
        ),
        bottomNavigationBar: _selecting
            ? PageSelectionBar(
                count: _selection!.length,
                total: shown.length,
                onClose: () => setState(() => _selection = null),
                onSelectAll: () => setState(() {
                  final all = _selection!.length == shown.length;
                  _selection = all ? {} : {for (final p in _shownPages) p.id};
                }),
                allBookmarked: _selected.isNotEmpty && _selected.every((p) => p.bookmarked),
                offered: {
                  SelectionAction.bookmark,
                  SelectionAction.duplicate,
                  if (widget.handlers.sendMany != null) SelectionAction.send,
                  if (widget.handlers.templateMany != null) SelectionAction.template,
                  if (widget.handlers.exportMany != null) SelectionAction.export,
                  SelectionAction.delete,
                },
                onAction: _runOnSelection,
              )
            : null,
        body: _filter == OverviewFilter.outline
            // A readable column under the filter, its text on the filter's
            // margin (the outline's own margin is Gaps.lg).
            ? Align(
                alignment: AlignmentDirectional.topStart,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
                  child: Padding(
                    padding: EdgeInsetsDirectional.only(start: compact ? 0 : Gaps.xxl - Gaps.lg),
                    child: widget.outline!(context, (page) => Navigator.of(context).pop(page)),
                  ),
                ),
              )
            : shown.isEmpty
            ? const NoBookmarks()
            : GridView.builder(
                padding: EdgeInsets.fromLTRB(
                  compact ? Gaps.lg : Gaps.xxl,
                  Gaps.lg,
                  compact ? Gaps.lg : Gaps.xxl,
                  Gaps.xxl + MediaQuery.paddingOf(context).bottom,
                ),
                gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
                  maxCrossAxisExtent: compact ? 180 : 200,
                  mainAxisSpacing: Gaps.lg,
                  crossAxisSpacing: compact ? Gaps.lg : Gaps.xl,
                  childAspectRatio: 0.62,
                ),
                itemCount: shown.length + (addTile ? 1 : 0),
                itemBuilder: (context, i) {
                  if (i == shown.length) {
                    return AddPageTile(
                      onTap: () => _run(PageCommand.insertAfter, _pages.last),
                      onLongPress: () => _run(PageCommand.insertWithTemplate, _pages.last),
                    );
                  }
                  final index = shown[i];
                  final page = _pages[index];
                  return PageTile(
                    key: ValueKey('page-tile-$index'),
                    index: index,
                    page: page,
                    cache: _cache,
                    backgrounds: widget.backgrounds,
                    current: index == widget.currentPage,
                    reorderable: !_bookmarksOnly,
                    selecting: _selecting,
                    selected: _selection?.contains(page.id) ?? false,
                    onTap: () => _selecting ? _toggle(page) : Navigator.of(context).pop(index),
                    onLongPress: () => _toggle(page),
                    onCommand: (c) => _run(c, page),
                    onDrop: (from) => _move(_pages[from], index),
                  );
                },
              ),
      ),
    );
  }
}
