import 'dart:ui';

import '../../../ink/viewport.dart';

/// A view of one page through the document viewport.
///
/// The ink engine (input controller, live-ink painter) works in the
/// coordinates of a single surface. This adapter presents the document
/// viewport in the active page's local coordinates: world = document −
/// [origin]. Panning and zooming are forwarded to the document viewport,
/// so gestures that start on any page move the whole document.
class PageViewport extends ViewportController {
  PageViewport(this.document) : super(minScale: document.minScale, maxScale: document.maxScale) {
    document.addListener(notifyListeners);
  }

  /// The viewport of the whole document (the source of truth).
  final ViewportController document;

  Offset _origin = Offset.zero;
  Rect? _page;

  /// Top-left of the active page in document coordinates.
  Offset get origin => _origin;

  /// Points this view at a page with the given document-space [frame].
  void showPage(Rect frame) {
    final page = Offset.zero & frame.size;
    if (frame.topLeft == _origin && page == _page) return;
    _origin = frame.topLeft;
    _page = page;
    notifyListeners();
  }

  @override
  Rect? get contentBounds => _page;

  @override
  set contentBounds(Rect? value) {} // Owned by the document layout.

  @override
  double get scale => document.scale;

  @override
  Offset get offset => document.offset + _origin * document.scale;

  @override
  Size get size => document.size;

  @override
  Rect get visibleWorld => visibleWorldFor(size);

  @override
  Rect visibleWorldFor(Size size) => document.visibleWorldFor(size).shift(-_origin);

  @override
  Offset toWorld(Offset screen) => document.toWorld(screen) - _origin;

  @override
  Offset toScreen(Offset world) => document.toScreen(world + _origin);

  @override
  void setSize(Size size) => document.setSize(size);

  @override
  void panBy(Offset screenDelta) => document.panBy(screenDelta);

  @override
  void zoomAt(Offset focal, double factor) => document.zoomAt(focal, factor);

  @override
  void fitWidth({double padding = 24}) {}

  @override
  void dispose() {
    document.removeListener(notifyListeners);
    super.dispose();
  }
}
