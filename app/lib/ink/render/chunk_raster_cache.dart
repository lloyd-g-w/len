import 'dart:async';
import 'dart:collection';

import 'package:flutter/foundation.dart';

import '../../domain/chunk_digest.dart';
import '../../domain/chunk_grid.dart';
import '../../domain/stroke.dart';
import '../surface_model.dart';
import 'chunk_picture_cache.dart';
import 'chunk_rasteriser.dart';
import 'chunk_versions.dart';
import 'raster_batch.dart';
import 'stored_rasters.dart';

part 'chunk_raster_invalidation.dart';
part 'chunk_raster_storage.dart';

/// Level-of-detail rasters of chunks, for zoomed-out views.
///
/// When a chunk covers only a few hundred device pixels, replaying its
/// vector picture (every stroke outline) costs far more than the pixels it
/// produces. Instead the chunk is drawn from a small cached image, so the
/// cost of a zoomed-out frame depends on how many chunks are visible, not
/// on how much ink they hold.
///
/// Images are made lazily, off the critical path: [imageFor] only queues a
/// missing raster ([ChunkRasteriser]). Listeners are
/// notified when new images are ready. Edits invalidate rasters through the
/// same per-chunk stream as the vector pictures. Memory is bounded by an
/// LRU over [maxBytes]; evicted and stale images are disposed.
class ChunkRasterCache extends ChangeNotifier {
  ChunkRasterCache(
    this.pictures, {
    this.maxBytes = 64 << 20,
    Duration batchBudget = const Duration(milliseconds: 6),
    int? maxInFlight,
    RasterBatch? batch,
  }) {
    batch ??= RasterBatch.shared;
    _maker = ChunkRasteriser(
      pictures,
      versionOf: _versions.of,
      isWanted: (key, version) =>
          version == _versions.of(key.chunk) && _imageVersions[key] != version,
      storable: _storable,
      onImage: (key, version, image, digest) => _store(key, version, image, digest: digest),
      batchBudget: batchBudget,
      // Batched, as many as fit on an atlas: one read-back for them all.
      maxInFlight: maxInFlight ?? (batch.batching ? 256 : 8),
      batch: batch,
    );
    _subscription = pictures.model.changes.listen(_onChange);
    final store = pictures.model.rasterStore;
    if (store != null) {
      _stored = StoredRasters(pictures.model, store, onChanged: _scheduleNotify);
    }
  }

  final ChunkPictureCache pictures;

  SurfaceModel get _model => pictures.model;

  /// Rasters kept across restarts, if the surface has a store.
  StoredRasters? _stored;

  /// Upper bound on the memory held by cached images.
  final int maxBytes;

  /// Raster edge lengths in pixels, coarsest first.
  static const List<int> levels = [32, 64, 128, 256];

  /// The raster edge to draw a chunk with when it covers [devicePixels]
  /// pixels on screen, or null when it is large enough to need vectors.
  /// Always at least as fine as the screen, so rasters never look soft.
  static int? levelFor(double devicePixels) {
    for (final level in levels) {
      if (devicePixels <= level) return level;
    }
    return null;
  }

  final LinkedHashMap<RasterKey, RasterImage> _images = LinkedHashMap();
  late final ChunkRasteriser _maker;
  final ChunkVersions _versions = ChunkVersions();
  late final StreamSubscription<SurfaceChange> _subscription;
  int _bytes = 0;
  bool _notifyScheduled = false;
  bool _disposed = false;

  /// Images currently cached.
  int get length => _images.length;

  /// Bytes held by cached images.
  int get bytes => _bytes;

  /// Whether rasters are queued, being made or read, or wait to be
  /// stored.
  bool get isBusy => isMaking || (_stored?.io.saving ?? false);

  /// Whether rasters are queued, being made or read.
  bool get isMaking => _maker.isBusy || (_stored?.io.reading ?? false);

  /// Stored rasters found missing this session.
  final Set<String> _misses = {};

  /// Chunks to read from storage (no raster stored), asked for together.
  final Set<ChunkKey> _toLoad = {};

  /// Content digest each cached image shows, when known: a stale image
  /// whose chunk turns out to hold the same content again (it finished
  /// loading, an edit was undone) is current without rasterising.
  final Map<RasterKey, ChunkDigest> _imageDigests = {};

  /// The content version a stale image's digest was last compared at.
  final Map<RasterKey, int> _digestChecked = {};

  /// The populated chunks within [range]: those in memory and, while the
  /// model shows stored rasters ([SurfaceModel.showStored]), those in
  /// storage.
  /// Painters call this once per frame with what they show.
  List<ChunkKey> chunksIn(ChunkRange range) {
    final inMemory = _model.chunksIn(range);
    final stored = _stored;
    if (stored == null) return inMemory;
    stored.io
      ..view = range
      ..noteActivity();
    if (!_model.showsStored) return inMemory;
    return {...inMemory, ...stored.chunksIn(range)}.toList();
  }

