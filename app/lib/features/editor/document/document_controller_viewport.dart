part of 'document_controller.dart';

/// Which page is active, framing pages in the viewport and loading what
/// is on screen.
mixin _DocumentViewport on _DocumentState {
  void _activate(int index) {
    // Laid out together (continuous flow), the laser keeps showing where
    // it was when another page becomes the active one.
    final was = _pages.indexWhere((p) => p.id == surfaces.active);
    final from = was == -1 ? null : _layout.frameOf(was);
    final to = _layout.frameOf(index);
    _active = index;
    surfaces.active = _pages[index].id;
    pageViewport.showPage(to ?? _layout.frames.first);
    final shift = from != null && to != null ? from.topLeft - to.topLeft : null;
    input?.switchTo(activeModel, laserShift: shift);
  }

  void _relayout() {
    _layout = _flow == PageFlow.continuous
        ? DocumentLayout.continuous([for (final p in _pages) p.size])
        : DocumentLayout.single(_current, _pages[_current].size);
    _updateBounds();
  }

  /// Fits page [index] to the screen width (capped) and scrolls its top
  /// into view.
  @override
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
  @override
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
    final free = size.height - _insets.vertical - 2 * DocumentController.fitPadding;
    // A whole page shown alone sits in the middle of the free space.
    final alone = _flow == PageFlow.single;
    final spare = alone ? math.max(0.0, free - frame.height * scale) : 0.0;
    final x = (size.width - widest * scale) / 2 - _layout.bounds.left * scale;
    final y = DocumentController.fitPadding + _insets.top + spare / 2 - frame.top * scale;
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
    // Pages about to scroll into view load ahead, so they show complete.
    final ahead = DocumentLayout.lookahead(visible);
    surfaces.showPages({
      for (final index in _layout.visiblePages(ahead))
        _pages[index].id: ahead.shift(-_layout.frameOf(index)!.topLeft),
    });
    if (_flow == PageFlow.continuous) {
      final current = _layout.currentPage(visible);
      if (current != null && current != _current) {
        _current = current;
        notifyListeners();
      }
    }
  }
}
