import 'dart:async';
import 'dart:developer' as developer;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../../domain/chunk_grid.dart';
import '../../lab/perf_probe.dart';
import '../../surface_model.dart';
import '../chunk_picture_cache.dart';
import '../stroke_renderer.dart';
import 'ink_tile.dart';
import 'tile_pool.dart';
import 'tile_space.dart';

export 'ink_tile.dart' show TilePaintStats;

part 'ink_tile_cache_drawing.dart';
part 'ink_tile_cache_invalidation.dart';
part 'ink_tile_cache_rendering.dart';

/// Draws ink as vectors in [view] into the given world rectangles (clipped
/// to them), where no tile image can stand in yet.
typedef VectorFallback = void Function(ui.Canvas canvas, TileView view, List<ui.Rect> world);

/// A raster cache of a surface's committed ink: the screen is split into
/// [TileSpace.size]² device-pixel tiles rendered to GPU images at the
/// current zoom, so a frame draws a few dozen images instead of replaying
/// every outline. Impeller has no raster cache of its own: without this,
/// every frame — every pen move — re-tessellated all the ink on screen.
///
/// - **Appends** (a new pen stroke over everything in its chunks, see
///   [SurfaceChange.appended]) keep the tiles: the stroke is drawn as a
///   vector over them until each tile is re-rendered as [old image + the
///   stroke], off the frame. So a committed stroke never disappears.
/// - **Loads** ([SurfaceChange.loaded]) keep the images of the tiles they
///   touch as stale stand-ins until those are rendered again.
/// - **Other edits** (erasing, undo, selections) drop the tiles they
///   touch; those areas are drawn as vectors until rendered again.
/// - **Panning** keeps the tiles, by fractions of a pixel too (the view is
///   aligned to them, see [TileView.alignedTo]); tiles coming into view are
///   rendered ahead, a ring around the screen.
/// - **Zooming** draws the existing tiles scaled, rendering only those
///   missing on screen, until the view has been still for [settleDelay]:
///   then the new zoom is adopted and rendered, with the old tiles standing
///   in until then. Zooming out further than [maxZoomOut] adopts the
///   current zoom at once (fewer, larger tiles than the old zoom needs).
///   Once zoomed, areas no tile covers yet stay empty until rendered (a
///   frame or two) instead of being drawn from vectors; edits always are.
///
/// Rendering is asynchronous ([ui.Picture.toImage]), newest and most
/// urgent first, a few at a time. Images live in a [TilePool] (LRU by
/// bytes) shared by all surfaces.
class InkTileCache extends ChangeNotifier {
  InkTileCache(
    this.pictures, {
    TilePool? pool,
    this.settleDelay = const Duration(milliseconds: 150),
    this.maxInFlight = 2,
    this.batchBudget = const Duration(milliseconds: 4),
  }) : pool = pool ?? TilePool.shared {
    _subscription = pictures.model.changes.listen(_onChange);
  }

  /// The vector source of tile renders.
  final ChunkPictureCache pictures;
  final TilePool pool;

  /// How long the view must stay still before tiles are re-rendered for it.
  final Duration settleDelay;

  /// Tile renders running at once (more for edits on screen).
  final int maxInFlight;

  /// Time one batch of render recordings may take before yielding.
  final Duration batchBudget;

  SurfaceModel get model => pictures.model;

  late final StreamSubscription<SurfaceChange> _subscription;
  TileSpace? _space;
  TileSpace? _pendingSpace;
  Timer? _settle;
  Map<TileIndex, InkTile> _tiles = {};

  /// Tiles of the space before [_space], standing in until it is rendered.
  TileSpace? _oldSpace;
  Map<TileIndex, InkTile> _old = {};
  ui.Rect? _clip;

  /// Requested renders of [_space] tiles: index → priority (lower first).
  final Map<TileIndex, int> _requests = {};
  int _inFlight = 0;
  Timer? _pumpTimer;
  bool _notifyScheduled = false;
  bool _disposed = false;

