part of 'ink_tile_cache.dart';

/// Rendering tiles off the frame, most urgent first.
extension _Rendering on InkTileCache {
  /// Whether [tile] is to be rendered ahead: strokes written over its
  /// image wait for the pen to rest where renders are spared.
  bool _wantsRender(InkTile tile) =>
      tile.needsRender && !(_spare && tile.image != null && !tile.stale);

  void _request(TileIndex index, int priority) {
    if (_disposed) return;
    final current = _requests[index];
    if (current != null && current <= priority) return;
    _requests[index] = priority;
    _schedulePump();
  }

  void _schedulePump() {
    if (_pumpTimer != null || _disposed) return;
    // After the frame being built (painting requests renders).
    _pumpTimer = Timer(Duration.zero, _pump);
  }

  void _pump() {
    _pumpTimer = null;
    if (_disposed || _space == null) return;
    if (_waitForLoad()) return;
    final watch = Stopwatch()..start();
    var first = true;
    while (_requests.isNotEmpty) {
      // Over budget: the rest in the next batch. At least one request is
      // handled per batch, however late it started (a busy machine), and
      // the next one is always scheduled: [_request] relies on it.
      if (!first && watch.elapsed >= batchBudget) {
        _schedulePump();
        break;
      }
      first = false;
      final index = _next();
      // Urgent renders (edits on screen) all start at once. The others
      // wait for a running render, which pumps again when it completes.
      if (_inFlight >= maxInFlight && _requests[index]! > 0) break;
      _requests.remove(index);
      final tile = _tiles[index] ??= InkTile(pool, _space!, index);
      if (tile.rendering) continue; // Requested again when it completes.
      tile.blank ??= model.chunksIn(ChunkGrid.rangeFor(tile.space.worldRectOf(index))).isEmpty;
      if (!tile.needsRender) continue;
      _render(tile);
    }
    _flushBatch();
  }

  /// Whether renders wait for the surface to finish loading ([_spare]):
  /// edits' never do.
  bool _waitForLoad() {
    if (!_holdForLoad || _requests.values.any((p) => p == 0)) return false;
    _pumpTimer = Timer(const Duration(milliseconds: 50), _pump);
    return true;
  }

  /// Whether a loading surface's tiles wait for the rest of it ([_spare]):
  /// for up to [InkTileCache.maxLoadWait], they are neither rendered nor
  /// drawn from vectors (frames of vectors cost as much GPU work as
  /// rendering), so each is rendered once, complete.
  bool get _holdForLoad {
    if (!_spare || !model.isLoading) {
      _loadWait = null;
      return false;
    }
    final wait = _loadWait ??= Stopwatch()..start();
    return wait.elapsed < InkTileCache.maxLoadWait;
  }

  /// The most urgent request (lowest priority value, newest first).
  TileIndex _next() {
    TileIndex? best;
    var bestPriority = 1 << 30;
    for (final e in _requests.entries) {
      if (e.value <= bestPriority) {
        best = e.key;
        bestPriority = e.value;
      }
    }
    return best!;
  }

  void _render(InkTile tile) {
    developer.Timeline.startSync('len.renderTile');
    final space = tile.space;
    final rect = space.worldRectOf(tile.index);
    final clipped = _clip == null ? rect : rect.intersect(_clip!);
    final included = tile.overlay.length;
    // A stale image is rendered afresh (the chunk pictures hold everything).
    final base = tile.stale ? null : tile.image;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    if (base != null) canvas.drawImage(base, ui.Offset.zero, _exactPaint);
    canvas
      ..translate(
        space.phase.dx - tile.index.x * TileSpace.size,
        space.phase.dy - tile.index.y * TileSpace.size,
      )
      ..scale(space.k)
      ..clipRect(clipped);
    if (base != null) {
      // Incremental: the strokes appended since [base] was rendered.
      for (final stroke in tile.overlay) {
        StrokeRenderer.draw(canvas, stroke);
      }
      PerfProbe.count('tileAppends');
    } else {
      // Chunk pictures hold everything committed so far, overlay included.
      for (final key in model.chunksIn(ChunkGrid.rangeFor(clipped))) {
        canvas.drawPicture(pictures.pictureFor(key));
      }
      PerfProbe.count('tileRenders');
    }
    final picture = recorder.endRecording();
    developer.Timeline.finishSync();
    final version = tile.version;
    tile.rendering = true;
    _inFlight++;
    unawaited(
      batch
          .rasterize(picture, TileSpace.size, TileSpace.size)
          .then(
            (raster) => _store(tile, version, included, raster.image),
            onError: (Object error, StackTrace stack) => FlutterError.reportError(
              FlutterErrorDetails(exception: error, stack: stack, library: 'len rendering'),
            ),
          )
          .whenComplete(() {
            picture.dispose();
            tile.rendering = false;
            _inFlight--;
            if (!_disposed && tile.needsRender && _tiles[tile.index] == tile) {
              _request(tile.index, tile.overlay.isEmpty ? 1 : 0);
            }
            _flushBatch();
            _schedulePump();
          }),
    );
  }

  void _store(InkTile tile, int version, int included, ui.Image image) {
    if (_disposed || tile.version != version || _tiles[tile.index] != tile) {
      image.dispose(); // Changed (or gone) while rendering.
      return;
    }
    if (tile.batched) {
      // Shown with the rest of its edit's tiles.
      tile.parked?.image.dispose();
      tile.parked = (image: image, version: version, included: included);
      _parked.add(tile);
      return;
    }
    _install(tile, image, included);
  }

  /// Shows the images rendered for a large edit together, once none of its
  /// tiles is still waiting for a render, so the edit never shows half
  /// done.
  void _flushBatch() {
    if (_parked.isEmpty) return;
    for (final tile in _tiles.values) {
      if (tile.batched && (tile.rendering || _requests.containsKey(tile.index))) return;
    }
    for (final tile in _tiles.values) {
      tile.batched = false;
    }
    for (final tile in _parked) {
      final parked = tile.parked;
      tile.parked = null;
      if (parked == null) continue; // Released meanwhile.
      if (_disposed || tile.version != parked.version || _tiles[tile.index] != tile) {
        parked.image.dispose();
        continue;
      }
      _install(tile, parked.image, parked.included);
      if (tile.needsRender) _request(tile.index, 0); // Strokes appended since.
    }
    _parked.clear();
  }

  void _install(InkTile tile, ui.Image image, int included) {
    pool.remove(tile);
    tile.image?.dispose();
    tile
      ..image = image
      ..stale = false
      ..edited = false
      ..overlay.removeRange(0, included)
      // Underlays make the image stale: it was rendered afresh, with them.
      ..underlay.clear();
    pool.add(tile);
    _notify();
  }
}
