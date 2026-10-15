part of 'chunk_raster_cache.dart';

/// Where a [ChunkRasterCache]'s rasters come from when the surface keeps
/// them across restarts ([StoredRasters]): chunks storage holds more of
/// than memory are read from the store, by content digest.
extension _Storage on ChunkRasterCache {
  /// The digest a raster of [key] about to be made shows, if it may be
  /// stored: its picture's look must not depend on images still decoding.
  ChunkDigest? _storable(RasterKey key) {
    if (_stored == null || key.level > StoredRasters.maxLevel) return null;
    _stored!.io.noteActivity();
    return pictures.isSettled(key.chunk) ? _model.digestOf(key.chunk) : null;
  }

  /// Whether the stale image of [key] shows what its chunk holds now,
  /// by digest; it is then marked current.
  bool _sameContent(RasterKey key) {
    final shown = _imageDigests[key];
    final version = _versions.of(key.chunk);
    if (shown == null || _digestChecked[key] == version) return false;
    _digestChecked[key] = version;
    if (_model.digestOf(key.chunk) != shown) return false;
    _imageVersions[key] = version;
    _trimOverlay(key.chunk);
    return true;
  }

  /// Gets a raster of [key] made. A chunk storage holds more of than
  /// memory does is read from the store if a raster of its stored content
  /// is there, else loaded (its stale image standing in meanwhile, or a
  /// partial one made if it has none); others are rasterised.
  void _request(RasterKey key) {
    final stored = _stored;
    final chunk = key.chunk;
    if (stored == null || !stored.isStored(chunk) || _model.isComplete(chunk)) {
      return _maker.request(key);
    }
    final digest = stored.digestOf(chunk);
    if (digest != null && key.level <= StoredRasters.maxLevel) {
      final name = stored.nameOf(chunk, key.level, digest);
      if (stored.io.isReading(name)) return;
      if (!_misses.contains(name)) return _read(key, name, digest);
    }
    _notStored(key);
  }

  /// Queues reading [key]'s raster [name] (see [StoredRasterIo]).
  void _read(RasterKey key, String name, ChunkDigest digest) {
    final version = _versions.of(key.chunk);
    _stored!.io.read(name, key.chunk, (image) {
      if (_disposed) return image?.dispose();
      if (image != null) {
        // Still right if the chunk's stored content is: loads around it
        // (strokes reaching into it) change nothing stored.
        final same = _stored?.digestOf(key.chunk) == digest;
        final at = same ? _versions.of(key.chunk) : version;
        return _store(key, at, RasterImage(image), digest: digest, keep: false);
      }
      _misses.add(name);
      _notStored(key);
    });
  }

  /// [key] has no stored raster: its chunk is read from storage to make
  /// one, and rasterised as far as it is in memory if nothing stands in.
  void _notStored(RasterKey key) {
    if (_disposed) return;
    final chunk = key.chunk;
    if (_toLoad.isEmpty) {
      scheduleMicrotask(() {
        if (!_disposed) _model.requestChunks(_toLoad);
        _toLoad.clear();
      });
    }
    _toLoad.add(chunk);
    final hasImage = ChunkRasterCache.levels.any(
      (l) => _images.containsKey((chunk: chunk, level: l)),
    );
    final inMemory = _model.chunksIn(ChunkRange(chunk.x, chunk.y, chunk.x, chunk.y)).isNotEmpty;
    if (!hasImage && inMemory) _maker.request(key);
  }
}
