part of 'pdf_background_cache.dart';

/// The cache's images and render queue: looking images up (most recently
/// used last), queueing requests, rendering tiles and evicting over budget.
extension _PdfBackgroundQueue on PdfBackgroundCache {
  ui.Image? _touch(Object key) {
    final hit = _images.remove(key);
    if (hit != null) _images[key] = hit; // Most recently used.
    return hit;
  }

  ui.Image? _bestFor(PageBackground background) {
    ui.Image? best;
    for (final MapEntry(:key, :value) in _images.entries) {
      if (key is! _PageImage || key.background != background) continue;
      if (best == null || value.width > best.width) best = value;
    }
    return best;
  }

  void _request(Object key, {ui.Size? page}) {
    if (_disposed) return;
    _queue.remove(key);
    _queue[key] = _clock.elapsedMilliseconds;
    if (key is PdfTile && page != null) _tilePages[key] = page;
    if (!_working) unawaited(_work());
  }

  /// The next request to serve: the newest whole page, else the newest tile;
  /// stale requests are dropped on the way.
  Object? _next() {
    final now = _clock.elapsedMilliseconds;
    _queue.removeWhere((key, at) {
      final stale = now - at > PdfBackgroundCache.staleAfter.inMilliseconds;
      if (stale && key is PdfTile) _tilePages.remove(key);
      return stale;
    });
    Object? next;
    for (final key in _queue.keys) {
      if (key is _PageImage) next = key; // The newest whole page…
    }
    next ??= _queue.isEmpty ? null : _queue.keys.last; // …else the newest tile.
    if (next != null) _queue.remove(next);
    return next;
  }

  Future<void> _work() async {
    _working = true;
    try {
      while (!_disposed) {
        final key = _next();
        if (key == null) break;
        await _render(key);
      }
    } finally {
      _working = false;
    }
  }

  Future<ui.Image?> _renderTile(PdfTile tile) async {
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
    );
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
