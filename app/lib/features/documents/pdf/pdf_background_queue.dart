part of 'pdf_background_cache.dart';

/// The cache's images and render queue: looking images up (most recently
/// used last), queueing requests, rendering tiles and evicting over budget.
extension _PdfBackgroundQueue on PdfBackgroundCache {
  /// Tiers of requests, served in this order: pages painted in view (and
  /// thumbnails), viewport renders, tiles in view, pages just outside the
  /// view.
  static const painted = 0, viewport = 1, tile = 2, ahead = 3;

  ui.Image? _touch(Object key) {
    final hit = _images.remove(key);
    if (hit != null) _images[key] = hit; // Most recently used.
    return hit;
  }

  /// A cached image of [key]'s page at least as wide as [key] but at most
  /// [PdfBackgroundCache.reuseUpTo] wider (touched), if any: the narrowest.
  ui.Image? _wideEnough(_PageImage key) {
    _PageImage? best;
    for (final k in _images.keys) {
      if (k is! _PageImage || k.background != key.background) continue;
      if (k.width < key.width || k.width > key.width * PdfBackgroundCache.reuseUpTo + 1) continue;
      if (best == null || k.width < best.width) best = k;
    }
    return best == null ? null : _touch(best);
  }

  /// Whether a render of [key]'s page that [_wideEnough] would use is in
  /// flight (so asking for [key] too would only render it twice).
  bool _renderingWideEnough(_PageImage key) => _inFlight.any(
    (k) =>
        k is _PageImage &&
        k.background == key.background &&
        k.width >= key.width &&
        k.width <= key.width * PdfBackgroundCache.reuseUpTo + 1,
  );

  ui.Image? _bestFor(PageBackground background) {
    ui.Image? best;
    for (final MapEntry(:key, :value) in _images.entries) {
      if (key is! _PageImage || key.background != background) continue;
      if (best == null || value.width > best.width) best = value;
    }
    return best;
  }

  void _request(Object key, {required int tier, int rank = 0, ui.Size? page}) {
    // Being rendered: this request joins that render (rendering it again
    // would only replace its image).
    if (_disposed || _images.containsKey(key) || _inFlight.contains(key)) return;
    _queue.remove(key);
    _queue[key] = (at: _clock.elapsedMilliseconds, frame: _frame, tier: tier, rank: rank);
    if ((key is PdfTile || key is PdfViewport) && page != null) _tilePages[key] = page;
    if (!_working) unawaited(_work());
  }

  /// The next request to serve: the lowest tier, of it what the latest
  /// frame asked for, of that the lowest rank, the newest of equals; stale
  /// requests are dropped on the way.
  Object? _next() {
    final now = _clock.elapsedMilliseconds;
    _queue.removeWhere((key, p) {
      final stale = now - p.at > PdfBackgroundCache.staleAfter.inMilliseconds;
      if (stale) _tilePages.remove(key);
      return stale;
    });
    Object? next;
    _Pending? best;
    for (final MapEntry(:key, value: p) in _queue.entries) {
      final b = best;
      final better =
          b == null ||
          p.tier < b.tier ||
          p.tier == b.tier && (p.frame > b.frame || p.frame == b.frame && p.rank <= b.rank);
      if (better) {
        next = key;
        best = p;
      }
    }
    if (next != null) _queue.remove(next);
    return next;
  }

  Future<void> _work() async {
    _working = true;
    try {
      // Lets the rest of the frame ask for its pages first, so the most
      // central one goes first rather than the first painted.
      await Future<void>.value();
      while (!_disposed) {
        final key = _next();
        if (key == null) break;
        _inFlight.add(key);
        // The next render starts once PDFium is done with this one, while
        // its pixels are copied into an image.
        final released = Completer<void>();
        void release() {
          if (!released.isCompleted) released.complete();
        }

        _finishing++;
        unawaited(
          _render(key, release).whenComplete(() {
            _inFlight.remove(key);
            _finishing--;
            release();
          }),
        );
        await released.future;
      }
    } finally {
      _working = false;
    }
  }

  Future<ui.Image?> _renderTile(PdfTile tile, void Function() released) async {
    final page = _tilePages.remove(tile);
    if (page == null) return null;
    final area = PdfTiling.pixels(page, tile.width, tile.col, tile.row);
    return _renderer.renderArea(
      tile.background.blob,
      tile.background.pageIndex,
      fullWidth: tile.width,
      fullHeight: PdfTiling.heightAt(tile.width, page),
      x: area.x,
      y: area.y,
      width: area.width,
      height: area.height,
      released: released,
    );
  }

  Future<ui.Image?> _renderViewport(PdfViewport v, void Function() released) async {
    final page = _tilePages.remove(v);
    if (page == null) return null;
    return _renderer.renderArea(
      v.background.blob,
      v.background.pageIndex,
      fullWidth: v.width,
      fullHeight: PdfTiling.heightAt(v.width, page),
      x: v.x,
      y: v.y,
      width: v.w,
      height: v.h,
      released: released,
    );
  }

  /// Caches [image] as [key]'s, disposing any image it replaces, and
  /// evicts the least recently used images over the budget.
  void _store(Object key, ui.Image image) {
    final old = _images.remove(key);
    if (old != null && !identical(old, image)) old.dispose();
    if (key is PdfViewport) {
      // One viewport render per page: the newest.
      for (final k in _images.keys.toList()) {
        if (k is PdfViewport && k.background == key.background) _images.remove(k)!.dispose();
      }
    }
    _images[key] = image;
    _evict();
  }

  void _evict() {
    var bytes = _images.values.fold<int>(0, (sum, i) => sum + i.width * i.height * 4);
    while (bytes > budgetBytes && _images.length > 1) {
      final oldest = _images.keys.first;
      final image = _images.remove(oldest)!;
      bytes -= image.width * image.height * 4;
      image.dispose();
    }
  }
}
