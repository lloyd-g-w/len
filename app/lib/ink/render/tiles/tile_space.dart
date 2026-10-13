import 'dart:ui';

/// A tile's position in its [TileSpace] grid.
typedef TileIndex = ({int x, int y});

/// The device-pixel grid committed ink is rasterised on, at one zoom.
///
/// A world point `w` lands on device pixel `w * k + origin` on screen
/// (`k` = device pixels per world unit, `origin` = where the world origin
/// is). Tiles are [size]-pixel squares of the grid `w * k + phase`, where
/// [phase] is the fractional part of the origin the space was made for:
/// every tile sits on whole device pixels on screen, so a tile image shows
/// exactly what drawing the vectors would. Panning keeps the space (and
/// its tiles) — by a fraction of a pixel too: the view is then drawn
/// aligned to the space ([TileView.alignedTo]), off by under half a device
/// pixel, rather than every tile re-rendered for the new fraction. Only
/// zooming makes a new space.
class TileSpace {
  const TileSpace(this.k, this.phase);

  /// The space for a view with world origin at device pixel [origin].
  factory TileSpace.of(double k, Offset origin) => TileSpace(
    k,
    Offset(origin.dx - origin.dx.floorToDouble(), origin.dy - origin.dy.floorToDouble()),
  );

  /// Tile edge in device pixels.
  static const int size = 512;

  /// Device pixels per world unit.
  final double k;

  /// Sub-pixel offset of the grid, each coordinate in [0, 1).
  final Offset phase;

  /// Whether tiles of this space serve a view of [other]'s zoom unscaled.
  bool matches(TileSpace other) => k == other.k;

  /// The world rectangle tile [t] covers.
  Rect worldRectOf(TileIndex t) =>
      Rect.fromLTWH((t.x * size - phase.dx) / k, (t.y * size - phase.dy) / k, size / k, size / k);

  /// The tiles covering [world] (row by row).
  Iterable<TileIndex> covering(Rect world) sync* {
    final x0 = ((world.left * k + phase.dx) / size).floor();
    final y0 = ((world.top * k + phase.dy) / size).floor();
    final x1 = ((world.right * k + phase.dx) / size).ceil();
    final y1 = ((world.bottom * k + phase.dy) / size).ceil();
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        yield (x: x, y: y);
      }
    }
  }

  @override
  String toString() => 'TileSpace(k: $k, phase: $phase)';
}

/// Where a surface's world is on screen, in device pixels.
class TileView {
  const TileView({required this.k, required this.origin, required this.visible, this.clip});

  /// Device pixels per world unit.
  final double k;

  /// Device pixel (relative to the canvas) of the world origin.
  final Offset origin;

  /// The world rectangle on screen.
  final Rect visible;

  /// World clip (a page), if any.
  final Rect? clip;

  TileSpace get space => TileSpace.of(k, origin);

  /// This view moved by under half a device pixel so that [space]'s tiles
  /// sit on whole device pixels in it (same zoom: [TileSpace.matches]).
  TileView alignedTo(TileSpace space) {
    final dx = (origin.dx - space.phase.dx).roundToDouble() + space.phase.dx;
    final dy = (origin.dy - space.phase.dy).roundToDouble() + space.phase.dy;
    return TileView(k: k, origin: Offset(dx, dy), visible: visible, clip: clip);
  }

  /// The device rectangle of the world rectangle [world].
  Rect toDevice(Rect world) => Rect.fromLTRB(
    world.left * k + origin.dx,
    world.top * k + origin.dy,
    world.right * k + origin.dx,
    world.bottom * k + origin.dy,
  );
}
