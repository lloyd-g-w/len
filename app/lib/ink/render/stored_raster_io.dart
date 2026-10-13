import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';

import '../../data/raster_store.dart';
import '../../domain/chunk_grid.dart';
import '../lab/perf_probe.dart';

/// Reads and writes the PNG files of `StoredRasters`, so that neither
/// floods the device nor costs frames.
///
/// Reads: a view far out may ask for well over a thousand chunks at once.
/// They are queued and read [maxReads] at a time, nearest to the middle
/// of the [view] first; those whose chunk left the view are dropped
/// (asked for again if it comes back).
///
/// Writes: encoding a raster reads its pixels back from the GPU on the
/// raster thread (the PNG encoding itself runs on the engine's IO thread),
/// so writes wait until the view has been idle — no paint, no new raster —
/// for [idleDelay], then go one at a time while it stays idle. At most
/// [maxPendingBytes] of images wait; beyond that the oldest are dropped
/// (drawn and stored again another time).
class StoredRasterIo {
  StoredRasterIo(
    this.store, {
    this.maxReads = 4,
    this.idleDelay = const Duration(milliseconds: 300),
    this.maxPendingBytes = 16 << 20,
  });

  final RasterStore store;

  /// Reads (and decodes) running at once.
  final int maxReads;

  /// Quiet time before writes start.
  final Duration idleDelay;

  /// Memory images waiting to be written may hold.
  final int maxPendingBytes;

  /// Rasters known to be stored (read or written this session).
  final Set<String> _known = {};

  final Map<String, _Read> _waiting = {};
  final Set<String> _reading = {};
  List<String>? _order;
  ChunkRange? _view;

  final LinkedHashMap<String, ui.Image> _pending = LinkedHashMap();
  int _pendingBytes = 0;
  bool _writing = false;
  Timer? _idle;
  final Stopwatch _clock = Stopwatch()..start();
  Duration _lastActivity = Duration.zero;
  bool _disposed = false;

  /// Whether raster [name] is queued or being read.
  bool isReading(String name) => _waiting.containsKey(name) || _reading.contains(name);

  /// Whether reads are queued or running.
  bool get reading => _waiting.isNotEmpty || _reading.isNotEmpty;

  /// Whether rasters wait to be written or are being written.
  bool get saving => _pending.isNotEmpty || _writing;

  /// The chunks on screen: queued reads of others are dropped, the rest
  /// are read nearest to its middle first.
  set view(ChunkRange range) {
    if (range == _view) return;
    _view = range;
    _order = null;
    _pump();
  }

  /// Reads and decodes raster [name] of [chunk] when its turn comes;
  /// [done] gets the image (null if it is not stored or unreadable). Not
  /// called if the read is dropped (see [view]).
  void read(String name, ChunkKey chunk, void Function(ui.Image? image) done) {
    if (_disposed || isReading(name)) return;
    _waiting[name] = _Read(chunk, done);
    _order = null;
    _pump();
  }

  /// Something was painted or rasterised: writes wait.
  void noteActivity() {
    _lastActivity = _clock.elapsed;
    if (_pending.isNotEmpty) _idle ??= Timer(idleDelay, _flush);
  }

  /// Stores [image] as [name] once the view is idle (unless it is known
  /// to be stored). Takes ownership of [image].
  void write(String name, ui.Image image) {
    if (_disposed || !_known.add(name)) return image.dispose();
    PerfProbe.count('lodStoreWrites');
    _pending.remove(name)?.dispose();
    _pending[name] = image;
    _pendingBytes += _sizeOf(image);
    while (_pendingBytes > maxPendingBytes && _pending.length > 1) {
      final oldest = _pending.keys.first;
      _known.remove(oldest);
      _drop(oldest);
    }
    noteActivity();
  }

  void _pump() {
    if (_disposed) return;
    while (_reading.length < maxReads && _waiting.isNotEmpty) {
      final order = _order ??= _sorted();
      if (order.isEmpty) break;
      final name = order.removeLast();
      final read = _waiting.remove(name);
      if (read == null) continue;
      _reading.add(name);
      unawaited(_read(name, read));
    }
  }

  /// The queued reads still in view, nearest to its middle last; drops
  /// the others.
  List<String> _sorted() {
    final view = _view;
    if (view == null) return _waiting.keys.toList();
    // A chunk's margin: the edge row may be asked for a frame early.
    final keep = ChunkRange(view.minX - 1, view.minY - 1, view.maxX + 1, view.maxY + 1);
    _waiting.removeWhere((_, read) => !keep.contains(read.chunk));
    final cx = view.minX + view.maxX, cy = view.minY + view.maxY;
    int distance(ChunkKey k) {
      final dx = 2 * k.x - cx, dy = 2 * k.y - cy;
      return dx * dx + dy * dy;
    }

    return _waiting.keys.toList()
      ..sort((a, b) => distance(_waiting[b]!.chunk).compareTo(distance(_waiting[a]!.chunk)));
  }

  Future<void> _read(String name, _Read read) async {
    ui.Image? image;
    try {
      PerfProbe.count('lodStoreReads');
      final bytes = await store.read(name);
      if (bytes != null && !_disposed) {
        final codec = await ui.instantiateImageCodec(bytes);
        final frame = await codec.getNextFrame();
        codec.dispose();
        image = frame.image;
        _known.add(name);
        PerfProbe.count('lodStoreHits');
      }
    } on Object {
      image = null; // Corrupt: drawn again (and stored over).
    }
    _reading.remove(name);
    if (_disposed) {
      image?.dispose();
      return;
    }
    read.done(image);
    _pump();
  }

  void _flush() {
    _idle = null;
    if (_writing || _pending.isEmpty) return;
    final quiet = _clock.elapsed - _lastActivity;
    if (quiet < idleDelay && !_disposed) {
      _idle = Timer(idleDelay - quiet, _flush);
      return;
    }
    final name = _pending.keys.first;
    final image = _pending.remove(name)!;
    _pendingBytes -= _sizeOf(image);
    _writing = true;
    unawaited(
      _write(name, image).whenComplete(() {
        _writing = false;
        // The next one, as long as the view stays idle.
        if (_pending.isNotEmpty) _idle ??= Timer(Duration.zero, _flush);
      }),
    );
  }

  Future<void> _write(String name, ui.Image image) async {
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data != null) await store.write(name, data.buffer.asUint8List());
    } on Object catch (error, stack) {
      _known.remove(name);
      FlutterError.reportError(
        FlutterErrorDetails(exception: error, stack: stack, library: 'len rendering'),
      );
    } finally {
      image.dispose();
    }
  }

  void _drop(String name) {
    final image = _pending.remove(name);
    if (image == null) return;
    _pendingBytes -= _sizeOf(image);
    image.dispose();
  }

  static int _sizeOf(ui.Image image) => image.width * image.height * 4;

  /// Drops the reads waiting; the writes waiting go now, one at a time
  /// (the view is gone).
  void dispose() {
    _disposed = true;
    _waiting.clear();
    _idle?.cancel();
    _idle = null;
    _flush();
  }
}

class _Read {
  _Read(this.chunk, this.done);

  final ChunkKey chunk;
  final void Function(ui.Image? image) done;
}
