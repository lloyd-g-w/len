import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../domain/chunk_grid.dart';
import '../../domain/stroke.dart';
import '../surface_model.dart';
import 'chunk_picture_cache.dart';

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
  }

  final ChunkPictureCache pictures;

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

  /// Whether rasters are queued or being made.
  bool get isBusy => _queue.isNotEmpty || _inFlight > 0;

  /// Content version each cached image was made from.
  final Map<_Key, int> _imageVersions = {};

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
      if ((_imageVersions[key] ?? 0) != _versionOf(chunk)) _enqueue(key); // Stale.
      return exact;
    }
    _enqueue(key);
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
    final recorder = ui.PictureRecorder();
    final rect = ChunkGrid.rectOf(key.chunk);
    ui.Canvas(recorder)
      ..scale(level / ChunkGrid.size)
      ..translate(-rect.left, -rect.top)
      ..drawPicture(pictures.pictureFor(key.chunk));
    final picture = recorder.endRecording();
    _inFlight++;
    _pending[key] = version;
    unawaited(
      picture
          .toImage(level, level)
          .then(
            (image) => _store(key, version, image),
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

  void _store(_Key key, int version, ui.Image image) {
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
    _bytes += _sizeOf(key);
    _trimOverlay(key.chunk);
    while (_bytes > maxBytes && _images.length > 1) {
      final oldest = _images.keys.first;
      _bytes -= _sizeOf(oldest);
      _images.remove(oldest)!.dispose();
      _imageVersions.remove(oldest);
      _trimOverlay(oldest.chunk);
    }
    _scheduleNotify();
  }

  static int _sizeOf(_Key key) => key.level * key.level * 4;

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
      }
    }
  }

  void _invalidate(Set<ChunkKey>? chunks) {
    if (chunks == null) {
      _overlays.clear();
      _versions.clear();
      _epoch = ++_counter;
      _clear();
      return;
    }
    for (final chunk in chunks) {
      _versions[chunk] = ++_counter;
      _overlays.remove(chunk);
      for (final level in levels) {
        _imageVersions.remove((chunk: chunk, level: level));
        final image = _images.remove((chunk: chunk, level: level));
        if (image == null) continue;
        _bytes -= level * level * 4;
        image.dispose();
      }
    }
  }

  void _clear() {
    _imageVersions.clear();
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
    _timer?.cancel();
    unawaited(_subscription.cancel());
    _clear();
    super.dispose();
  }
}

typedef _Key = ({ChunkKey chunk, int level});