  /// Content version each cached image was made from.
  final Map<RasterKey, int> _imageVersions = {};

  /// Whether [chunk], having no image at any level, must be drawn from its
  /// vectors: it was edited since (an erased stroke must not linger, a new
  /// one must show at once). Others may wait for their raster, drawn from
  /// a stand-in or not at all for a frame or two.
  bool needsVectors(ChunkKey chunk) => _versions.edited.contains(chunk);

  /// Strokes added to [chunk] after [image] (as returned by [imageFor])
  /// was made, to draw with it: pen strokes over it, highlighter strokes
  /// beneath it (as the pen ink covers them).
  List<Stroke> overlayOf(ChunkKey chunk, RasterImage image) {
    for (final level in levels) {
      final key = (chunk: chunk, level: level);
      if (identical(_images[key], image)) return _versions.overlay(chunk, _imageVersions[key] ?? 0);
    }
    return _versions.overlay(chunk, 0);
  }

  /// The raster of [chunk] at [level], or the nearest other level cached
  /// (a stand-in until the right one is made); null if none is cached.
  /// Queues the requested level if it is missing or stale (then strokes
  /// appended since must be drawn over it, see [overlayOf]). Safe to call
  /// while painting: it never notifies synchronously.
  RasterImage? imageFor(ChunkKey chunk, int level) {
    final key = (chunk: chunk, level: level);
    final exact = _images.remove(key);
    if (exact != null) {
      _images[key] = exact; // Most recently used.
      if ((_imageVersions[key] ?? 0) != _versions.of(chunk) && !_sameContent(key)) {
        _request(key); // Stale.
      }
      return exact;
    }
    _request(key);
    RasterImage? best;
    var bestDistance = 1 << 30;
    for (final other in levels) {
      final image = _images[(chunk: chunk, level: other)];
      if (image != null && (other - level).abs() < bestDistance) {
        best = image;
        bestDistance = (other - level).abs();
      }
    }
    return best;
  }

  /// The finest raster of [chunk] cached at any level, without asking for
  /// one (null: none): a stand-in where the tiles that take over from the
  /// level of detail (zooming in) are not rendered yet. Strokes added
  /// since go with it ([overlayOf]).
  RasterImage? peekFinest(ChunkKey chunk) {
    for (final level in levels.reversed) {
      final image = _images[(chunk: chunk, level: level)];
      if (image != null) return image;
    }
    return null;
  }

  /// Caches [image] as [key]'s raster of content [version] (showing
  /// content [digest], if known); with [keep], a copy goes to storage.
  void _store(
    RasterKey key,
    int version,
    RasterImage image, {
    ChunkDigest? digest,
    bool keep = true,
  }) {
    if (keep && digest != null && !_disposed && image.whole) {
      // Stored even if the chunk changed meanwhile: it shows [digest].
      _stored!.io.write(_stored!.nameOf(key.chunk, key.level, digest), image.image.clone());
    }
    if (_disposed || version != _versions.of(key.chunk)) {
      image.dispose(); // The chunk changed while it was being rasterised.
      return;
    }
    final previous = _images.remove(key);
    if (previous != null) {
      _bytes -= previous.bytes;
      previous.dispose();
    }
    _images[key] = image;
    _imageVersions[key] = version;
    _forgetDigest(key);
    if (digest != null) _imageDigests[key] = digest;
    _bytes += image.bytes;
    _versions.edited.remove(key.chunk);
    _trimOverlay(key.chunk);
    while (_bytes > maxBytes && _images.length > 1) {
      final oldest = _images.keys.first;
      final image = _images.remove(oldest)!;
      _bytes -= image.bytes;
      image.dispose();
      _imageVersions.remove(oldest);
      _forgetDigest(oldest);
      _trimOverlay(oldest.chunk);
    }
    _scheduleNotify();
  }

  void _forgetDigest(RasterKey key) {
    _imageDigests.remove(key);
    _digestChecked.remove(key);
  }

  void _scheduleNotify() {
    if (_notifyScheduled) return;
    _notifyScheduled = true;
    scheduleMicrotask(() {
      _notifyScheduled = false;
      if (!_disposed) notifyListeners();
    });
  }

  /// Forgets overlay strokes every cached image of [chunk] includes.
  void _trimOverlay(ChunkKey chunk) {
    var oldest = 1 << 50;
    for (final level in levels) {
      final made = _imageVersions[(chunk: chunk, level: level)];
      if (made != null && made < oldest) oldest = made;
    }
    _versions.trim(chunk, oldest);
  }

  @override
  void dispose() {
    _disposed = true;
    _stored?.dispose();
    _maker.dispose();
    unawaited(_subscription.cancel());
    _clear();
    super.dispose();
  }
}
