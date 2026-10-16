part of 'chunk_raster_cache.dart';

/// How edits and loads reach [ChunkRasterCache]'s images.
extension _RasterInvalidation on ChunkRasterCache {
  /// The surface changed: rasters of the chunks it touched go stale
  /// (appends and loads keep theirs as stand-ins) or are dropped.
  void _onChange(SurfaceChange change) {
    // New pen strokes go over the images, new highlights beneath them.
    final appended = change.appended ?? change.underlaid;
    final chunks = change.chunks;
    if (!change.loaded) _stored?.forget(chunks);
    if (change.loaded && chunks != null) {
      // Stored content arrived: the images (and their overlays) stand in,
      // stale, until new ones are made — no vector frames while a canvas
      // loads.
      for (final chunk in chunks) {
        _versions.bump(chunk, keepOverlay: true);
      }
      return;
    }
    if (appended == null || chunks == null) return _invalidate(chunks);
    for (final chunk in chunks) {
      final version = _versions.bump(chunk, keepOverlay: true);
      if (ChunkRasterCache.levels.any((l) => _images.containsKey((chunk: chunk, level: l)))) {
        final rect = ChunkGrid.rectOf(chunk);
        _versions.append(chunk, version, appended.where((s) => s.bounds.overlaps(rect)));
      } else {
        _versions.edited.add(chunk);
      }
    }
  }

  /// Drops the rasters of [chunks] (null: all), drawn from vectors until
  /// made again.
  void _invalidate(Set<ChunkKey>? chunks) {
    if (chunks == null) {
      _versions
        ..bumpAll()
        // What was on screen may have changed anywhere.
        ..edited.addAll([for (final key in _images.keys) key.chunk]);
      _clear();
      return;
    }
    for (final chunk in chunks) {
      _versions
        ..bump(chunk)
        ..edited.add(chunk);
      for (final level in ChunkRasterCache.levels) {
        _imageVersions.remove((chunk: chunk, level: level));
        _forgetDigest((chunk: chunk, level: level));
        final image = _images.remove((chunk: chunk, level: level));
        if (image == null) continue;
        _bytes -= image.bytes;
        image.dispose();
      }
    }
  }

  /// Disposes every image and queued raster.
  void _clear() {
    _imageVersions.clear();
    _imageDigests.clear();
    _digestChecked.clear();
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    _maker.clear();
    _bytes = 0;
  }
}
