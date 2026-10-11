import 'dart:collection';

/// Something holding GPU memory that the [TilePool] may take back.
abstract class PooledTile {
  /// Bytes held (fixed while pooled).
  int get bytes;

  /// Called when the pool drops the tile: release its image.
  void evict();
}

/// One memory budget for the tile images of every surface on screen (all
/// pages of a document share it), least recently drawn evicted first.
class TilePool {
  TilePool({this.maxBytes = 160 << 20});

  /// The pool the editor's surfaces share.
  static final TilePool shared = TilePool();

  /// Upper bound on the bytes held by pooled tiles.
  final int maxBytes;

  final LinkedHashSet<PooledTile> _lru = LinkedHashSet.identity();
  int _bytes = 0;

  /// Bytes currently held.
  int get bytes => _bytes;

  /// Tiles currently held.
  int get length => _lru.length;

  /// Adds [tile] (most recently used) and evicts the oldest tiles while
  /// over budget.
  void add(PooledTile tile) {
    remove(tile);
    _lru.add(tile);
    _bytes += tile.bytes;
    while (_bytes > maxBytes && _lru.length > 1) {
      final oldest = _lru.first;
      remove(oldest);
      oldest.evict();
    }
  }

  /// Marks [tile] as just drawn.
  void touch(PooledTile tile) {
    if (_lru.remove(tile)) _lru.add(tile);
  }

  /// Forgets [tile] (its owner released it).
  void remove(PooledTile tile) {
    if (_lru.remove(tile)) _bytes -= tile.bytes;
  }
}
