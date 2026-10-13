import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show EdgeInsets;

import '../../../data/element_repository.dart';
import '../../../data/stroke_repository.dart';
import '../../../domain/notebook_page.dart';
import '../../../domain/paper.dart';
import '../../../domain/paper_pattern.dart';
import '../../../ink/images/element_images.dart';
import '../../../ink/input/ink_input_controller.dart';
import '../../../ink/render/outline_preparer.dart';
import '../../../ink/surface_model.dart';
import '../../../ink/viewport.dart';
import '../tabs/open_notebooks.dart';
import 'document_layout.dart';
import 'document_scroller.dart';
import 'document_surfaces.dart';
import 'page_fit.dart';
import 'page_models.dart';
import 'page_viewport.dart';

/// State of an open paged notebook: its pages, their layout in document
/// space, the viewport, which page is current (shown in the indicator) and
/// which one receives input (the active page).
class DocumentController extends ChangeNotifier {
  DocumentController({
    required List<NotebookPage> pages,
    required StrokeRepository strokes,
    ElementRepository? elements,
    ElementImages? images,
    OutlinePreparer? outlines,
    this._flow = PageFlow.continuous,
    int initialPage = 0,
    this._initialView,
    this._fit = PageFit.auto,
    PageModels? models,
  }) : assert(pages.isNotEmpty, 'A document needs at least one page'),
       _pages = pages,
       _current = initialPage.clamp(0, pages.length - 1),
       surfaces = DocumentSurfaces(
         strokes,
         elements: elements,
         images: images,
         outlines: outlines,
         models: models,
       ) {
    _active = _current;
    surfaces.active = pages[_current].id;
    _relayout();
    // The page viewport needs the first active page too (its bounds clip
    // the content layer and keep inserted images on the page).
    pageViewport.showPage(_layout.frameOf(_active) ?? _layout.frames.first);
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
  NotebookPage get activePageData => _pages[_active];
  SurfaceModel get activeModel => surfaces.surfaceOf(_pages[_active].id).model;

  /// Screen padding around a fitted page.
  static const double fitPadding = PageFit.padding;

  /// Screen space covered by editor chrome (top bar, toolbar, page
  /// navigator). Pages can be scrolled clear of it, and a page shown by
  /// [goToPage] starts below the top inset.
  EdgeInsets get insets => _insets;
  EdgeInsets _insets = EdgeInsets.zero;

  /// Room (screen pixels) below the last page for the "add page" button in
  /// continuous flow.
  static const double footerExtent = 112;

  EditorViewState? _initialView;

  PageFit _fit;

  /// How pages are zoomed when opening and jumping to a page.
  PageFit get fit => _fit;

  /// The view last set by fitting a page, while the user hasn't moved it:
  /// it is re-fitted when the chrome or the screen size changes.
  ({double scale, Offset offset, Size size})? _fitted;

  void setInsets(EdgeInsets insets) {
    if (insets == _insets) return;
    // Asked before the new bounds may nudge the view.
    final untouched = _untouched;
    _insets = insets;
    _updateBounds();
    if (untouched) _frame(_current);
  }

  /// Whether the view is still the one the last fit set (the user has not
  /// scrolled or zoomed since).
  bool get _untouched {
    final f = _fitted;
    return f != null &&
        (f.scale - viewport.scale).abs() < 1e-6 &&
        (f.offset - viewport.offset).distance < 0.5;
  }

  /// Changes how pages are zoomed and shows the current page that way.
  void setFit(PageFit fit) {
    _fit = fit;
    scrollToPage(_current, animateSamePage: true);
    notifyListeners();
  }

  /// Where the document is looking (to restore it later, e.g. in a tab).
  EditorViewState get viewState => EditorViewState(
    scale: viewport.scale,
    offset: viewport.offset,
    page: _current,
    size: viewport.size,
    fit: _fit == PageFit.auto ? null : _fit.name,
  );

  /// Extra room (screen pixels) past the end for controls floating over
  /// the bottom of the document (the recording pill, the player), so the
  /// "add page" footer can scroll clear of them.
  double get endRoom => _endRoom;
  double _endRoom = 0;

  /// Sets [endRoom]; scrolled to the end, the view stays at the end (so
  /// the footer moves up out of the way).
  void setEndRoom(double room) {
    if (room == _endRoom) return;
    final grow = room - _endRoom;
    final bounds = viewport.contentBounds;
    final end = viewport.size.height - ViewportController.overscroll;
    final atEnd = bounds != null && (viewport.toScreen(bounds.bottomLeft).dy - end).abs() < 0.5;
    _endRoom = room;
    _updateBounds();
    if (atEnd && grow > 0) viewport.panBy(Offset(0, -grow));
  }

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

  /// Like [goToPage], but scrolls there smoothly in continuous flow (and
  /// with [animateSamePage], also re-fits the page shown in single flow).
  void scrollToPage(int index, {bool animateSamePage = false}) {
    if (index < 0 || index >= _pages.length) return;
    final smooth = _flow == PageFlow.continuous || (animateSamePage && index == _current);
    final target = smooth ? frameTarget(index) : null;
    if (target == null) {
      goToPage(index);
      return;
    }
    beforeJump?.call();
    // Show the destination in the indicator straight away.
    _current = index;
    notifyListeners();
    scroller.animateTo(
      target.scale,
      target.offset,
      onDone: () {
        settleOn(index);
        _fitted = (scale: viewport.scale, offset: viewport.offset, size: viewport.size);
      },
    );
  }

  /// The planner page a link at [screen] leads to (a day, week or month
  /// printed on a planner page), or null when there is no link there.
  Paper? plannerLinkAt(Offset screen) {
    final world = viewport.toWorld(screen);
    final index = _layout.pageAt(world);
    if (index == null) return null;
    final page = _pages[index];
    if (!page.paper.style.isPlanner) return null;
    final local = world - _layout.frameOf(index)!.topLeft;
    final pattern = PaperPattern.of(page.paper, page.bounds, page: page.bounds);
    for (final link in pattern.links) {
      if (link.rect.contains(local)) return link.target;
    }
    return null;
  }

  /// The index of the first page with template [paper], or -1.
  int indexOfPaper(Paper paper) => _pages.indexWhere((p) => p.paper.sameSheet(paper));

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
      b.bottom + (_insets.bottom + footer + _endRoom) / s,
    );
  }

  // ---------------------------------------------------------------------------
  // Viewport

  /// Fits page [index] to the screen width (capped) and scrolls its top
  /// into view.
  void _frame(int index) {
    final target = frameTarget(index);
    if (target == null) return;
    applyView(target.scale, target.offset);
    _fitted = (scale: viewport.scale, offset: viewport.offset, size: viewport.size);
  }

  void _onViewport() {
    _updateBounds(); // A no-op unless the zoom changed.
    final size = viewport.size;
    if (!_framed && !size.isEmpty) {
      _framed = true;
      final view = _initialView;
      _initialView = null;
      if (view != null && view.fitsSize(size)) {
        applyView(view.scale, view.offset);
      } else {
        _frame(_current);
      }
      return; // The viewport notified again.
    }
    // Rotated or resized while showing a fitted page: fit it again.
    final fitted = _fitted;
    if (fitted != null && fitted.size != size && !size.isEmpty) {
      final untouched = (fitted.scale - viewport.scale).abs() < 1e-6;
      _fitted = null;
      if (untouched) {
        _frame(_current);
        return;
      }
    }
    _refreshVisible();
  }

  /// Sets the viewport's zoom and pan (within the document's bounds).
  void applyView(double scale, Offset offset) {
    viewport.zoomAt(Offset.zero, scale / viewport.scale);
    viewport.panBy(offset - viewport.offset);
  }

  /// The zoom and pan that [goToPage] would use to show page [index],
  /// zoomed as [fit] says, horizontally centred, below the top chrome (in
  /// single-page flow, vertically centred when it fits). Null before the
  /// first layout.
  ({double scale, Offset offset})? frameTarget(int index) {
    final size = viewport.size;
    final frame = _layout.frameOf(index);
    if (size.isEmpty || frame == null) return null;
    final widest = _layout.bounds.width;
    final fit = _flow == PageFlow.single && _fit == PageFit.auto ? PageFit.page : _fit;
    final scale = fit
        .scale(screen: size, insets: _insets, width: widest, height: frame.height)
        .clamp(viewport.minScale, viewport.maxScale);
    final free = size.height - _insets.vertical - 2 * fitPadding;
    // A whole page shown alone sits in the middle of the free space.
    final alone = _flow == PageFlow.single;
    final spare = alone ? math.max(0.0, free - frame.height * scale) : 0.0;
    final x = (size.width - widest * scale) / 2 - _layout.bounds.left * scale;
    final y = fitPadding + _insets.top + spare / 2 - frame.top * scale;
    return (scale: scale, offset: Offset(x, y));
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
