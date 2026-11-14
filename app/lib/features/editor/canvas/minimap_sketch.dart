import 'dart:math' as math;
import 'dart:ui';

import '../../../data/stroke_reader.dart';
import '../../../domain/chunk_digest.dart';
import '../../../domain/chunk_grid.dart';
import '../../../domain/stroke.dart';
import '../../../domain/surface_element.dart';
import 'minimap_geometry.dart';

/// A group of [MinimapSketch.tileChunks]² chunks whose items the map
/// records into one picture.
typedef MinimapTile = ({int x, int y});

/// The whole of a canvas's content, lightly simplified, kept for its
/// minimap: strokes with fewer points (in their colours and widths),
/// elements as they are, grouped into tiles.
///
/// [update] brings it up to date with storage incrementally: it compares
/// every chunk's digest (`StrokeReader.chunkDigests`, one cheap query)
/// with the ones it last read and re-reads only the chunks that differ, a
/// batch at a time; the tiles whose items changed are reported dirty
/// ([takeDirty]) for their pictures to be recorded again. A canvas with
/// more than [maxItems] items keeps only the [blocks] (soft blocks by
/// density).
class MinimapSketch {
  MinimapSketch({this.maxItems = defaultMaxItems});

  /// Items (strokes and elements, counted per chunk) above which the map
  /// shows blocks instead of a miniature.
  final int maxItems;
  static const int defaultMaxItems = 40000;

  /// Chunks read at a time.
  static const int batchChunks = 96;

  /// Chunks along a tile's side.
  static const int tileChunks = 8;

  /// Strokes keep a point at least this far (world units, at least) from
  /// the last one kept; larger on vaster canvases.
  static const double minTolerance = 2;

  /// A stroke spanning more chunks than this is not indexed per chunk.
  static const int _maxIndexed = 1024;

  /// Every chunk float32 world coordinates reach (negated, not shifted:
  /// see `ThumbnailRenderer`).
  static const ChunkRange everywhere = ChunkRange(-(1 << 22), -(1 << 22), 1 << 22, 1 << 22);

  Map<ChunkKey, ChunkDigest> _digests = {};
  final Map<ChunkKey, Set<String>> _byChunk = {};
  final Set<String> _wide = {};
  final Map<String, Stroke> _strokes = {};
  final Map<String, SurfaceElement> _elements = {};
  final Map<MinimapTile, Set<String>> _byTile = {};
  final Set<MinimapTile> _dirty = {};
  double _tolerance = minTolerance;
  Rect? _bounds;
  bool _boundsStale = false;

  /// The content as blocks by density (always kept: it costs nothing).
  MinimapContent blocks = MinimapContent.empty;

  /// Whether the canvas holds too much for a miniature ([maxItems]).
  bool overBudget = false;

  /// Whether nothing is on the canvas.
  bool get isEmpty => blocks.isEmpty;

  /// Whether every item is read (not [overBudget], no update midway).
  bool get sketched => !overBudget && _complete && !isEmpty;
  bool _complete = false;

  /// The tiles holding items.
  Iterable<MinimapTile> get tiles => _byTile.keys;

  /// The tiles changed since the last call.
  Set<MinimapTile> takeDirty() {
    final dirty = {..._dirty};
    _dirty.clear();
    return dirty;
  }

  /// Marks every tile holding an image dirty (a bitmap finished decoding).
  void imagesChanged() {
    for (final e in _elements.values) {
      if (e.knownType == ElementType.image) _dirty.add(tileOf(e.bounds));
    }
  }

  /// The strokes and elements of [tile].
  ({List<Stroke> strokes, List<SurfaceElement> elements}) itemsOf(MinimapTile tile) {
    final strokes = <Stroke>[], elements = <SurfaceElement>[];
    for (final id in _byTile[tile] ?? const <String>{}) {
      if (_strokes[id] case final s?) strokes.add(s);
      if (_elements[id] case final e?) elements.add(e);
    }
    return (strokes: strokes, elements: elements);
  }

  /// A tile's side in world units.
  static const double tileSide = tileChunks * ChunkGrid.size;

  /// The world area of [tile].
  static Rect rectOf(MinimapTile tile) =>
      Rect.fromLTWH(tile.x * tileSide, tile.y * tileSide, tileSide, tileSide);

  /// The tile [bounds] belongs to (by its centre).
  static MinimapTile tileOf(Rect bounds) {
    final key = ChunkGrid.keyAt(bounds.center.dx, bounds.center.dy);
    return (x: (key.x / tileChunks).floor(), y: (key.y / tileChunks).floor());
  }

  /// The content's exact bounds (the populated chunks' while not sketched).
  Rect? get bounds {
    if (!sketched) return blocks.bounds;
    if (_boundsStale) {
      _boundsStale = false;
      Rect? b;
      for (final s in _strokes.values) {
        b = b == null ? s.bounds : b.expandToInclude(s.bounds);
      }
      for (final e in _elements.values) {
        b = b == null ? e.bounds : b.expandToInclude(e.bounds);
      }
      _bounds = b;
    }
    return _bounds ?? blocks.bounds;
  }