  /// Time since [paint] last ran: a cache not painted lately (its view is
  /// zoomed out to level-of-detail images, or gone) renders nothing on
  /// edits — it keeps their strokes as overlays until painted again —
  /// so it never competes with the raster thread for what is on screen.
  final Stopwatch _sincePaint = Stopwatch();

  /// How far a view may zoom out from the tiles' zoom before it is adopted
  /// mid-gesture.
  static const double maxZoomOut = 1.5;

  /// How recently the cache must have been painted to render on edits.
  static const Duration inUseFor = Duration(milliseconds: 500);

  bool get _inUse => _sincePaint.isRunning && _sincePaint.elapsed < inUseFor;

  /// What the last [paint] drew (tests and the perf probe).
  final TilePaintStats lastPaint = TilePaintStats();

  /// Whether renders are queued or running.
  bool get isBusy => _requests.isNotEmpty || _inFlight > 0 || _settle != null;

  /// Tile renders running.
  @visibleForTesting
  int get rendering => _inFlight;

  /// Tiles known (with or without an image).
  @visibleForTesting
  int get tileCount => _tiles.length;

  /// Tiles known beyond which those without an image or pending work are
  /// forgotten (panning far would otherwise pile them up).
  static const int maxTiles = 256;

  /// Tile images held.
  int get imageCount => _tiles.values.where((t) => t.image != null).length;

  /// Renders the tiles of [view] ahead of time, after those the screen
  /// waits for: [view] is about to come into view (a page below the
  /// screen). Nothing is drawn; the surface must have finished loading.
  void prefetch(TileView view) {
    if (view.clip != _clip) {
      _dropAll();
      _clip = view.clip;
    }
    final space = _space ??= view.space;
    if (!space.matches(view.space) || model.isLoading) return;
    final area = view.clip == null ? view.visible : view.visible.intersect(view.clip!);
    if (area.isEmpty) return;
    for (final index in space.covering(area)) {
      final tile = _tiles[index];
      if (tile == null || tile.needsRender) _request(index, 2);
    }
  }

