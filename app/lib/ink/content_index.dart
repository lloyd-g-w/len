import 'dart:ui';

import '../domain/chunk_grid.dart';
import 'spatial_index.dart';

/// In-memory items of one kind (strokes or elements) by id, with a sparse
/// chunk index.
///
/// Each item is indexed in exactly the chunks [chunksOf] returns — the same
/// function the storage index uses (`StrokeChunks.of` / `ElementChunks.of`),
/// so memory and storage always agree on which chunks an item populates.
class ContentIndex<T> {
  ContentIndex({required this.idOf, required this.chunksOf});

  final String Function(T) idOf;
  final Iterable<ChunkKey> Function(T) chunksOf;

  final Map<String, T> _items = {};
  final SpatialIndex _index = SpatialIndex();

  int get length => _items.length;

  T? operator [](String id) => _items[id];

  bool containsId(String id) => _items.containsKey(id);

  /// Inserts [item], replacing any item with the same id.
  void insert(T item) {
    remove(item);
    _items[idOf(item)] = item;
    _index.insertAt(idOf(item), chunksOf(item));
  }

  /// Removes the item with [item]'s id (unindexing the stored instance, so
  /// a stale copy with other geometry cannot leave index entries behind).
  void remove(T item) {
    final id = idOf(item);
    final stored = _items.remove(id);
    if (stored != null) _index.removeAt(id, chunksOf(stored));
  }

  void clear() {
    _items.clear();
    _index.clear();
  }

  Iterable<T> get all => _items.values;

  List<ChunkKey> populatedIn(ChunkRange range) => _index.populatedIn(range);

  Iterable<T> inChunk(ChunkKey key) => _index.idsIn(key).map((id) => _items[id] as T);

  /// Items indexed in chunks overlapping [rect] (a candidate set for
  /// precise tests).
  Iterable<T> query(Rect rect) => _index.query(rect).map((id) => _items[id] as T);
}
