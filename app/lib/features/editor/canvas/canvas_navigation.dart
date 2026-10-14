import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart' show EdgeInsets;

import '../../../data/stroke_reader.dart';
import '../../../ink/navigation/viewport_animator.dart';
import '../../../ink/viewport.dart';
import '../tabs/open_notebooks.dart';

/// Navigation of an infinite canvas: animated zoom steps, "fit content" and "back to the origin".
class CanvasNavigation extends ChangeNotifier {
  CanvasNavigation({required this.viewport, required this.reader, required this.surfaceId});

  final ViewportController viewport;
  final StrokeReader reader;
  final String surfaceId;

  late final ViewportAnimator animator = ViewportAnimator(viewport);

  /// Zoom levels the zoom-in / zoom-out actions step through.
  static const List<double> zoomSteps = [
    0.05, 0.1, 0.25, 0.5, 0.75, 1, 1.5, 2, 3, 4, 6, 8, 12, 16, //
  ];

  /// "Fit content" never magnifies beyond this (a lone word would fill
  /// the screen otherwise).
  static const double fitScaleCap = 2;

  /// Opening a canvas shows its content at most at 100 %.
  static const double openScaleCap = 1;

  /// Screen padding around fitted content (inside [insets]).
  static const double fitPadding = 32;

  /// Screen edges covered by the editor's chrome: fits keep clear of them.
  EdgeInsets get insets => _insets;
  EdgeInsets _insets = EdgeInsets.zero;

  /// The view to restore once the viewport is laid out ([open]).
  EditorViewState? _opening;
  bool _waitingForSize = false;
  bool _waitingForInsets = false;

  /// Whether [open] still waits for the first [setInsets].
  bool get waitingForInsets => _waitingForInsets || _waitingForSize;
  bool _disposed = false;
  bool _hasInsets = false;

  /// Zooms in to the next step, about [focal] (default: the centre).
  void zoomIn({Offset? focal}) => animator.zoomTo(
    zoomSteps.firstWhere((s) => s > viewport.scale * 1.01, orElse: () => zoomSteps.last),
    focal: focal,
  );

  /// Zooms out to the previous step, about [focal] (default: the centre).
  void zoomOut({Offset? focal}) => animator.zoomTo(
    zoomSteps.lastWhere((s) => s < viewport.scale / 1.01, orElse: () => zoomSteps.first),
    focal: focal,
  );

  /// Animates to [scale] (1 = 100 %) about the centre of the view.
  void zoomTo(double scale) => animator.zoomTo(scale);

  /// Shows all the ink on the canvas, or the origin if there is none.
  Future<void> fitContent() async {
    final bounds = await reader.contentBounds(surfaceId);
    if (_disposed) return; // The canvas closed meanwhile.
    if (bounds == null) return goToOrigin();
    final view = viewFitting(bounds, scaleCap: fitScaleCap);
    animator.animateTo(scale: view.scale, offset: view.offset);
  }

  /// The view showing [world] as large as fits (at most [scaleCap]),
  /// centred in the part of the screen the chrome leaves free.
  ({double scale, Offset offset}) viewFitting(Rect world, {double scaleCap = fitScaleCap}) {
    final size = viewport.size;
    var area = _insets.deflateRect(Offset.zero & size).deflate(fitPadding);
    if (area.width < 1 || area.height < 1) area = Offset.zero & size;
    final fit = math.min(
      area.width / math.max(world.width, 1),
      area.height / math.max(world.height, 1),
    );
    final scale = math.min(fit, scaleCap).clamp(viewport.minScale, viewport.maxScale);
    return (scale: scale, offset: area.center - world.center * scale);
  }

  /// Sets the chrome [insets]; the first call finishes [open].
  void setInsets(EdgeInsets insets) {
    _insets = insets;
    _hasInsets = true;
    if (_waitingForInsets) {
      _waitingForInsets = false;
      unawaited(_openFresh());
    }
  }

  /// Shows the canvas once its viewport is laid out: [view] where it was
  /// left (same screen size), else centred on its content (at most 100 %)
  /// once the chrome's [insets] are known, so nothing hides under it.
  void open(EditorViewState? view) {
    _opening = view;
    _waitingForSize = true;
    viewport.addListener(_onFirstSize);
    _onFirstSize();
  }

  void _onFirstSize() {
    final size = viewport.size;
    if (!_waitingForSize || size.isEmpty) return;
    _waitingForSize = false;
    viewport.removeListener(_onFirstSize);
    final view = _opening;
    if (view != null && view.fitsSize(size)) {
      _opening = null;
      _quietly(() => viewport.setView(scale: view.scale, offset: view.offset));
    } else if (_hasInsets) {
      unawaited(_openFresh());
    } else {
      _waitingForInsets = true;
    }
  }

  Future<void> _openFresh() async {
    final view = _opening;
    _opening = null;
    if (view != null) {
      // Saved at another size: keep the same point in the middle.
      final centre = (view.size!.center(Offset.zero) - view.offset) / view.scale;
      final middle = _insets.deflateRect(Offset.zero & viewport.size).center;
      _quietly(() => viewport.setView(scale: view.scale, offset: middle - centre * view.scale));
      return;
    }
    final before = (viewport.scale, viewport.offset);
    final bounds = await reader.contentBounds(surfaceId);
    // Not if the user already moved (or the canvas is empty: the origin).
    if (_disposed || bounds == null || before != (viewport.scale, viewport.offset)) return;
    final fitted = viewFitting(bounds, scaleCap: openScaleCap);
    _quietly(() => viewport.setView(scale: fitted.scale, offset: fitted.offset));
  }

  /// Whether the view is being set by [open] (not a zoom to announce).
  bool get opening => _openingNow;
  bool _openingNow = false;

  void _quietly(VoidCallback change) {
    _openingNow = true;
    try {
      change();
    } finally {
      _openingNow = false;
    }
  }

  /// The screen area the chrome leaves free (where fits centre).
  Rect get _freeArea {
    final area = _insets.deflateRect(Offset.zero & viewport.size);
    return area.width < 1 || area.height < 1 ? Offset.zero & viewport.size : area;
  }

  /// The world area on screen and not under the chrome.
  Rect get visibleArea {
    final area = _freeArea;
    return Rect.fromPoints(viewport.toWorld(area.topLeft), viewport.toWorld(area.bottomRight));
  }

  /// Brings [world] to the middle of the free area: gliding there, or at
  /// once (dragging on the minimap). The zoom stays.
  void centreOn(Offset world, {bool animate = true}) {
    final offset = _freeArea.center - world * viewport.scale;
    if (animate) return animator.animateTo(scale: viewport.scale, offset: offset);
    animator.stop();
    viewport.setView(scale: viewport.scale, offset: offset);
  }

  /// Zooms by [factor] at once about the middle of the free area (pinching
  /// on the minimap).
  void zoomBy(double factor) {
    animator.stop();
    viewport.zoomAt(_freeArea.center, factor);
  }

  /// Zooms one step in ([steps] > 0) or out about the middle of the free
  /// area (scrolling on the minimap).
  void zoomStep(int steps) {
    final centre = _freeArea.center;
    steps > 0 ? zoomIn(focal: centre) : zoomOut(focal: centre);
  }

  /// Back to where a new canvas starts: the origin at the top left (below
  /// the chrome), 100 %.
  void goToOrigin() => animator.animateTo(scale: 1, offset: Offset(_insets.left, _insets.top));

  @override
  void dispose() {
    _disposed = true;
    viewport.removeListener(_onFirstSize);
    animator.dispose();
    super.dispose();
  }
}
