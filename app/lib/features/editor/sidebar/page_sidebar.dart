import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../app_services.dart';
import '../../../data/surface_copier.dart';
import '../../../domain/notebook_page.dart';
import '../../../domain/pdf_page_numbers.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/fast_scroll.dart';
import '../../../ui/menus.dart';
import '../../documents/overview/page_commands.dart';
import '../../documents/overview/page_moves.dart';
import '../chrome/bar_button.dart';
import '../document/document_commands.dart';
import '../document/document_controller.dart';
import '../document/page_backgrounds.dart';
import '../document/page_thumbnail.dart';
import 'sidebar_add_page.dart';
import 'sidebar_metrics.dart';
import 'sidebar_tile.dart';
import 'thumbnail_refresh.dart';

export 'sidebar_metrics.dart';

part 'page_sidebar_input.dart';

/// The pages of a paged notebook in a slim column beside the page (wide
/// panes only, [SidebarMetrics.fits]): live thumbnails, the page on screen
/// marked and kept in view, tap to go, drag to reorder (one undo step),
/// right-click or hold for the page menu, Add page at the end. With the
/// keyboard: one Tab stop, ↑ ↓ Home End between pages, Enter to go,
/// Ctrl+arrows to move a page, the Menu key for its menu.
///
/// Scrolling the page costs it nothing: it hears only when the page on
/// screen changes, and then only the two numbers concerned rebuild.
class PageSidebar extends StatefulWidget {
  const PageSidebar({
    super.key,
    required this.doc,
    required this.commands,
    required this.services,
    required this.onClose,
    this.backgrounds,
    this.padding = EdgeInsets.zero,
  });

  final DocumentController doc;
  final DocumentCommands commands;
  final AppServices services;
  final PageBackgrounds? backgrounds;

  /// Hides the sidebar.
  final VoidCallback onClose;

  /// System insets the column keeps clear of (a notch at its side, the
  /// gesture bar below).
  final EdgeInsets padding;

  @override
  State<PageSidebar> createState() => _PageSidebarState();
}

class _PageSidebarState extends State<PageSidebar> {
  final ScrollController _scroll = ScrollController();

  /// Thumbnails wait while the column scrolls fast.
  late final FastScroll _fast = FastScroll(_scroll);
  late final ThumbnailCache _cache = ThumbnailCache(
    SurfaceCopier(widget.services.strokes, elements: widget.services.elements),
    images: widget.services.images,
    defer: _fast,
  );
  late final ThumbnailRefresh _refresh = ThumbnailRefresh(
    cache: _cache,
    models: widget.doc.surfaces.models,
    remote: widget.services.sync.remoteChanges,
  );

  late List<NotebookPage> _pages = widget.doc.pages;
  late PdfPageNumbers _numbers = PdfPageNumbers(_pages);

  /// The page on screen; tiles listen to it themselves.
  late final ValueNotifier<int> _current = ValueNotifier(widget.doc.currentPage);

  /// Each tile's focus, by page id (focus follows a page that moves).
  final Map<String, FocusNode> _focus = {};

  /// The page a pointer pressed, until it lifts: a press held until the
  /// drag began and let go where it was opens the page menu.
  ({int pointer, Offset at, int index, bool moved, bool dragged})? _press;

  /// A page is being dragged: the column does not follow the page.
  bool _dragging = false;

  /// The tiles' tops (and the end of the last), for number rows
  /// [_laidOutLabel] high.
  List<double> _tops = const [];
  double? _laidOutLabel;

  @override
  void initState() {
    super.initState();
    widget.doc.addListener(_onDoc);
    _refresh; // Starts following edits.
    WidgetsBinding.instance.addPostFrameCallback((_) => _follow(_current.value, animate: false));
  }

  @override
  void dispose() {
    widget.doc.removeListener(_onDoc);
    _refresh.dispose();
    _cache.dispose();
    _fast.dispose();
    _scroll.dispose();
    _current.dispose();
    for (final node in _focus.values) {
      node.dispose();
    }
    super.dispose();
  }

  /// The document notifies when its page on screen, its active page or its
  /// pages change: only the last rebuilds the column.
  void _onDoc() {
    if (!identical(widget.doc.pages, _pages)) {
      setState(() {
        _pages = widget.doc.pages;
        _numbers = PdfPageNumbers(_pages);
        _laidOutLabel = null;
        final ids = {for (final p in _pages) p.id};
        _focus.removeWhere((id, node) {
          if (ids.contains(id)) return false;
          node.dispose();
          return true;
        });
      });
    }
    final current = widget.doc.currentPage;
    if (current == _current.value) return;
    _current.value = current;
    _updateStop();
    if (!_dragging) _follow(current);
  }

  FocusNode _focusOf(NotebookPage page) =>
      _focus[page.id] ??= FocusNode(debugLabel: 'sidebar page ${page.id}');

