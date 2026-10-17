part of 'ink_tile_cache.dart';

/// Tile spaces (zooming) and invalidation (edits, loads).
extension _Invalidation on InkTileCache {
  void _scheduleSettle(TileSpace target) {
    _pendingSpace = target;
    _settle?.cancel();
    _settle = Timer(settleDelay, () {
      _settle = null;
      final next = _pendingSpace;
      if (next == null || _disposed) return;
      _adopt(next);
      _notify();
    });
  }

  /// Makes [space] current; today's tiles stand in until it is rendered.
  void _adopt(TileSpace space) {
    _releaseAll(_old);
    _old = {
      for (final e in _tiles.entries)
        if ((e.value.image != null || e.value.blank == true) &&
            e.value.overlay.isEmpty &&
            !e.value.stale)
          e.key: e.value,
    };
    _releaseAll({
      for (final e in _tiles.entries)
        if (!_old.containsKey(e.key)) e.key: e.value,
    });
    _oldSpace = _space;
    _space = space;
    _tiles = {};
    _requests.clear();
  }

  // ---------------------------------------------------------------------------
  // Invalidation

  void _onChange(SurfaceChange change) {
    final chunks = change.chunks;
    if (chunks == null) {
      _dropAll();
      _notify();
      return;
    }
    final areas = change.areas ?? [for (final c in chunks) ChunkGrid.rectOf(c)];
    // Tiles of the previous zoom no longer show the content.
    for (final tile in _touching(_old, areas)) {
      _old.remove(tile.index);
      tile.release();
    }
    final appended = change.appended;
    if (appended != null && _space != null) {
      for (final stroke in appended) {
        final bounds = _clip == null ? stroke.bounds : stroke.bounds.intersect(_clip!);
        if (bounds.isEmpty) continue;
        for (final index in _space!.covering(bounds)) {
          final tile = _tiles[index] ??= InkTile(pool, _space!, index);
          tile
            ..overlay.add(stroke)
            ..blank = false;
          if (!_inUse) continue;
          if (!_spare || tile.overlay.length >= InkTileCache.maxOverlay) _request(index, 0);
        }
      }
      if (_spare && _inUse) _scheduleMerge();
      return;
    }
    final underlaid = change.underlaid;
    if (underlaid != null && _space != null) return _underlay(underlaid, areas);
    final overlaid = change.overlaid;
    if (overlaid != null && _space != null) return _overlay(overlaid, areas);
    final hit = _touching(_tiles, areas);
    if (change.loaded) {
      // Stored content arrived: it was not on screen before, so nothing
      // the user did lingers while the old images stand in.
      _restale(hit, 1);
    } else if (hit.where((t) => t.image != null).length <= InkTileCache.maxVectorTiles) {
      for (final tile in hit) {
        tile
          ..invalidate()
          ..edited = true;
      }
    } else {
      // A large edit (undo of a lasso move, say): rather than frames of
      // vectors over much of the screen, the old images stay until the new
      // ones, all rendered at once, replace them together a frame or two
      // later (see [_flushBatch]).
      _restale(hit, 0);
    }
  }

  /// A highlighter's pen-up: tiles with an image keep it, stale, with the
  /// strokes drawn beneath it — as the live stroke was, beneath the
  /// committed ink — until rendered again (urgently); tiles without one
  /// show the content as it now is from vectors. So the highlight never
  /// misses a frame, however many tiles it crosses.
  void _underlay(List<Stroke> strokes, List<ui.Rect> areas) {
    for (final tile in _touching(_tiles, areas)) {
      if (tile.image == null) {
        tile
          ..invalidate()
          ..edited = true;
        continue;
      }
      final rect = tile.space.worldRectOf(tile.index);
      tile
        ..dropParked()
        ..version += 1
        ..stale = true
        ..underlay.addAll(strokes.where((s) => s.bounds.overlaps(rect)));
      if (_inUse) _request(tile.index, 0);
    }
  }

  /// New pen strokes something paints over (no append): tiles with an
  /// image keep it, stale, with the strokes drawn over it — as the live
  /// stroke was, over the committed ink — until rendered again (urgently);
  /// tiles without one show the content as it now is from vectors. So the
  /// stroke never misses a frame at pen-up, however many tiles it crosses.
  void _overlay(List<Stroke> strokes, List<ui.Rect> areas) {
    for (final tile in _touching(_tiles, areas)) {
      if (tile.image == null) {
        tile
          ..invalidate()
          ..edited = true;
        continue;
      }
      final rect = tile.space.worldRectOf(tile.index);
      tile
        ..dropParked()
        ..version += 1
        ..stale = true
        ..overlay.addAll(strokes.where((s) => s.bounds.overlaps(rect)));
      if (_inUse) _request(tile.index, 0);
    }
  }

  /// Merges the strokes written into their tiles once the pen rests
  /// ([InkTileCache.mergeDelay]).
  void _scheduleMerge() {
    _merge?.cancel();
    _merge = Timer(InkTileCache.mergeDelay, () {
      _merge = null;
      // Painted when the strokes were written; perhaps not since (nothing
      // moved while the pen rested).
      if (_disposed) return;
      for (final tile in _tiles.values) {
        if (tile.overlay.isNotEmpty) _request(tile.index, 0);
      }
    });
  }

  /// The tiles of [tiles] overlapping any of [areas].
  List<InkTile> _touching(Map<TileIndex, InkTile> tiles, List<ui.Rect> areas) {
    if (tiles.isEmpty || areas.isEmpty) return const [];
    return [
      for (final tile in tiles.values)
        if (areas.any(tile.space.worldRectOf(tile.index).overlaps)) tile,
    ];
  }

  /// Tiles whose content changed keep showing their image until rendered
  /// again (requested at [priority]); those without one are invalidated.
  void _restale(List<InkTile> tiles, int priority) {
    for (final tile in tiles) {
      if (tile.image == null) {
        final edited = tile.edited || priority == 0;
        tile
          ..invalidate()
          ..edited = edited;
        continue;
      }
      tile
        ..dropParked()
        ..version += 1
        ..stale = true
        // Strokes added since, unless erased or hidden by this change.
        ..overlay.removeWhere((s) => model.strokeById(s.id) != s || model.isHidden(s.id))
        ..underlay.removeWhere((s) => model.strokeById(s.id) != s || model.isHidden(s.id));
      tile.batched = priority == 0;
      if (_inUse) _request(tile.index, priority);
    }
  }

  void _prune() {
    _tiles.removeWhere(
      (index, tile) =>
          tile.image == null &&
          tile.parked == null &&
          !tile.rendering &&
          tile.overlay.isEmpty &&
          !_requests.containsKey(index),
    );
  }

  void _dropAll() {
    _releaseAll(_tiles);
    _releaseAll(_old);
    _tiles = {};
    _old = {};
    _oldSpace = null;
    _space = null;
    _requests.clear();
  }

  void _releaseAll(Map<TileIndex, InkTile> tiles) {
    for (final tile in tiles.values) {
      tile.release();
    }
  }
}
