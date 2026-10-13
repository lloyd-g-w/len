import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../domain/chunk_digest.dart';
import '../../domain/chunk_grid.dart';
import '../../domain/stroke.dart';
import '../lab/perf_probe.dart';
import '../surface_model.dart';
import 'chunk_picture_cache.dart';
import 'stored_rasters.dart';

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
/// missing raster; queued chunks are recorded in short time-boxed batches
/// (one per event-loop turn, most recently requested first) and
/// rasterised asynchronously with [ui.Picture.toImage]. Listeners are
/// notified when new images are ready. Edits invalidate rasters through the
/// same per-chunk stream as the vector pictures. Memory is bounded by an
/// LRU over [maxBytes]; evicted and stale images are disposed.
class ChunkRasterCache extends ChangeNotifier {
  ChunkRasterCache(
    this.pictures, {
    this.maxBytes = 64 << 20,
    this.batchBudget = const Duration(milliseconds: 6),
    this.maxInFlight = 8,
  }) {
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

  /// Time a batch of recordings may take before yielding.
  final Duration batchBudget;

  /// Rasterisations running at once.
  final int maxInFlight;

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

  final LinkedHashMap<_Key, ui.Image> _images = LinkedHashMap();
  final LinkedHashMap<_Key, int> _queue = LinkedHashMap();

  /// Content version per chunk; any change gets a fresh number from
  /// [_counter], and chunks without an entry are at [_epoch].
  final Map<ChunkKey, int> _versions = {};
  int _counter = 0;
  int _epoch = 0;
  late final StreamSubscription<SurfaceChange> _subscription;

  /// Pen strokes appended to a chunk since its (now stale) images were
  /// made, with the content version that added them; drawn over the
  /// images until fresh ones arrive (see [overlayOf]).
  final Map<ChunkKey, List<(int, Stroke)>> _overlays = {};
  int _bytes = 0;
  int _inFlight = 0;

  /// Rasters being made, with the content version they are made from, so
  /// a chunk requested again on every frame is not rasterised twice.
  final Map<_Key, int> _pending = {};
  Timer? _timer;
  bool _notifyScheduled = false;
  bool _disposed = false;

  /// Images currently cached.
  int get length => _images.length;

  /// Bytes held by cached images.
  int get bytes => _bytes;

  /// Whether rasters are queued, being made, read or written.
  bool get isBusy =>
      _queue.isNotEmpty || _inFlight > 0 || _reads.isNotEmpty || (_stored?.writing ?? 0) > 0;

  /// Stored rasters being read, by name.
  final Set<String> _reads = {};

  /// Stored rasters found missing this session.
  final Set<String> _misses = {};

  /// Chunks to read from storage (no raster stored), asked for together.
  final Set<ChunkKey> _toLoad = {};

  /// Content digest each cached image shows, when known: a stale image
  /// whose chunk turns out to hold the same content again (it finished
  /// loading, an edit was undone) is current without rasterising.
  final Map<_Key, ChunkDigest> _imageDigests = {};

  /// The content version a stale image's digest was last compared at.
  final Map<_Key, int> _digestChecked = {};

  /// The populated chunks within [range]: those in memory and, while the
  /// model shows stored rasters ([SurfaceModel.showStored]), those in
  /// storage.
  List<ChunkKey> chunksIn(ChunkRange range) {
    final inMemory = _model.chunksIn(range);
    final stored = _stored;
    if (stored == null || !_model.showsStored) return inMemory;
    return {...inMemory, ...stored.chunksIn(range)}.toList();
  }

  /// Content version each cached image was made from.
  final Map<_Key, int> _imageVersions = {};

  /// Chunks edited (not just loaded) while they had no image: until one is
  /// made, only their vectors show them as they are ([needsVectors]).
  final Set<ChunkKey> _edited = {};

  /// Whether [chunk], having no image at any level, must be drawn from its
  /// vectors: it was edited since (an erased stroke must not linger, a new
  /// one must show at once). Others may wait for their raster, drawn from
  /// a stand-in or not at all for a frame or two.
  bool needsVectors(ChunkKey chunk) => _edited.contains(chunk);

  /// Strokes to draw over [image] (as returned by [imageFor] for [chunk]):
  /// those appended after it was made.
  List<Stroke> overlayOf(ChunkKey chunk, ui.Image image) {
    final overlay = _overlays[chunk];
    if (overlay == null) return const [];
    final made = _madeFrom(chunk, image);
    return [
      for (final (version, s) in overlay)
        if (version > made) s,
    ];
  }

  int _madeFrom(ChunkKey chunk, ui.Image image) {
    for (final level in levels) {
      final key = (chunk: chunk, level: level);
      if (identical(_images[key], image)) return _imageVersions[key] ?? 0;
    }
    return 0;
  }

  /// The raster of [chunk] at [level], or the nearest other level cached
  /// (a stand-in until the right one is made); null if none is cached.
  /// Queues the requested level if it is missing or stale (then strokes
  /// appended since must be drawn over it, see [overlayOf]). Safe to call
  /// while painting: it never notifies synchronously.
  ui.Image? imageFor(ChunkKey chunk, int level) {
    final key = (chunk: chunk, level: level);
    final exact = _images.remove(key);
    if (exact != null) {
      _images[key] = exact; // Most recently used.
      if ((_imageVersions[key] ?? 0) != _versionOf(chunk) && !_sameContent(key)) {
        _request(key); // Stale.
      }
      return exact;
    }
    _request(key);
    ui.Image? best;
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

  void _enqueue(_Key key) {
    if (_disposed) return;
    _queue
      ..remove(key)
      ..[key] = _versionOf(key.chunk);
    // Requests from long ago are for views that are gone.
    while (_queue.length > 4096) {
      _queue.remove(_queue.keys.first);
    }
    _timer ??= Timer(Duration.zero, _processBatch);
  }

  int _versionOf(ChunkKey chunk) => _versions[chunk] ?? _epoch;

  void _processBatch() {
    _timer = null;
    if (_disposed) return;
    final watch = Stopwatch()..start();
    while (_queue.isNotEmpty && _inFlight < maxInFlight && watch.elapsed < batchBudget) {
      final key = _queue.keys.last; // Newest request first: what is on screen now.
      final version = _queue.remove(key)!;
      if (version != _versionOf(key.chunk) || _imageVersions[key] == version) continue;
      if (_pending[key] == version) continue;
      _rasterise(key, version);
    }
    if (_queue.isNotEmpty && _inFlight < maxInFlight) {
      _timer = Timer(Duration.zero, _processBatch);
    }
  }

  void _rasterise(_Key key, int version) {
    final level = key.level;
    // What the raster will show, if it may be stored.
    final digest = _stored != null && level <= StoredRasters.maxLevel
        ? _model.digestOf(key.chunk)
        : null;
    final recorder = ui.PictureRecorder();
    final rect = ChunkGrid.rectOf(key.chunk);
    ui.Canvas(recorder)
      ..scale(level / ChunkGrid.size)
      ..translate(-rect.left, -rect.top)
      ..drawPicture(pictures.pictureFor(key.chunk));
    final picture = recorder.endRecording();
    PerfProbe.count('lodRasters');
    _inFlight++;
    _pending[key] = version;
    unawaited(
      picture
          .toImage(level, level)
          .then(
            (image) => _store(key, version, image, digest: digest, keep: true),
            onError: (Object error, StackTrace stack) => FlutterError.reportError(
              FlutterErrorDetails(exception: error, stack: stack, library: 'len rendering'),
            ),
          )
          .whenComplete(() {
            picture.dispose();
            _inFlight--;
            if (_pending[key] == version) _pending.remove(key);
            if (!_disposed && _queue.isNotEmpty) _timer ??= Timer(Duration.zero, _processBatch);
          }),
    );
  }

  /// Caches [image] as [key]'s raster of content [version] (showing
  /// content [digest], if known); with [keep], a copy goes to storage.
  void _store(_Key key, int version, ui.Image image, {ChunkDigest? digest, bool keep = false}) {
    if (keep && digest != null && !_disposed) {
      // Stored even if the chunk changed meanwhile: it shows [digest].
      _stored!.write(_stored!.nameOf(key.chunk, key.level, digest), image.clone());
    }
    if (_disposed || version != _versionOf(key.chunk)) {
      image.dispose(); // The chunk changed while it was being rasterised.
      return;
    }
    final previous = _images.remove(key);
    if (previous != null) {
      _bytes -= _sizeOf(key);
      previous.dispose();
    }
    _images[key] = image;
    _imageVersions[key] = version;
    _forgetDigest(key);
    if (digest != null) _imageDigests[key] = digest;
    _bytes += _sizeOf(key);
    _edited.remove(key.chunk);
    _trimOverlay(key.chunk);
    while (_bytes > maxBytes && _images.length > 1) {
      final oldest = _images.keys.first;
      _bytes -= _sizeOf(oldest);
      _images.remove(oldest)!.dispose();
      _imageVersions.remove(oldest);
      _forgetDigest(oldest);
      _trimOverlay(oldest.chunk);
    }
    _scheduleNotify();
  }

  static int _sizeOf(_Key key) => key.level * key.level * 4;

  void _forgetDigest(_Key key) {
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
    final overlay = _overlays[chunk];
    if (overlay == null) return;
    var oldest = 1 << 50;
    for (final level in levels) {
      final made = _imageVersions[(chunk: chunk, level: level)];
      if (made != null && made < oldest) oldest = made;
    }
    overlay.removeWhere((e) => e.$1 <= oldest);
    if (overlay.isEmpty) _overlays.remove(chunk);
  }

  void _onChange(SurfaceChange change) {
    final appended = change.appended;
    final chunks = change.chunks;
    if (!change.loaded) _stored?.forget(chunks);
    if (change.loaded && chunks != null) {
      // Stored content arrived: the images (and their overlays) stand in,
      // stale, until new ones are made — no vector frames while a canvas
      // loads.
      for (final chunk in chunks) {
        _versions[chunk] = ++_counter;
      }
      return;
    }
    if (appended == null || chunks == null) return _invalidate(chunks);
    for (final chunk in chunks) {
      final version = _versions[chunk] = ++_counter;
      final strokes = [
        for (final s in appended)
          if (s.bounds.overlaps(ChunkGrid.rectOf(chunk))) s,
      ];
      if (levels.any((l) => _images.containsKey((chunk: chunk, level: l)))) {
        (_overlays[chunk] ??= []).addAll([for (final s in strokes) (version, s)]);
      } else {
        _edited.add(chunk);
      }
    }
  }

  void _invalidate(Set<ChunkKey>? chunks) {
    if (chunks == null) {
      _overlays.clear();
      _versions.clear();
      // What was on screen may have changed anywhere.
      _edited.addAll([for (final key in _images.keys) key.chunk]);
      _epoch = ++_counter;
      _clear();
      return;
    }
    for (final chunk in chunks) {
      _versions[chunk] = ++_counter;
      _overlays.remove(chunk);
      _edited.add(chunk);
      for (final level in levels) {
        _imageVersions.remove((chunk: chunk, level: level));
        _forgetDigest((chunk: chunk, level: level));
        final image = _images.remove((chunk: chunk, level: level));
        if (image == null) continue;
        _bytes -= level * level * 4;
        image.dispose();
      }
    }
  }

  void _clear() {
    _imageVersions.clear();
    _imageDigests.clear();
    _digestChecked.clear();
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    _queue.clear();
    _bytes = 0;
  }

  @override
  void dispose() {
    _disposed = true;
    _stored?.dispose();
    _timer?.cancel();
    unawaited(_subscription.cancel());
    _clear();
    super.dispose();
  }
}

typedef _Key = ({ChunkKey chunk, int level});
