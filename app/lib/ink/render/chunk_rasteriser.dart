import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../domain/chunk_digest.dart';
import '../../domain/chunk_grid.dart';
import '../lab/perf_probe.dart';
import 'chunk_picture_cache.dart';

/// A chunk's raster at one level (its edge in pixels).
typedef RasterKey = ({ChunkKey chunk, int level});

/// Makes chunk rasters for `ChunkRasterCache`, off the critical path:
/// [request] only queues; queued chunks are recorded in short time-boxed
/// batches (one per event-loop turn, most recently requested first) and
/// rasterised asynchronously with [ui.Picture.toImage], at most
/// [maxInFlight] at once.
class ChunkRasteriser {
  ChunkRasteriser(
    this.pictures, {
    required this.versionOf,
    required this.isWanted,
    required this.storable,
    required this.onImage,
    this.batchBudget = const Duration(milliseconds: 6),
    this.maxInFlight = 8,
  });

  final ChunkPictureCache pictures;

  /// The current content version of a chunk.
  final int Function(ChunkKey chunk) versionOf;

  /// Whether a raster of a content version is still needed.
  final bool Function(RasterKey key, int version) isWanted;

  /// The digest a raster about to be made shows, if it may be stored.
  final ChunkDigest? Function(RasterKey key) storable;

  /// Receives a raster made of a content version (owning it).
  final void Function(RasterKey key, int version, ui.Image image, ChunkDigest? digest) onImage;

  /// Time a batch of recordings may take before yielding.
  final Duration batchBudget;

  /// Rasterisations running at once.
  final int maxInFlight;

  final LinkedHashMap<RasterKey, int> _queue = LinkedHashMap();
  int _inFlight = 0;

  /// Rasters being made, with the content version they are made from, so
  /// a chunk requested again on every frame is not rasterised twice.
  final Map<RasterKey, int> _pending = {};
  Timer? _timer;
  bool _disposed = false;

  /// Whether rasters are queued or being made.
  bool get isBusy => _queue.isNotEmpty || _inFlight > 0;

  /// Queues [key] at its chunk's current version.
  void request(RasterKey key) {
    if (_disposed) return;
    _queue
      ..remove(key)
      ..[key] = versionOf(key.chunk);
    // Requests from long ago are for views that are gone.
    while (_queue.length > 4096) {
      _queue.remove(_queue.keys.first);
    }
    _timer ??= Timer(Duration.zero, _processBatch);
  }

  /// Forgets the queue.
  void clear() => _queue.clear();

  void _processBatch() {
    _timer = null;
    if (_disposed) return;
    final watch = Stopwatch()..start();
    while (_queue.isNotEmpty && _inFlight < maxInFlight && watch.elapsed < batchBudget) {
      final key = _queue.keys.last; // Newest request first: what is on screen now.
      final version = _queue.remove(key)!;
      if (!isWanted(key, version) || _pending[key] == version) continue;
      _rasterise(key, version);
    }
    if (_queue.isNotEmpty && _inFlight < maxInFlight) {
      _timer = Timer(Duration.zero, _processBatch);
    }
  }

  void _rasterise(RasterKey key, int version) {
    final level = key.level;
    final recorder = ui.PictureRecorder();
    final rect = ChunkGrid.rectOf(key.chunk);
    ui.Canvas(recorder)
      ..scale(level / ChunkGrid.size)
      ..translate(-rect.left, -rect.top)
      ..drawPicture(pictures.pictureFor(key.chunk));
    final digest = storable(key); // After recording: it settles images.
    final picture = recorder.endRecording();
    PerfProbe.count('lodRasters');
    _inFlight++;
    _pending[key] = version;
    unawaited(
      picture
          .toImage(level, level)
          .then(
            (image) => _disposed ? image.dispose() : onImage(key, version, image, digest),
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

  void dispose() {
    _disposed = true;
    _timer?.cancel();
    _queue.clear();
  }
}
