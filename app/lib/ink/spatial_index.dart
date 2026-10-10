import 'dart:ui';

import '../domain/chunk_grid.dart';

/// Sparse in-memory chunk index: maps each populated chunk to the ids of the
/// strokes overlapping it. Empty space costs nothing, which is what makes
/// the infinite canvas cheap regardless of how far apart content is.
class SpatialIndex {
  final Map<ChunkKey, Set<String>> _chunks = {};

  int get chunkCount => _chunks.length;

  void insert(String id, Rect bounds) {
    for (final key in ChunkGrid.rangeFor(bounds).keys) {
      (_chunks[key] ??= <String>{}).add(id);
    }
  }

  void remove(String id, Rect bounds) {
    for (final key in ChunkGrid.rangeFor(bounds).keys) {
      final ids = _chunks[key];
      if (ids == null) continue;
      ids.remove(id);
      if (ids.isEmpty) _chunks.remove(key);
    }
  }

  void clear() => _chunks.clear();

  /// Ids of strokes in [key]; empty if the chunk is unpopulated.
  Set<String> idsIn(ChunkKey key) => _chunks[key] ?? const {};

  /// Populated chunks within [range]. Iterates whichever is smaller — the
  /// range or the populated set — so huge zoomed-out ranges stay cheap.
  List<ChunkKey> populatedIn(ChunkRange range) {
    if (range.count <= _chunks.length) {
      return [for (final key in range.keys) if (_chunks.containsKey(key)) key];
    }
    return [for (final key in _chunks.keys) if (range.contains(key)) key];
  }

  /// Ids of strokes whose chunks overlap [rect] (a candidate set — callers
  /// do precise tests themselves).
  Set<String> query(Rect rect) => {
        for (final key in populatedIn(ChunkGrid.rangeFor(rect))) ..._chunks[key]!,
      };
}
