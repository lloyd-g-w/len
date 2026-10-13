part of 'document_controller.dart';

/// What a [DocumentController] holds: the pages and their layout, the
/// viewport, and the room the chrome and overlays take around the pages.
abstract class _DocumentState extends ChangeNotifier {
  _DocumentState({
    required this._pages,
    required this._current,
    required this.surfaces,
    required this._flow,
    required this._initialView,
    required this._fit,
  });

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

  /// Screen space covered by editor chrome (top bar, toolbar, page
  /// navigator). Pages can be scrolled clear of it, and a page shown by
  /// [goToPage] starts below the top inset.
  EdgeInsets get insets => _insets;
  EdgeInsets _insets = EdgeInsets.zero;

  EditorViewState? _initialView;

  PageFit _fit;

  /// How pages are zoomed when opening and jumping to a page.
  PageFit get fit => _fit;

  /// The view last set by fitting a page, while the user hasn't moved it:
  /// it is re-fitted when the chrome or the screen size changes.
  ({double scale, Offset offset, Size size})? _fitted;

  /// Extra screen space at the top covered by a transient overlay (the
  /// search bar): pages can scroll clear of it, but fits ignore it.
  double get overlayTop => _overlayTop;
  double _overlayTop = 0;

  void setOverlayTop(double top) {
    if (top == _overlayTop) return;
    _overlayTop = top;
    _updateBounds();
  }

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

  /// The layout's bounds, padded so content can scroll clear of the chrome
  /// (and, in continuous flow, past the end to the "add page" footer).
  /// The padding is in screen pixels, so it is recomputed when zooming.
  void _updateBounds() {
    final b = _layout.bounds;
    final s = viewport.scale;
    final footer = _flow == PageFlow.continuous ? DocumentController.footerExtent : 0;
    viewport.contentBounds = Rect.fromLTRB(
      b.left,
      b.top - math.max(_insets.top, _overlayTop) / s,
      b.right,
      b.bottom + (_insets.bottom + footer + _endRoom) / s,
    );
  }

  /// Fits page [index] to the screen (see [_DocumentViewport]).
  void _frame(int index);

  /// Sets the viewport's zoom and pan (see [_DocumentViewport]).
  void applyView(double scale, Offset offset);
}