  /// The tiles' tops for a number row [label] high.
  void _layOut(double label) {
    if (_laidOutLabel == label && _tops.length == _pages.length + 1) return;
    _laidOutLabel = label;
    final tops = List<double>.filled(_pages.length + 1, 0);
    var top = 0.0;
    for (var i = 0; i < _pages.length; i++) {
      tops[i] = top;
      top += SidebarMetrics.extent(_pages[i], label);
    }
    tops[_pages.length] = top;
    _tops = tops;
  }

  /// Scrolls the column so that page [index] is in view (a little room
  /// around it), unless it is.
  void _follow(int index, {bool animate = true}) {
    if (!mounted || !_scroll.hasClients || index < 0 || index >= _pages.length) return;
    _layOut(SidebarMetrics.labelHeight(context));
    final position = _scroll.position;
    final top = _tops[index];
    final bottom = _tops[index + 1] + SidebarMetrics.gap;
    final view = position.viewportDimension;
    final pixels = position.pixels;
    if (top >= pixels && bottom <= pixels + view) return;
    final target = (top < pixels ? top : bottom - view).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    // Far away (a jump across the notebook): no glide through every page.
    if (!animate || (target - pixels).abs() > 3 * view) {
      _scroll.jumpTo(target);
    } else {
      unawaited(
        _scroll.animateTo(
          target,
          duration: Motion.moving(context, Motion.medium),
          curve: Motion.emphasized,
        ),
      );
    }
  }

  void _go(int index) => widget.doc.goToPage(index);

  Future<void> _run(PageCommand command, NotebookPage page) =>
      widget.commands.run(context, command, page);

  /// The page menu of page [index], at [at] (global) or over its tile.
  Future<void> _menu(int index, Offset? at) async {
    if (index < 0 || index >= _pages.length) return;
    final page = _pages[index];
    final node = _focus[page.id];
    final anchor = node?.context ?? context;
    final command = await showContextMenuAt<PageCommand>(
      anchor,
      items: pageMenuItems(page),
      at: at,
    );
    if (command != null && mounted) await _run(command, page);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final label = SidebarMetrics.labelHeight(context);
    _layOut(label);
    return RepaintBoundary(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Surfaces.chrome(scheme),
          border: BorderDirectional(end: Surfaces.chromeEdge(scheme)),
        ),
        child: Padding(
          padding: EdgeInsets.only(left: widget.padding.left, right: widget.padding.right),
          child: Column(
            children: [
              _Header(count: _pages.length, rtl: rtl, onClose: widget.onClose),
              Expanded(
                child: Focus(
                  canRequestFocus: false,
                  skipTraversal: true,
                  onKeyEvent: _onKey,
                  child: _list(label),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _list(double label) => ReorderableListView.builder(
    scrollController: _scroll,
    buildDefaultDragHandles: false,
    itemCount: _pages.length,
    itemExtentBuilder: (index, _) =>
        index < _pages.length ? SidebarMetrics.extent(_pages[index], label) : null,
    padding: EdgeInsets.zero,
    proxyDecorator: (child, index, animation) => SidebarLifted(
      child: Material(type: MaterialType.transparency, child: child),
    ),
    onReorderStart: _dragStarted,
    onReorderEnd: (_) => _dragging = false,
    onReorderItem: _dropped,
    footer: SidebarAddPage(
      bottom: widget.padding.bottom,
      onTap: () => unawaited(_run(PageCommand.insertAfter, _pages.last)),
      onLongPress: () => unawaited(_run(PageCommand.insertWithTemplate, _pages.last)),
    ),
    itemBuilder: _tile,
  );

  Widget _tile(BuildContext context, int index) {
    final page = _pages[index];
    return Listener(
      key: ValueKey(page.id),
      onPointerDown: (e) => _pointerDown(context, index, e),
      onPointerMove: _pointerMove,
      onPointerUp: _pointerUp,
      onPointerCancel: (_) => _press = null,
      child: SidebarTile(
        index: index,
        page: page,
        pdfLabel: _numbers.labelOf(index),
        current: _current,
        cache: _cache,
        backgrounds: widget.backgrounds,
        thumbHeight: SidebarMetrics.thumbHeight(page),
        focusNode: _focusOf(page)..skipTraversal = page.id != _stop,
        onTap: () => _go(index),
        onMenu: (at) => unawaited(_menu(index, at)),
        onMove: (direction) => _step(page, direction),
      ),
    );
  }
}

/// The column's head: how many pages, and the way to hide it.
class _Header extends StatelessWidget {
  const _Header({required this.count, required this.rtl, required this.onClose});

  final int count;
  final bool rtl;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      height: Targets.barHit(context),
      child: Row(
        children: [
          const SizedBox(width: SidebarMetrics.side + Gaps.sm),
          Expanded(
            child: Text(
              count == 1 ? '1 page' : '$count pages',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(fontFeatures: AppTheme.tabularFigures),
            ),
          ),
          BarButton(
            icon: rtl ? Symbols.right_panel_close_sharp : Symbols.left_panel_close_sharp,
            tooltip: Targets.touchFirst ? 'Hide pages' : 'Hide pages (F4)',
            onPressed: onClose,
          ),
          const SizedBox(width: Gaps.xs),
        ],
      ),
    );
  }
}
