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

  @override
  State<PageOverview> createState() => _PageOverviewState();
}

class _PageOverviewState extends State<PageOverview> {
  late final ThumbnailCache _cache = ThumbnailCache(widget.copier, images: widget.images);
  late List<NotebookPage> _pages = widget.handlers.load();
  bool _bookmarksOnly = false;

  /// The page tag filtered by (id), if any.
  String? _tag;
  late var _pageTags = widget.handlers.pageTags?.call() ?? const [];

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
      _pageTags = widget.handlers.pageTags?.call() ?? const [];
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
        for (final p in pages.where((p) => p.bookmarked == clear)) {
          await widget.handlers.command(context, PageCommand.bookmark, p);
        }
      case SelectionAction.duplicate:
        for (final p in pages.reversed) {
          if (!mounted) return;
          await widget.handlers.command(context, PageCommand.duplicate, p);
        }
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
        setState(() => _selection = null);
    }
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    final tagged = _pageTags.where((t) => t.tag.id == _tag).firstOrNull;
    if (tagged == null) _tag = null;
    final shown = [
      for (var i = 0; i < _pages.length; i++)
        if ((!_bookmarksOnly || _pages[i].bookmarked) &&
            (tagged == null || tagged.pages.contains(_pages[i].id)))
          i,
    ];
    final compact = MediaQuery.sizeOf(context).width < Breakpoints.medium;
    final addTile = !_bookmarksOnly && _tag == null && !_selecting && _pages.isNotEmpty;
    return PopScope(
      canPop: !_selecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) setState(() => _selection = null);
      },
      child: Scaffold(
        appBar: _selecting
            ? SelectionAppBar(
                count: _selection!.length,
                total: _pages.length,
                onClose: () => setState(() => _selection = null),
                onSelectAll: () => setState(() {
                  final all = _selection!.length == _pages.length;
                  _selection = all ? {} : {for (final p in _pages) p.id};
                }),
              )
            : OverviewAppBar(
                pageCount: _pages.length,
                bookmarksOnly: _bookmarksOnly,
                compact: compact,
                onBookmarksOnly: (v) => setState(() => _bookmarksOnly = v),
                onSelect: () => setState(() => _selection = {}),
                tags: [for (final t in _pageTags) t.tag],
                tag: _tag,
                onTag: (id) => setState(() => _tag = id),
              ),
        bottomNavigationBar: _selecting
            ? SelectionBar(count: _selection!.length, onAction: _runOnSelection)
            : null,
        body: shown.isEmpty
            ? NoBookmarks(tag: tagged?.tag.name)
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
                    return AddPageTile(onTap: () => _run(PageCommand.insertAfter, _pages.last));
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
                    reorderable: !_bookmarksOnly && _tag == null,
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
