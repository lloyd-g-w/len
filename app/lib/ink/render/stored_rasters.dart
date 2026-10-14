import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/raster_store.dart';
import '../../domain/chunk_digest.dart';
import '../../domain/chunk_grid.dart';
import '../surface_model.dart';
import 'stored_raster_io.dart';

/// Level-of-detail rasters of a surface's chunks kept across restarts, so
/// a canvas reopened far zoomed out shows its ink from a few small images
/// instead of loading and rasterising every chunk (`ChunkRasterCache`).
///
/// Rasters are stored by content: the name holds the chunk, the level and
/// the chunk's [ChunkDigest]. Storage keeps digests per chunk without
/// loading anything ([SurfaceModel.storedDigests]), memory computes them
/// from the items ([SurfaceModel.digestOf]); the same digest means the
/// same content, so a raster found is right — whatever was edited, undone
/// or synced since, by whichever device. Nothing needs invalidating:
/// changed chunks just have new names, and old rasters age out of the
/// store's budget.
class StoredRasters {
  StoredRasters(this.model, this.store, {required this.onChanged});

  /// Version of how chunks are drawn; bump it when rendering changes
  /// (pens, text, layering), so rasters drawn before are not shown.
  static const int format = 2;

  /// The finest level stored (a view coarser than this one reads chunks
  /// from storage; finer views load them anyway).
  static const int maxLevel = 128;

  final SurfaceModel model;
  final RasterStore store;

  /// Called when stored digests arrive (the view should repaint).
  final VoidCallback onChanged;

  /// Digests of the populated chunks in [_range], as stored; null for
  /// chunks changed in memory since (see [forget]).
  Map<ChunkKey, ChunkDigest?> _digests = const {};
  ChunkRange? _range;
  ChunkRange? _queued;
  bool _querying = false;
  int _generation = 0;
  bool _disposed = false;

  /// Reads and writes the files.
  late final StoredRasterIo io = StoredRasterIo(store);

  /// The stored chunks within [range], asking storage for the digests
  /// around it when [range] goes beyond those known.
  Iterable<ChunkKey> chunksIn(ChunkRange range) {
    final known = _range;
    if (known == null || !_covers(known, range)) {
      // Not while painting: asking writes pending edits first.
      scheduleMicrotask(() {
        if (!_disposed) _query(range);
      });
    }
    return [
      for (final key in _digests.keys)
        if (range.contains(key)) key,
    ];
  }

  /// [key]'s digest as stored, if known and not changed in memory since.
  ChunkDigest? digestOf(ChunkKey key) => _digests[key];

  /// Whether storage held content in [key] when last asked (it may be
  /// in memory only in part).
  bool isStored(ChunkKey key) => _digests.containsKey(key);

  static bool _covers(ChunkRange a, ChunkRange b) =>
      a.minX <= b.minX && a.minY <= b.minY && a.maxX >= b.maxX && a.maxY >= b.maxY;

  void _query(ChunkRange range) {
    // A margin, so panning a little asks nothing.
    final wanted = ChunkRange(range.minX - 2, range.minY - 2, range.maxX + 2, range.maxY + 2);
    if (_querying) {
      _queued = wanted;
      return;
    }
    _querying = true;
    _range = wanted;
    final generation = _generation;
    FutureOr<Map<ChunkKey, ChunkDigest>> result;
    try {
      result = model.storedDigests(wanted);
    } on Object catch (error, stack) {
      _querying = false;
      return _report(error, stack);
    }
    void done(Map<ChunkKey, ChunkDigest> digests) {
      _querying = false;
      if (_disposed) return;
      if (generation == _generation) {
        _digests = digests;
        onChanged();
      } else {
        _range = null; // Edited meanwhile: ask again.
      }
      final queued = _queued;
      _queued = null;
      if (queued != null && (_range == null || !_covers(_range!, queued))) _query(queued);
    }

    if (result is Map<ChunkKey, ChunkDigest>) {
      done(result); // Synchronous readers (tests).
    } else {
      result.then(
        done,
        onError: (Object error, StackTrace stack) {
          _querying = false;
          _report(error, stack);
        },
      );
    }
  }

  /// Forgets the stored digests of [chunks] (edited in memory; null:
  /// everything, e.g. after a sync), asking storage again when next
  /// needed. They still count as stored ([isStored]).
  void forget(Set<ChunkKey>? chunks) {
    _generation++;
    _range = null;
    if (chunks == null) {
      _digests = const {};
    } else if (chunks.any(_digests.containsKey)) {
      _digests = {
        for (final MapEntry(:key, :value) in _digests.entries)
          key: chunks.contains(key) ? null : value,
      };
    }
  }

  /// The name of [chunk]'s raster at [level] for content [digest].
  String nameOf(ChunkKey chunk, int level, ChunkDigest digest) =>
      '${model.surfaceId}_${chunk.x}_${chunk.y}_${level}_${digest.name}.png';

  void dispose() {
    _disposed = true;
    io.dispose();
  }

  void _report(Object error, StackTrace stack) => FlutterError.reportError(
    FlutterErrorDetails(exception: error, stack: stack, library: 'len rendering'),
  );
}
