part of 'chunk_raster_cache.dart';

/// Where a [ChunkRasterCache]'s rasters come from when the surface keeps
/// them across restarts ([StoredRasters]): chunks storage holds more of
/// than memory are read from the store, by content digest.
extension _Storage on ChunkRasterCache {
  /// Whether the stale image of [key] shows what its chunk holds now,
  /// by digest; it is then marked current.
  bool _sameContent(_Key key) {
    final shown = _imageDigests[key];
    final version = _versionOf(key.chunk);
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
  void _request(_Key key) {
    final stored = _stored;
    final chunk = key.chunk;
    if (stored == null || !stored.isStored(chunk) || _model.isComplete(chunk)) {
      return _enqueue(key);
    }
    final digest = stored.digestOf(chunk);
    if (digest != null && key.level <= StoredRasters.maxLevel) {
      final name = stored.nameOf(chunk, key.level, digest);
      if (_reads.contains(name)) return;
      if (!_misses.contains(name)) return _read(key, name, digest);
    }
    _notStored(key);
  }

  void _read(_Key key, String name, ChunkDigest digest) {
    _reads.add(name);
    final version = _versionOf(key.chunk);
    unawaited(
      _stored!.read(name).then((image) {
        _reads.remove(name);
        if (image != null) {
          // Still right if the chunk's stored content is: loads around it
          // (strokes reaching into it) change nothing stored.
          final same = _stored?.digestOf(key.chunk) == digest;
          return _store(key, same ? _versionOf(key.chunk) : version, image, digest: digest);
        }
        _misses.add(name);
        if (!_disposed) _notStored(key);
      }),
    );
  }

  /// [key] has no stored raster: its chunk is read from storage to make
  /// one, and rasterised as far as it is in memory if nothing stands in.
  void _notStored(_Key key) {
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
    if (!hasImage && inMemory) _enqueue(key);
  }
}