  /// Reads what changed in storage since the last update; [progress]
  /// after each batch read. Returns whether anything changed. One at a
  /// time (the caller waits for one before starting the next).
  Future<bool> update(StrokeReader reader, String surfaceId, {void Function()? progress}) async {
    final digests = await reader.chunkDigests(surfaceId, everywhere);
    final changed = <ChunkKey>{
      for (final MapEntry(:key, :value) in digests.entries)
        if (_digests[key] != value) key,
      for (final key in _digests.keys)
        if (!digests.containsKey(key)) key,
    };
    if (changed.isEmpty) return false;
    final density = {for (final MapEntry(:key, :value) in digests.entries) key: _count(value)};
    blocks = MinimapContent.fromDensity(density);
    if (density.values.fold(0, (a, b) => a + b) > maxItems) {
      _clear();
      overBudget = true;
      _digests = digests;
      return true;
    }
    if (overBudget) {
      overBudget = false;
      _digests = {};
      changed.addAll(digests.keys);
    }
    final extent = blocks.bounds?.longestSide ?? 0;
    _tolerance = math.max(minTolerance, extent / 4096);
    _drop(changed);
    _complete = false;
    final toRead = changed.where(digests.containsKey).toList()
      ..sort((a, b) => a.y != b.y ? a.y.compareTo(b.y) : a.x.compareTo(b.x));
    for (var i = 0; i < toRead.length; i += batchChunks) {
      final batch = toRead.sublist(i, math.min(toRead.length, i + batchChunks));
      final range = _rangeOf(batch);
      final wanted = batch.toSet();
      final skip = {
        for (final key in digests.keys)
          if (range.contains(key) && !wanted.contains(key)) key,
      };
      final load = await reader.read(surfaceId, range, skip: skip);
      load.strokes.forEach(_addStroke);
      load.elements.forEach(_addElement);
      for (final key in batch) {
        _digests[key] = digests[key]!;
      }
      progress?.call();
    }
    _complete = true;
    return true;
  }

  static int _count(ChunkDigest d) => d.strokes + d.elements;

  static ChunkRange _rangeOf(List<ChunkKey> keys) {
    var minX = keys.first.x, maxX = keys.first.x, minY = keys.first.y, maxY = keys.first.y;
    for (final k in keys) {
      minX = math.min(minX, k.x);
      maxX = math.max(maxX, k.x);
      minY = math.min(minY, k.y);
      maxY = math.max(maxY, k.y);
    }
    return ChunkRange(minX, minY, maxX, maxY);
  }

  void _clear() {
    _dirty.addAll(_byTile.keys);
    _digests = {};
    _complete = false;
    _byChunk.clear();
    _wide.clear();
    _strokes.clear();
    _elements.clear();
    _byTile.clear();
    _boundsStale = true;
  }

  /// Forgets every item indexed in [chunks] (they are read again).
  void _drop(Set<ChunkKey> chunks) {
    final ids = <String>{
      for (final key in chunks) ...?_byChunk[key],
      for (final id in _wide)
        if (_touches(_boundsOf(id)!, chunks)) id,
    };
    ids.forEach(_remove);
    for (final key in chunks) {
      _digests.remove(key);
    }
  }

  static bool _touches(Rect bounds, Set<ChunkKey> chunks) {
    final range = ChunkGrid.rangeFor(bounds);
    return chunks.any(range.contains);
  }

  Rect? _boundsOf(String id) => _strokes[id]?.bounds ?? _elements[id]?.bounds;

  void _remove(String id) {
    final bounds = _boundsOf(id);
    if (bounds == null) return;
    _strokes.remove(id);
    _elements.remove(id);
    if (!_wide.remove(id)) {
      _eachChunk(bounds, (key) {
        final set = _byChunk[key];
        if (set != null && set.remove(id) && set.isEmpty) _byChunk.remove(key);
      });
    }
    final tile = tileOf(bounds);
    final inTile = _byTile[tile];
    if (inTile != null && inTile.remove(id) && inTile.isEmpty) _byTile.remove(tile);
    _dirty.add(tile);
    _boundsStale = true;
  }

  void _index(String id, Rect bounds) {
    final range = ChunkGrid.rangeFor(bounds);
    if ((range.maxX - range.minX + 1) * (range.maxY - range.minY + 1) > _maxIndexed) {
      _wide.add(id);
    } else {
      _eachChunk(bounds, (key) => (_byChunk[key] ??= {}).add(id));
    }
    final tile = tileOf(bounds);
    (_byTile[tile] ??= {}).add(id);
    _dirty.add(tile);
    _boundsStale = true;
  }

  static void _eachChunk(Rect bounds, void Function(ChunkKey key) each) {
    final r = ChunkGrid.rangeFor(bounds);
    for (var y = r.minY; y <= r.maxY; y++) {
      for (var x = r.minX; x <= r.maxX; x++) {
        each((x: x, y: y));
      }
    }
  }

  void _addStroke(Stroke s) {
    // Read again with another chunk of the batch, or of an earlier one.
    _remove(s.id);
    _strokes[s.id] = simplify(s, _tolerance);
    _index(s.id, s.bounds);
  }

  void _addElement(SurfaceElement e) {
    _remove(e.id);
    _elements[e.id] = e;
    _index(e.id, e.bounds);
  }

  /// [s] with points at least [tolerance] apart (its ends kept), sharing
  /// everything else; [s] itself when there is nothing to drop.
  static Stroke simplify(Stroke s, double tolerance) {
    final points = s.points;
    if (points.length <= 4) return s;
    final kept = <StrokePoint>[points.first];
    final t2 = tolerance * tolerance;
    for (var i = 1; i < points.length - 1; i++) {
      final p = points[i], last = kept.last;
      final dx = p.x - last.x, dy = p.y - last.y;
      if (dx * dx + dy * dy >= t2) kept.add(p);
    }
    kept.add(points.last);
    if (kept.length == points.length) return s;
    return Stroke(
      id: s.id,
      surfaceId: s.surfaceId,
      tool: s.tool,
      color: s.color,
      width: s.width,
      points: kept,
      createdAt: s.createdAt,
      style: s.style,
      shape: s.shape,
      bounds: s.bounds,
    );
  }
}
