part of 'page_overview.dart';

/// The overview grid's tiles, Bookmarked's empty view, and moving a page
/// with Ctrl+arrows.
extension _OverviewTiles on _PageOverviewState {
  /// Tile [i] of the grid: a page of [shown] or, past them, "Add page".
  Widget _tile(List<int> shown, PdfPageNumbers numbers, int i, int columns) {
    if (i == shown.length) {
      return AddPageTile(
        pageAspect: commonPageAspect(_pages),
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
      pdfLabel: numbers.labelOf(index),
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
      focusNode: _focusOf(page),
      onMove: _bookmarksOnly || _selecting ? null : (direction) => _step(page, direction, columns),
    );
  }

  /// Bookmarked's empty view, offering the page on screen.
  Widget _noBookmarks() {
    final current = widget.currentPage;
    if (current < 0 || current >= _pages.length) return const NoBookmarks();
    return NoBookmarks(
      page: current,
      onBookmark: () => unawaited(_run(PageCommand.bookmark, _pages[current])),
    );
  }

  /// Moves [page] a step toward [direction] in a grid of [columns]
  /// (Ctrl+arrows), says where it went and keeps it focused and in view.
  void _step(NotebookPage page, AxisDirection direction, int columns) {
    final from = _pages.indexWhere((p) => p.id == page.id);
    if (from == -1) return;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final to = pageStep(from, direction, columns: columns, count: _pages.length, rtl: rtl);
    if (to == from) return;
    _move(page, to);
    announcePageMove(context, from, to);
    final node = _focusOf(page);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      node.requestFocus();
      if (node.context case final context?) {
        Scrollable.ensureVisible(
          context,
          duration: Motion.moving(context, Motion.fast),
          alignmentPolicy: to > from
              ? ScrollPositionAlignmentPolicy.keepVisibleAtEnd
              : ScrollPositionAlignmentPolicy.keepVisibleAtStart,
        );
      }
    });
  }
}
