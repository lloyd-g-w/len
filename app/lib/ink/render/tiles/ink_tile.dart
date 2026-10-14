import 'dart:ui' as ui;

import '../../../domain/stroke.dart';
import 'tile_pool.dart';
import 'tile_space.dart';

/// Counts of what one [InkTileCache.paint] drew.
class TilePaintStats {
  int images = 0;
  int vectorTiles = 0;
  int overlayStrokes = 0;
  int underlayStrokes = 0;

  /// Images drawn that predate a change (standing in until re-rendered).
  int staleImages = 0;

  /// Screen area (device pixels) left empty until its tiles are rendered.
  double blankPixels = 0;

  /// Screen area (device pixels) drawn from vectors.
  double vectorPixels = 0;

  void reset() {
    images = vectorTiles = overlayStrokes = underlayStrokes = staleImages = 0;
    vectorPixels = blankPixels = 0;
  }
}

/// One tile of an [InkTileCache] (its state; the cache does the work).
class InkTile implements PooledTile {
  InkTile(this.pool, this.space, this.index);

  /// Where [image] is accounted for.
  final TilePool pool;
  final TileSpace space;
  final TileIndex index;

  ui.Image? image;

  /// Whether no ink is under the tile (null: not checked yet).
  bool? blank;

  /// Pen strokes appended since [image] was rendered, in paint order.
  final List<Stroke> overlay = [];

  /// Highlighter strokes added since [image] was rendered (which is then
  /// stale): drawn beneath it until the tile is rendered again.
  final List<Stroke> underlay = [];

  /// Bumped when the content changes in other ways than appends, so a
  /// render in flight is discarded.
  int version = 0;
  bool rendering = false;

  /// Whether [image] predates stored content that arrived since (it stands
  /// in until the tile is rendered again).
  bool stale = false;

  /// Whether the image was dropped by an edit since the tile was last
  /// rendered: until it is again, only vectors show it as it is.
  bool edited = false;

  /// Whether the next render is part of a large edit's batch (see
  /// InkTileCache's batches).
  bool batched = false;

  /// An image rendered for the batch, waiting to be shown.
  ({ui.Image image, int version, int included})? parked;

  bool get needsRender =>
      parked == null &&
      (image == null ? blank != true || overlay.isNotEmpty : overlay.isNotEmpty || stale);

  @override
  int get bytes => TileSpace.size * TileSpace.size * 4;

  /// Content changed: the image is stale.
  void invalidate() {
    dropParked();
    version++;
    blank = null;
    stale = false;
    overlay.clear();
    underlay.clear();
    _dropImage();
  }

  /// The tile is forgotten.
  void release() {
    dropParked();
    version++;
    stale = false;
    overlay.clear();
    underlay.clear();
    _dropImage();
  }

  @override
  void evict() {
    image?.dispose();
    image = null;
    stale = false;
    underlay.clear(); // Only ever drawn beneath an image.
    // An evicted tile with pending strokes is rendered in full next time.
  }

  /// Forgets the image waiting in [parked].
  void dropParked() {
    parked?.image.dispose();
    parked = null;
    batched = false;
  }

  void _dropImage() {
    if (image == null) return;
    pool.remove(this);
    image!.dispose();
    image = null;
  }
}
