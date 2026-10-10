import 'dart:ui';

/// Integer coordinates of a square chunk of world space.
typedef ChunkKey = ({int x, int y});

/// An inclusive rectangular range of chunk keys.
class ChunkRange {
  const ChunkRange(this.minX, this.minY, this.maxX, this.maxY);

  final int minX, minY, maxX, maxY;

  int get count => (maxX - minX + 1) * (maxY - minY + 1);

  bool contains(ChunkKey key) => key.x >= minX && key.x <= maxX && key.y >= minY && key.y <= maxY;

  Iterable<ChunkKey> get keys sync* {
    for (var y = minY; y <= maxY; y++) {
      for (var x = minX; x <= maxX; x++) {
        yield (x: x, y: y);
      }
    }
  }

  @override
  bool operator ==(Object other) =>
      other is ChunkRange &&
      other.minX == minX &&
      other.minY == minY &&
      other.maxX == maxX &&
      other.maxY == maxY;

  @override
  int get hashCode => Object.hash(minX, minY, maxX, maxY);

  @override
  String toString() => 'ChunkRange($minX,$minY → $maxX,$maxY)';
}

/// Partitions the (unbounded) world plane into square chunks.
///
/// Chunks are the unit of lazy loading, spatial indexing and render caching
/// for surfaces. The grid is fixed, so every device computes identical keys.
abstract final class ChunkGrid {
  /// Edge length of a chunk in world units.
  static const double size = 512;

  static ChunkKey keyAt(double x, double y) => (x: (x / size).floor(), y: (y / size).floor());

  /// All chunks overlapping [rect] (edges inclusive).
  static ChunkRange rangeFor(Rect rect) {
    final min = keyAt(rect.left, rect.top);
    final max = keyAt(rect.right, rect.bottom);
    return ChunkRange(min.x, min.y, max.x, max.y);
  }

  static Rect rectOf(ChunkKey key) => Rect.fromLTWH(key.x * size, key.y * size, size, size);
}
