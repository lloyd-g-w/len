import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../../data/stroke_repository.dart';
import '../../../domain/notebook_page.dart';
import '../../../ink/input/ink_input_controller.dart';
import '../../../ink/surface_model.dart';
import '../../../ink/viewport.dart';
import 'document_layout.dart';
import 'document_surfaces.dart';
import 'page_viewport.dart';

/// State of an open paged notebook: its pages, their layout in document
/// space, the viewport, which page is current (shown in the indicator) and
/// which one receives input (the active page).
class DocumentController extends ChangeNotifier {
  DocumentController({
    required List<NotebookPage> pages,
    required StrokeRepository strokes,
    this._flow = PageFlow.continuous,
    int initialPage = 0,
  }) : assert(pages.isNotEmpty, 'A document needs at least one page'),
       _pages = pages,
       _current = initialPage.clamp(0, pages.length - 1),
       surfaces = DocumentSurfaces(strokes) {
    _active = _current;
    _relayout();
    viewport.addListener(_onViewport);
  }

  /// Pans and zooms the whole document.
  final ViewportController viewport = ViewportController(minScale: 0.1, maxScale: 8);

  /// The active page's view of [viewport], used by the ink engine.
  late final PageViewport pageViewport = PageViewport(viewport);

  final DocumentSurfaces surfaces;

  /// Receives the active page's model whenever it changes.
  InkInputController? input;

  List<NotebookPage> _pages;
  PageFlow _flow;
  late DocumentLayout _layout;
  int _current;
  late int _active;
  bool _framed = false;

  List<NotebookPage> get pages => _pages;
  PageFlow get flow => _flow;
  DocumentLayout get layout => _layout;

  /// The page the user is looking at.
  int get currentPage => _current;

  /// The page that receives drawing input.
  int get activePage => _active;
  NotebookPage get activePageData => _pages[_active];
  SurfaceModel get activeModel => surfaces.surfaceOf(_pages[_active].id).model;

  /// Largest zoom used when fitting a page to the screen, so pages don't
  /// become huge on wide desktop windows.
  static const double maxFitScale = 1.4;

  /// Screen padding around a fitted page.
  static const double fitPadding = 16;

  /// Extra space at the top of the screen covered by editor chrome; a
  /// page shown by [goToPage] starts below it.
  double topInset = 0;

  // ---------------------------------------------------------------------------
  // Pages

  /// Replaces the page list (after adding, deleting, reordering or a sync),
  /// keeping [keepPageId] (default: the current page) in view.
  void setPages(List<NotebookPage> pages, {String? keepPageId}) {
    if (pages.isEmpty) return;
    final keep = keepPageId ?? _pages[_current].id;
    final activeId = _pages[_active].id;
    final oldFrame = _layout.frameOf(_current);
    final screenTop = oldFrame == null ? null : viewport.toScreen(oldFrame.topLeft).dy;
    _pages = pages;
    surfaces.retain({for (final p in pages) p.id});
    final index = pages.indexWhere((p) => p.id == keep);
    _current = index == -1 ? _current.clamp(0, pages.length - 1) : index;
    final active = pages.indexWhere((p) => p.id == activeId);
    _relayout();
    _activate(active == -1 ? _current : active);
    // Keep the kept page where it was on screen, so edits elsewhere in the
    // notebook do not make the view jump.
    final frame = _layout.frameOf(_current);
    if (screenTop != null && frame != null && _framed) {
      viewport.panBy(Offset(0, screenTop - viewport.toScreen(frame.topLeft).dy));
    }
    _refreshVisible();
    notifyListeners();
  }

  void setFlow(PageFlow flow) {
    if (flow == _flow) return;
    _flow = flow;
    _relayout();
    _activate(_current);
    _frame(_current);
    _refreshVisible();
    notifyListeners();
  }

  /// Shows page [index]: scrolls to it, or turns to it in single-page flow.
  void goToPage(int index) {
    if (index < 0 || index >= _pages.length) return;
    _current = index;
    if (_flow == PageFlow.single) _relayout();
    _activate(index);
    _frame(index);
    _refreshVisible();
    _current = index; // Not whatever the probe found mid-page.
    notifyListeners();
  }

  /// Makes the page under [screen] (or nearest to it) the active page.
  void activateAt(Offset screen) {
    final world = viewport.toWorld(screen);
    final index = _layout.pageAt(world) ?? _layout.nearestPage(world);
    if (index == null || index == _active) return;
    _activate(index);
    notifyListeners();
  }

  void _activate(int index) {
    _active = index;
    pageViewport.showPage(_layout.frameOf(index) ?? _layout.frames.first);
    input?.model = activeModel;
  }

  void _relayout() {
    _layout = _flow == PageFlow.continuous
        ? DocumentLayout.continuous([for (final p in _pages) p.size])
        : DocumentLayout.single(_current, _pages[_current].size);
    viewport.contentBounds = _layout.bounds;
  }

  // ---------------------------------------------------------------------------
  // Viewport

  /// Fits page [index] to the screen width (capped) and scrolls its top
  /// into view.
  void _frame(int index) {
    final size = viewport.size;
    final frame = _layout.frameOf(index);
    if (size.isEmpty || frame == null) return;
    final widest = _layout.bounds.width;
    final target = math.min((size.width - 2 * fitPadding) / widest, maxFitScale);
    final scale = viewport.scale;
    viewport.zoomAt(Offset.zero, target / scale);
    final screen = viewport.toScreen(frame.topLeft);
    final x =
        (size.width - widest * viewport.scale) / 2 - viewport.toScreen(_layout.bounds.topLeft).dx;
    viewport.panBy(Offset(x, fitPadding + topInset - screen.dy));
  }

  void _onViewport() {
    if (!_framed && !viewport.size.isEmpty) {
      _framed = true;
      _frame(_current);
      return; // _frame notified the viewport again.
    }
    _refreshVisible();
  }

  /// Loads what is on screen and updates the current page.
  void _refreshVisible() {
    if (viewport.size.isEmpty) return;
    final visible = viewport.visibleWorld;
    surfaces.showPages({
      for (final index in _layout.visiblePages(visible))
        _pages[index].id: visible.shift(-_layout.frameOf(index)!.topLeft),
    });
    if (_flow == PageFlow.continuous) {
      final current = _layout.currentPage(visible);
      if (current != null && current != _current) {
        _current = current;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    viewport.removeListener(_onViewport);
    pageViewport.dispose();
    viewport.dispose();
    surfaces.dispose();
    super.dispose();
  }
}
