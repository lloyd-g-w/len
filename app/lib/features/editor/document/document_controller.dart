import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show EdgeInsets;

import '../../../data/element_repository.dart';
import '../../../data/stroke_repository.dart';
import '../../../domain/notebook_page.dart';
import '../../../ink/input/ink_input_controller.dart';
import '../../../ink/surface_model.dart';
import '../../../ink/viewport.dart';
import '../tabs/open_notebooks.dart';
import 'document_layout.dart';
import 'document_scroller.dart';
import 'document_surfaces.dart';
import 'page_viewport.dart';

/// State of an open paged notebook: its pages, their layout in document
/// space, the viewport, which page is current (shown in the indicator) and
/// which one receives input (the active page).
class DocumentController extends ChangeNotifier {
  DocumentController({
    required List<NotebookPage> pages,
    required StrokeRepository strokes,
    ElementRepository? elements,
    this._flow = PageFlow.continuous,
    int initialPage = 0,
    this._initialView,
  }) : assert(pages.isNotEmpty, 'A document needs at least one page'),
       _pages = pages,
       _current = initialPage.clamp(0, pages.length - 1),
       surfaces = DocumentSurfaces(strokes, elements: elements) {
    _active = _current;
    surfaces.active = pages[_current].id;
    _relayout();
    viewport.addListener(_onViewport);
  }

  /// Pans and zooms the whole document.
  final ViewportController viewport = ViewportController(minScale: 0.1, maxScale: 8);

  /// Animates scrolls to a page ([scrollToPage]).
  late final DocumentScroller scroller = DocumentScroller(viewport, apply: applyView);

  /// Called before a page jump or scroll moves the view, e.g. to stop an
  /// inertial glide that would fight it.
  VoidCallback? beforeJump;

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

  /// Screen space covered by editor chrome (top bar, toolbar, page
  /// navigator). Pages can be scrolled clear of it, and a page shown by
  /// [goToPage] starts below the top inset.
  EdgeInsets get insets => _insets;
  EdgeInsets _insets = EdgeInsets.zero;

  /// Room (screen pixels) below the last page for the "add page" button in
  /// continuous flow.
  static const double footerExtent = 112;

  EditorViewState? _initialView;

  void setInsets(EdgeInsets insets) {
    if (insets == _insets) return;
    _insets = insets;
    _updateBounds();
  }

  /// Where the document is looking (to restore it later, e.g. in a tab).
  EditorViewState get viewState =>
      EditorViewState(scale: viewport.scale, offset: viewport.offset, page: _current);

  /// The frame of the last page on screen, for the "add page" footer.
  Rect? get lastPageOnScreen {
    final frame = _layout.frameOf(_pages.length - 1);
    if (frame == null) return null;
    return Rect.fromPoints(viewport.toScreen(frame.topLeft), viewport.toScreen(frame.bottomRight));
  }

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
    if (!pages.any((p) => p.id == activeId)) {
      // The active page is going away: drop what the tools hold on it
      // before its surface is released.
      input
        ?..cancelDraw()
        ..content?.selection.clear()
        ..content?.text.discard();
    }
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
    beforeJump?.call();
    scroller.stop();
    _current = index;
    if (_flow == PageFlow.single) _relayout();
    _activate(index);
    _frame(index);
    _refreshVisible();
    _current = index; // Not whatever the probe found mid-page.
    notifyListeners();
  }

  /// Like [goToPage], but scrolls there smoothly in continuous flow.
  void scrollToPage(int index) {
    if (index < 0 || index >= _pages.length) return;
    final target = _flow == PageFlow.continuous ? frameTarget(index) : null;
    if (target == null) {
      goToPage(index);
      return;
    }
    beforeJump?.call();
    // Show the destination in the indicator straight away.
    _current = index;
    notifyListeners();
    scroller.animateTo(target.scale, target.offset, onDone: () => settleOn(index));
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
    surfaces.active = _pages[index].id;
    pageViewport.showPage(_layout.frameOf(index) ?? _layout.frames.first);
    input?.model = activeModel;
  }

  void _relayout() {
    _layout = _flow == PageFlow.continuous
        ? DocumentLayout.continuous([for (final p in _pages) p.size])
        : DocumentLayout.single(_current, _pages[_current].size);
    _updateBounds();
  }

  /// The layout's bounds, padded so content can scroll clear of the chrome
  /// (and, in continuous flow, past the end to the "add page" footer).
  /// The padding is in screen pixels, so it is recomputed when zooming.
  void _updateBounds() {
    final b = _layout.bounds;
    final s = viewport.scale;
    final footer = _flow == PageFlow.continuous ? footerExtent : 0;
    viewport.contentBounds = Rect.fromLTRB(
      b.left,
      b.top - _insets.top / s,
      b.right,
      b.bottom + (_insets.bottom + footer) / s,
    );
  }

  // ---------------------------------------------------------------------------
  // Viewport

  /// Fits page [index] to the screen width (capped) and scrolls its top
  /// into view.
  void _frame(int index) {
    final target = frameTarget(index);
    if (target != null) applyView(target.scale, target.offset);
  }

  void _onViewport() {
    _updateBounds(); // A no-op unless the zoom changed.
    if (!_framed && !viewport.size.isEmpty) {
      _framed = true;
      final view = _initialView;
      _initialView = null;
      if (view != null) {
        applyView(view.scale, view.offset);
      } else {
        _frame(_current);
      }
      return; // The viewport notified again.
    }
    _refreshVisible();
  }

  /// Sets the viewport's zoom and pan (within the document's bounds).
  void applyView(double scale, Offset offset) {
    viewport.zoomAt(Offset.zero, scale / viewport.scale);
    viewport.panBy(offset - viewport.offset);
  }

  /// The zoom and pan that [goToPage] would use to show page [index]: fit
  /// to the width (continuous flow) or whole (single-page flow) and below
  /// the top chrome. Null before the first layout.
  ({double scale, Offset offset})? frameTarget(int index) {
    final size = viewport.size;
    final frame = _layout.frameOf(index);
    if (size.isEmpty || frame == null) return null;
    final widest = _layout.bounds.width;
    var scale = math.min((size.width - 2 * fitPadding) / widest, maxFitScale);
    if (_flow == PageFlow.single) {
      final free = size.height - _insets.vertical - 2 * fitPadding;
      if (free > 0) scale = math.min(scale, free / frame.height);
    }
    final x = (size.width - widest * scale) / 2 - _layout.bounds.left * scale;
    final y = fitPadding + _insets.top - frame.top * scale;
    return (scale: scale.clamp(viewport.minScale, viewport.maxScale), offset: Offset(x, y));
  }

  /// Marks page [index] as current once a scroll to it has finished.
  void settleOn(int index) {
    if (index < 0 || index >= _pages.length) return;
    _activate(index);
    _refreshVisible();
    _current = index;
    notifyListeners();
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
    scroller.dispose();
    pageViewport.dispose();
    viewport.dispose();
    surfaces.dispose();
    super.dispose();
  }
}
