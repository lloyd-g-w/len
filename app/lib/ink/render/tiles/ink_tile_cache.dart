import 'dart:async';
import 'dart:developer' as developer;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../../domain/chunk_grid.dart';
import '../../../domain/stroke.dart';
import '../../lab/perf_probe.dart';
import '../../surface_model.dart';
import '../chunk_picture_cache.dart';
import '../stroke_renderer.dart';
import 'tile_pool.dart';
import 'tile_space.dart';

/// Draws ink as vectors into the given world rectangles (clipped to them),
/// where no tile image can stand in yet.
typedef VectorFallback = void Function(ui.Canvas canvas, List<ui.Rect> world);

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
/// - **Other edits** (erasing, undo, loads, selections) drop the tiles they
///   touch; those areas are drawn as vectors until rendered again.
/// - **Zooming and panning** by fractions of a pixel draw the existing tiles
///   transformed; once the view has been still for [settleDelay] the new
///   space is adopted and rendered, with the old tiles standing in until
///   then.
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

  /// Tile renders running at once.
  final int maxInFlight;

  /// Time one batch of render recordings may take before yielding.
  final Duration batchBudget;

  SurfaceModel get model => pictures.model;

  late final StreamSubscription<SurfaceChange> _subscription;
  TileSpace? _space;
  TileSpace? _pendingSpace;
  Timer? _settle;
  Map<TileIndex, _Tile> _tiles = {};

  /// Tiles of the space before [_space], standing in until it is rendered.
  TileSpace? _oldSpace;
  Map<TileIndex, _Tile> _old = {};
  ui.Rect? _clip;

  /// Requested renders of [_space] tiles: index → priority (lower first).
  final Map<TileIndex, int> _requests = {};
  int _inFlight = 0;
  Timer? _pumpTimer;
  bool _notifyScheduled = false;
  bool _disposed = false;

  /// What the last [paint] drew (tests and the perf probe).
  final TilePaintStats lastPaint = TilePaintStats();

  /// Whether renders are queued or running.
  bool get isBusy => _requests.isNotEmpty || _inFlight > 0 || _settle != null;

  /// Tile images held.
  int get imageCount => _tiles.values.where((t) => t.image != null).length;

  /// Paints the ink in [view] onto [canvas], which must be in device
  /// pixels (the view's origin relative to it).
  void paint(ui.Canvas canvas, TileView view, VectorFallback fallback) {
    lastPaint.reset();
    if (view.clip != _clip) {
      _dropAll();
      _clip = view.clip;
    }
    final target = view.space;
    final space = _space ??= target;
    final same = space.matches(target);
    if (same) {
      _settle?.cancel();
      _settle = null;
    } else {
      _scheduleSettle(target);
    }
    final area = view.clip == null ? view.visible : view.visible.intersect(view.clip!);
    if (area.isEmpty) return;
    // Moving keeps rendering the current space (its tiles stay useful);
    // zooming waits for the new one.
    final canRender = same || target.k == space.k;
    final missing = <ui.Rect>[];
    final overlays = <_Tile>[];
    for (final index in space.covering(area)) {
      final tile = _tiles[index] ??= _Tile(this, space, index);
      final rect = space.worldRectOf(index);
      tile.blank ??= model.chunksIn(ChunkGrid.rangeFor(rect)).isEmpty;
      if (tile.blank! && tile.overlay.isEmpty) continue;
      final image = tile.image;
      if (image != null) {
        final dst = same
            ? ui.Rect.fromLTWH(
                index.x * TileSpace.size + view.origin.dx.floorToDouble(),
                index.y * TileSpace.size + view.origin.dy.floorToDouble(),
                TileSpace.size.toDouble(),
                TileSpace.size.toDouble(),
              )
            : view.toDevice(rect);
        _drawImage(canvas, image, dst, exact: same);
        pool.touch(tile);
        lastPaint.images++;
        if (tile.overlay.isNotEmpty) overlays.add(tile);
        continue;
      }
      if (canRender) _request(index, 1);
      if (_drawOld(canvas, view, rect)) continue;
      missing.add(rect);
    }
    if (missing.isNotEmpty) {
      lastPaint.vectorTiles = missing.length;
      fallback(canvas, missing);
    }
    for (final tile in overlays) {
      _drawOverlay(canvas, view, tile);
    }
    if (same && _settle == null) {
      for (final index in space.covering(area.inflate(TileSpace.size / space.k))) {
        if (!_tiles.containsKey(index) || _tiles[index]!.needsRender) _request(index, 2);
      }
    }
    PerfProbe.count('tileImages', lastPaint.images);
    PerfProbe.count('tileVector', lastPaint.vectorTiles);
    PerfProbe.count('tileOverlays', lastPaint.overlayStrokes);
  }

  static final ui.Paint _exactPaint = ui.Paint()..filterQuality = ui.FilterQuality.none;
  static final ui.Paint _scaledPaint = ui.Paint()..filterQuality = ui.FilterQuality.medium;

  void _drawImage(ui.Canvas canvas, ui.Image image, ui.Rect dst, {required bool exact}) {
    final src = ui.Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
    canvas.drawImageRect(image, src, dst, exact ? _exactPaint : _scaledPaint);
  }

  /// Draws tiles of the previous space over [rect] if they cover all of it.
  bool _drawOld(ui.Canvas canvas, TileView view, ui.Rect rect) {
    final old = _oldSpace;
    if (old == null) return false;
    final tiles = <_Tile>[];
    for (final index in old.covering(rect)) {
      final tile = _old[index];
      if (tile == null || tile.overlay.isNotEmpty) return false;
      if (tile.image == null && tile.blank != true) return false;
      tiles.add(tile);
    }
    canvas
      ..save()
      ..clipRect(view.toDevice(rect));
    for (final tile in tiles) {
      final image = tile.image;
      if (image == null) continue;
      _drawImage(canvas, image, view.toDevice(old.worldRectOf(tile.index)), exact: false);
      pool.touch(tile);
      lastPaint.images++;
    }
    canvas.restore();
    return true;
  }

  void _drawOverlay(ui.Canvas canvas, TileView view, _Tile tile) {
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
        if ((e.value.image != null || e.value.blank == true) && e.value.overlay.isEmpty)
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
    final appended = change.appended;
    if (appended != null && _space != null) {
      for (final stroke in appended) {
        final bounds = _clip == null ? stroke.bounds : stroke.bounds.intersect(_clip!);
        if (bounds.isEmpty) continue;
        for (final index in _space!.covering(bounds)) {
          final tile = _tiles[index] ??= _Tile(this, _space!, index);
          tile
            ..overlay.add(stroke)
            ..blank = false;
          _request(index, 0);
        }
      }
      _dropTouching(_old, chunks, all: true);
      return;
    }
    _dropTouching(_tiles, chunks);
    _dropTouching(_old, chunks, all: true);
  }

  /// Drops the images of tiles overlapping [chunks] ([all]: forgets the
  /// tiles too).
  void _dropTouching(Map<TileIndex, _Tile> tiles, Set<ChunkKey> chunks, {bool all = false}) {
    if (tiles.isEmpty || chunks.isEmpty) return;
    final rects = [for (final c in chunks) ChunkGrid.rectOf(c)];
    final hit = [
      for (final tile in tiles.values)
        if (rects.any(tile.space.worldRectOf(tile.index).overlaps)) tile,
    ];
    for (final tile in hit) {
      if (all) {
        tiles.remove(tile.index);
        tile.release();
      } else {
        tile.invalidate();
      }
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

  void _releaseAll(Map<TileIndex, _Tile> tiles) {
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
    // While zooming, renders wait for the new space.
    if (_settle != null && _pendingSpace?.k != _space!.k) return;
    final watch = Stopwatch()..start();
    while (_requests.isNotEmpty && _inFlight < maxInFlight && watch.elapsed < batchBudget) {
      final index = _next();
      _requests.remove(index);
      final tile = _tiles[index] ??= _Tile(this, _space!, index);
      if (tile.rendering) continue; // Requested again when it completes.
      tile.blank ??= model.chunksIn(ChunkGrid.rangeFor(tile.space.worldRectOf(index))).isEmpty;
      if (!tile.needsRender) continue;
      _render(tile);
    }
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

  void _render(_Tile tile) {
    developer.Timeline.startSync('len.renderTile');
    final space = tile.space;
    final rect = space.worldRectOf(tile.index);
    final clipped = _clip == null ? rect : rect.intersect(_clip!);
    final included = tile.overlay.length;
    final base = tile.image;
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
            _schedulePump();
          }),
    );
  }

  void _store(_Tile tile, int version, int included, ui.Image image) {
    if (_disposed || tile.version != version || _tiles[tile.index] != tile) {
      image.dispose(); // Changed (or gone) while rendering.
      return;
    }
    pool.remove(tile);
    tile.image?.dispose();
    tile
      ..image = image
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

/// Counts of what one [InkTileCache.paint] drew.
class TilePaintStats {
  int images = 0;
  int vectorTiles = 0;
  int overlayStrokes = 0;

  void reset() => images = vectorTiles = overlayStrokes = 0;
}

class _Tile implements PooledTile {
  _Tile(this.owner, this.space, this.index);

  final InkTileCache owner;
  final TileSpace space;
  final TileIndex index;

  ui.Image? image;

  /// Whether no ink is under the tile (null: not checked yet).
  bool? blank;

  /// Pen strokes appended since [image] was rendered, in paint order.
  final List<Stroke> overlay = [];

  /// Bumped when the content changes in other ways than appends, so a
  /// render in flight is discarded.
  int version = 0;
  bool rendering = false;

  bool get needsRender => image == null ? blank != true || overlay.isNotEmpty : overlay.isNotEmpty;

  @override
  int get bytes => TileSpace.size * TileSpace.size * 4;

  /// Content changed: the image is stale.
  void invalidate() {
    version++;
    blank = null;
    overlay.clear();
    _dropImage();
  }

  /// The tile is forgotten.
  void release() {
    version++;
    overlay.clear();
    _dropImage();
  }

  @override
  void evict() {
    image?.dispose();
    image = null;
    // An evicted tile with pending strokes is rendered in full next time.
  }

  void _dropImage() {
    if (image == null) return;
    owner.pool.remove(this);
    image!.dispose();
    image = null;
  }
}
