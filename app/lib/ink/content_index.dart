import 'dart:ui';

import '../domain/chunk_grid.dart';
import 'spatial_index.dart';

/// In-memory items of one kind (strokes or elements) by id, with a sparse
/// chunk index over their bounds.
class ContentIndex<T> {
  ContentIndex({required this.idOf, required this.boundsOf});

  final String Function(T) idOf;
  final Rect Function(T) boundsOf;

  final Map<String, T> _items = {};
  final SpatialIndex _index = SpatialIndex();

  int get length => _items.length;

  T? operator [](String id) => _items[id];

  bool containsId(String id) => _items.containsKey(id);

  /// Inserts [item], replacing any item with the same id.
  void insert(T item) {
    final previous = _items[idOf(item)];
    if (previous != null) remove(previous);
    _items[idOf(item)] = item;
    _index.insert(idOf(item), boundsOf(item));
  }

  void remove(T item) {
    _items.remove(idOf(item));
    _index.remove(idOf(item), boundsOf(item));
  }

  void clear() {
    _items.clear();
    _index.clear();
  }

  List<ChunkKey> populatedIn(ChunkRange range) => _index.populatedIn(range);

  Iterable<T> inChunk(ChunkKey key) => _index.idsIn(key).map((id) => _items[id] as T);

  /// Items whose chunks overlap [rect] (a candidate set for precise tests).
  Iterable<T> query(Rect rect) => _index.query(rect).map((id) => _items[id] as T);
}
