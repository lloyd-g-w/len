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

  /// Device pixels of [rects] (world) within the view's clip.
  static double _pixels(List<ui.Rect> rects, TileView view) {
    var sum = 0.0;
    for (final rect in rects) {
      final area = view.clip == null ? rect : rect.intersect(view.clip!);
      if (!area.isEmpty) sum += area.width * area.height * view.k * view.k;
    }
    return sum;
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

  static final ui.Paint _exactPaint = ui.Paint()..filterQuality = ui.FilterQuality.none;
  static final ui.Paint _scaledPaint = ui.Paint()..filterQuality = ui.FilterQuality.medium;

  void _drawImage(ui.Canvas canvas, ui.Image image, ui.Rect dst, {required bool exact}) {
    final src = ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    canvas.drawImageRect(image, src, dst, exact ? _exactPaint : _scaledPaint);
  }

  /// Draws the tiles of the previous space over [rect] (scaled); returns
  /// the parts of [rect] they do not cover.
  List<ui.Rect> _drawOld(ui.Canvas canvas, TileView view, ui.Rect rect) {
    final old = _oldSpace;
    if (old == null) return [rect];
    final uncovered = <ui.Rect>[];
    var clipped = false;
    for (final index in old.covering(rect)) {
      final tile = _old[index];
      final image = tile?.image;
      if (tile == null || (image == null && tile.blank != true)) {
        uncovered.add(old.worldRectOf(index).intersect(rect));
        continue;
      }
      if (image == null) continue; // Blank.
      if (!clipped) {
        clipped = true;
        canvas
          ..save()
          ..clipRect(view.toDevice(rect));
      }
      _drawImage(canvas, image, view.toDevice(old.worldRectOf(index)), exact: false);
      pool.touch(tile);
      lastPaint.images++;
    }
    if (clipped) canvas.restore();
    return uncovered;
  }

  void _drawOverlay(ui.Canvas canvas, TileView view, InkTile tile) {
    var rect = tile.space.worldRectOf(tile.index);
    if (_clip != null) rect = rect.intersect(_clip!);
    canvas
      ..save()
      ..clipRect(view.toDevice(rect))
      ..translate(view.origin.dx, view.origin.dy)
      ..scale(view.k);
    for (final stroke in tile.overlay) {
      StrokeRenderer.draw(canvas, stroke);
    }
    lastPaint.overlayStrokes += tile.overlay.length;
    canvas.restore();
  }

  void _prune() {
    _tiles.removeWhere(
      (index, tile) =>
          tile.image == null &&
          tile.parked == null &&
          !tile.rendering &&
          tile.overlay.isEmpty &&
          !_requests.containsKey(index),
    );
  }

  // ---------------------------------------------------------------------------
  // Spaces

  void _scheduleSettle(TileSpace target) {
    _pendingSpace = target;
    _settle?.cancel();
    _settle = Timer(settleDelay, () {
      _settle = null;
      final next = _pendingSpace;
      if (next == null || _disposed) return;
      _adopt(next);
      _notify();
    });
  }

  /// Makes [space] current; today's tiles stand in until it is rendered.
  void _adopt(TileSpace space) {
    _releaseAll(_old);
    _old = {
      for (final e in _tiles.entries)
        if ((e.value.image != null || e.value.blank == true) &&
            e.value.overlay.isEmpty &&
            !e.value.stale)
          e.key: e.value,
    };
    _releaseAll({
      for (final e in _tiles.entries)
        if (!_old.containsKey(e.key)) e.key: e.value,
    });
    _oldSpace = _space;
    _space = space;
    _tiles = {};
    _requests.clear();
  }

  // ---------------------------------------------------------------------------
  // Invalidation

  void _onChange(SurfaceChange change) {
    final chunks = change.chunks;
    if (chunks == null) {
      _dropAll();
      _notify();
      return;
    }
    final areas = change.areas ?? [for (final c in chunks) ChunkGrid.rectOf(c)];
    // Tiles of the previous zoom no longer show the content.
    for (final tile in _touching(_old, areas)) {
      _old.remove(tile.index);
      tile.release();
    }
    final appended = change.appended;
    if (appended != null && _space != null) {
      for (final stroke in appended) {
        final bounds = _clip == null ? stroke.bounds : stroke.bounds.intersect(_clip!);
        if (bounds.isEmpty) continue;
        for (final index in _space!.covering(bounds)) {
          final tile = _tiles[index] ??= InkTile(pool, _space!, index);
          tile
            ..overlay.add(stroke)
            ..blank = false;
          if (_inUse) _request(index, 0);
        }
      }
      return;
    }
    final hit = _touching(_tiles, areas);
    if (change.loaded) {
      // Stored content arrived: it was not on screen before, so nothing
      // the user did lingers while the old images stand in.
      _restale(hit, 1);
    } else if (hit.where((t) => t.image != null).length <= maxVectorTiles) {
      for (final tile in hit) {
        tile
          ..invalidate()
          ..edited = true;
      }
    } else {
      // A large edit (undo of a lasso move, say): rather than frames of
      // vectors over much of the screen, the old images stay until the new
      // ones, all rendered at once, replace them together a frame or two
      // later (see [_flushBatch]).
      _restale(hit, 0);
    }
  }

  /// Edits over at most this many tiles drop their images (drawn as vectors
  /// until rendered: shown at once); larger ones keep them as stand-ins.
  static const int maxVectorTiles = 2;

  /// The tiles of [tiles] overlapping any of [areas].
  List<InkTile> _touching(Map<TileIndex, InkTile> tiles, List<ui.Rect> areas) {
    if (tiles.isEmpty || areas.isEmpty) return const [];
    return [
      for (final tile in tiles.values)
        if (areas.any(tile.space.worldRectOf(tile.index).overlaps)) tile,
    ];
  }

  /// Tiles whose content changed keep showing their image until rendered
  /// again (requested at [priority]); those without one are invalidated.
  void _restale(List<InkTile> tiles, int priority) {
    for (final tile in tiles) {
      if (tile.image == null) {
        final edited = tile.edited || priority == 0;
        tile
          ..invalidate()
          ..edited = edited;
        continue;
      }
      tile
        ..dropParked()
        ..version += 1
        ..stale = true
        // Strokes appended since, unless erased or hidden by this change.
        ..overlay.removeWhere((s) => model.strokeById(s.id) != s || model.isHidden(s.id));
      tile.batched = priority == 0;
      if (_inUse) _request(tile.index, priority);
    }
  }

  void _dropAll() {
    _releaseAll(_tiles);
    _releaseAll(_old);
    _tiles = {};
    _old = {};
    _oldSpace = null;
    _space = null;
    _requests.clear();
  }

  void _releaseAll(Map<TileIndex, InkTile> tiles) {
    for (final tile in tiles.values) {
      tile.release();
    }
  }

  // ---------------------------------------------------------------------------
  // Rendering

  void _request(TileIndex index, int priority) {
    if (_disposed) return;
    final current = _requests[index];
    if (current != null && current <= priority) return;
    _requests[index] = priority;
    _schedulePump();
  }

  void _schedulePump() {
    if (_pumpTimer != null || _disposed) return;
    // After the frame being built (painting requests renders).
    _pumpTimer = Timer(Duration.zero, _pump);
  }

  void _pump() {
    _pumpTimer = null;
    if (_disposed || _space == null) return;
    final watch = Stopwatch()..start();
    while (_requests.isNotEmpty && watch.elapsed < batchBudget) {
      final index = _next();
      // Urgent renders (edits on screen) all start at once.
      if (_inFlight >= maxInFlight && _requests[index]! > 0) break;
      _requests.remove(index);
      final tile = _tiles[index] ??= InkTile(pool, _space!, index);
      if (tile.rendering) continue; // Requested again when it completes.
      tile.blank ??= model.chunksIn(ChunkGrid.rangeFor(tile.space.worldRectOf(index))).isEmpty;
      if (!tile.needsRender) continue;
      _render(tile);
    }
    _flushBatch();
  }

  /// The most urgent request (lowest priority value, newest first).
  TileIndex _next() {
    TileIndex? best;
    var bestPriority = 1 << 30;
    for (final e in _requests.entries) {
      if (e.value <= bestPriority) {
        best = e.key;
        bestPriority = e.value;
      }
    }
    return best!;
  }

  void _render(InkTile tile) {
    developer.Timeline.startSync('len.renderTile');
    final space = tile.space;
    final rect = space.worldRectOf(tile.index);
    final clipped = _clip == null ? rect : rect.intersect(_clip!);
    final included = tile.overlay.length;
    // A stale image is rendered afresh (the chunk pictures hold everything).
    final base = tile.stale ? null : tile.image;
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder);
    if (base != null) canvas.drawImage(base, ui.Offset.zero, _exactPaint);
    canvas
      ..translate(
        space.phase.dx - tile.index.x * TileSpace.size,
        space.phase.dy - tile.index.y * TileSpace.size,
      )
      ..scale(space.k)
      ..clipRect(clipped);
    if (base != null) {
      // Incremental: the strokes appended since [base] was rendered.
      for (final stroke in tile.overlay) {
        StrokeRenderer.draw(canvas, stroke);
      }
      PerfProbe.count('tileAppends');
    } else {
      // Chunk pictures hold everything committed so far, overlay included.
      for (final key in model.chunksIn(ChunkGrid.rangeFor(clipped))) {
        canvas.drawPicture(pictures.pictureFor(key));
      }
      PerfProbe.count('tileRenders');
    }
    final picture = recorder.endRecording();
    developer.Timeline.finishSync();
    final version = tile.version;
    tile.rendering = true;
    _inFlight++;
    unawaited(
      picture
          .toImage(TileSpace.size, TileSpace.size)
          .then(
            (image) => _store(tile, version, included, image),
            onError: (Object error, StackTrace stack) => FlutterError.reportError(
              FlutterErrorDetails(exception: error, stack: stack, library: 'len rendering'),
            ),
          )
          .whenComplete(() {
            picture.dispose();
            tile.rendering = false;
            _inFlight--;
            if (!_disposed && tile.needsRender && _tiles[tile.index] == tile) {
              _request(tile.index, tile.overlay.isEmpty ? 1 : 0);
            }
            _flushBatch();
            _schedulePump();
          }),
    );
  }

  void _store(InkTile tile, int version, int included, ui.Image image) {
    if (_disposed || tile.version != version || _tiles[tile.index] != tile) {
      image.dispose(); // Changed (or gone) while rendering.
      return;
    }
    if (tile.batched) {
      // Shown with the rest of its edit's tiles.
      tile.parked?.image.dispose();
      tile.parked = (image: image, version: version, included: included);
      _parked.add(tile);
      return;
    }
    _install(tile, image, included);
  }

  /// Tiles rendered for a large edit, waiting for the rest of it.
  final List<InkTile> _parked = [];

  /// Shows the images rendered for a large edit together, once none of its
  /// tiles is still waiting for a render, so the edit never shows half
  /// done.
  void _flushBatch() {
    if (_parked.isEmpty) return;
    for (final tile in _tiles.values) {
      if (tile.batched && (tile.rendering || _requests.containsKey(tile.index))) return;
    }
    for (final tile in _tiles.values) {
      tile.batched = false;
    }
    for (final tile in _parked) {
      final parked = tile.parked;
      tile.parked = null;
      if (parked == null) continue; // Released meanwhile.
      if (_disposed || tile.version != parked.version || _tiles[tile.index] != tile) {
        parked.image.dispose();
        continue;
      }
      _install(tile, parked.image, parked.included);
      if (tile.needsRender) _request(tile.index, 0); // Strokes appended since.
    }
    _parked.clear();
  }

  void _install(InkTile tile, ui.Image image, int included) {
    pool.remove(tile);
    tile.image?.dispose();
    tile
      ..image = image
      ..stale = false
      ..edited = false
      ..overlay.removeRange(0, included);
    pool.add(tile);
    _notify();
  }

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
