/// How the input controller thins out stylus samples before they become
/// stroke points (shared with the low-latency overlay, which must make the
/// same choices to draw the same ink).
abstract final class PointSpacing {
  /// Points closer than this (screen px) to the previous kept one are
  /// dropped; it removes jitter without visible loss of detail.
  static const double minDistance = 0.75;

  /// A dropped point further than this (screen px) from the line between
  /// the points kept around it is kept after all: the tip of a cusp or a
  /// tight loop, where the pen slows down and turns.
  static const double keepExtreme = 0.3;
}