  /// Paints the ink in [view] onto [canvas], which must be in device
  /// pixels (the view's origin relative to it).
  void paint(ui.Canvas canvas, TileView view, VectorFallback fallback) {
    lastPaint.reset();
    _sincePaint
      ..reset()
      ..start();
    if (view.clip != _clip) {
      _dropAll();
      _clip = view.clip;
    }
    final target = view.space;
    var space = _space ??= target;
    if (!space.matches(target) && target.k * maxZoomOut < space.k) {
      _adopt(target); // Zoomed far out: the old tiles cover too little.
      space = target;
    }
    final same = space.matches(target);
    if (same) {
      _settle?.cancel();
      _settle = null;
      view = view.alignedTo(space);
    } else {
      _scheduleSettle(target);
    }
    final area = view.clip == null ? view.visible : view.visible.intersect(view.clip!);
    if (area.isEmpty) return;
    // Requests for tiles the view has moved away from are dropped (edits'
    // stay: they may be on screen again soon).
    final ring = area.inflate(TileSpace.size / space.k);
    _requests.removeWhere((index, p) => p > 0 && !space.worldRectOf(index).overlaps(ring));
    // Where tile (0, 0) of [space] sits, on whole device pixels.
    final x0 = (view.origin.dx - space.phase.dx).roundToDouble();
    final y0 = (view.origin.dy - space.phase.dy).roundToDouble();
    final missing = <ui.Rect>[];
    final overlays = <InkTile>[];
    for (final index in space.covering(area)) {
      final tile = _tiles[index] ??= InkTile(pool, space, index);
      final rect = space.worldRectOf(index);
      tile.blank ??= model.chunksIn(ChunkGrid.rangeFor(rect)).isEmpty;
      if (tile.blank! && tile.overlay.isEmpty) continue;
      final image = tile.image;
      if (image != null) {
        final dst = same
            ? ui.Rect.fromLTWH(
                index.x * TileSpace.size + x0,
                index.y * TileSpace.size + y0,
                TileSpace.size.toDouble(),
                TileSpace.size.toDouble(),
              )
            : view.toDevice(rect);
        _drawImage(canvas, image, dst, exact: same);
        pool.touch(tile);
        lastPaint.images++;
        if (tile.stale) {
          lastPaint.staleImages++;
          _request(index, 1);
        }
        if (tile.overlay.isNotEmpty) overlays.add(tile);
        continue;
      }
      _request(index, 1);
      if (tile.edited) {
        missing.add(rect); // Shown as it now is at once.
        continue;
      }
      final uncovered = _drawOld(canvas, view, rect);
      if (_oldSpace == null) {
        missing.addAll(uncovered); // A first show.
      } else {
        // Not rendered since a zoom (a rim zooming out exposed): empty
        // for the frame or two until it is, rather than a frame of
        // vectors.
        lastPaint.blankPixels += _pixels(uncovered, view);
      }
    }
    if (missing.isNotEmpty) {
      lastPaint
        ..vectorTiles = missing.length
        ..vectorPixels = _pixels(missing, view);
      fallback(canvas, view, missing);
    }
    for (final tile in overlays) {
      _drawOverlay(canvas, view, tile);
    }
    // Tiles about to come into view: around the screen (panning, zooming
    // out), rendered after the visible ones.
    if (target.k <= space.k) {
      for (final index in space.covering(ring)) {
        if (!_tiles.containsKey(index) || _tiles[index]!.needsRender) _request(index, 2);
      }
    }
    if (_tiles.length > maxTiles) _prune();
    PerfProbe.count('tileImages', lastPaint.images);
    PerfProbe.count('tileVector', lastPaint.vectorTiles);
    PerfProbe.count('tileOverlays', lastPaint.overlayStrokes);
  }

  /// Draws, scaled into [view], what the tiles hold of [world] that is up
  /// to date (images of this or the previous zoom; no stale ones), as a
  /// stand-in while zoomed out to level-of-detail rasters that are not
  /// made yet. Renders and requests nothing; returns the parts of [world]
  /// not covered.
  List<ui.Rect> paintStandIn(ui.Canvas canvas, TileView view, ui.Rect world) {
    final space = _space;
    if (space == null || view.clip != _clip) return [world];
    final area = view.clip == null ? world : world.intersect(view.clip!);
    if (area.isEmpty) return const [];
    final uncovered = <ui.Rect>[];
    for (final index in space.covering(area)) {
      final rect = space.worldRectOf(index).intersect(area);
      final tile = _tiles[index];
      final image = tile?.image;
      if (tile != null && image != null && !tile.stale) {
        _drawImage(canvas, image, view.toDevice(space.worldRectOf(index)), exact: false);
        if (tile.overlay.isNotEmpty) _drawOverlay(canvas, view, tile);
        lastPaint.images++;
      } else if (tile == null || tile.blank != true || tile.overlay.isNotEmpty) {
        uncovered.addAll(_drawOld(canvas, view, rect));
      }
    }
    return uncovered;
  }

  /// Edits over at most this many tiles drop their images (drawn as vectors
  /// until rendered: shown at once); larger ones keep them as stand-ins.
  static const int maxVectorTiles = 2;

  /// Tiles rendered for a large edit, waiting for the rest of it.
  final List<InkTile> _parked = [];

  void _notify() {
    if (_notifyScheduled || _disposed) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  @override
  void dispose() {
    _disposed = true;
    _settle?.cancel();
    _pumpTimer?.cancel();
    unawaited(_subscription.cancel());
    _releaseAll(_tiles);
    _releaseAll(_old);
    _tiles = {};
    _old = {};
    super.dispose();
  }
}
