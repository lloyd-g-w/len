import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../data/stroke_reader.dart';
import '../domain/chunk_grid.dart';
import '../domain/stroke.dart';
import '../domain/surface_element.dart';

/// Schedules reads of one surface's chunks from a [StrokeReader].
///
/// With an asynchronous reader (a background isolate) panning never waits
/// for SQLite. The loader keeps that safe and cheap:
///  * at most one read is in flight; while it runs, newer requests replace
///    each other and only the newest range is read next;
///  * [reset] (e.g. a reload after sync) drops a read in flight;
///  * strokes and elements removed while a read is in flight (erased,
///    undone, moved) are filtered out of its result, since the read may
///    predate the removal;
///  * a large range (over [splitAbove] chunks: a whole canvas seen from
///    afar) is read in blocks of [block] × [block] chunks, those nearest
///    its middle first, so ink
///    shows from where the user looks within a fraction of a second
///    instead of after one read (and one copy between isolates) of tens
///    of thousands of strokes.
///
/// A synchronous reader delivers results immediately, inside [request].
class SurfaceLoader {
  SurfaceLoader({
    required this.reader,
    required this.surfaceId,
    required this.skipFor,
    required this.onLoad,
    this.block = 4,
    this.splitAbove = 36,
  });

  /// Chunks per side of the blocks a large range is read in.
  final int block;

  /// Ranges of more chunks than this are read in blocks.
  final int splitAbove;

  final StrokeReader reader;
  final String surfaceId;

  /// Chunks already in memory within a range (not read again).
  final Set<ChunkKey> Function(ChunkRange range) skipFor;

  /// Receives each result (on the UI isolate).
  final void Function(ChunkLoad load) onLoad;

  int _generation = 0;
  bool _inFlight = false;
  ChunkRange? _queued;

  /// Blocks of the current request still to read, nearest first.
  final List<ChunkRange> _blocks = [];
  final Set<String> _removed = {};
  Completer<void>? _idle;
  bool _disposed = false;

  /// Whether a read is in flight or queued.
  bool get isLoading => _inFlight;

  /// Completes once no read is in flight or queued.
  Future<void> get idle => _inFlight ? (_idle ??= Completer<void>()).future : Future.value();

  /// Reads the populated chunks of [range] not yet in memory.
  void request(ChunkRange range) {
    if (_disposed) return;
    if (_inFlight) {
      _queued = range;
      return;
    }
    _blocks
      ..clear()
      ..addAll(_split(range));
    _readNext();
  }

  /// [range] cut into blocks, ordered by their distance from its middle.
  List<ChunkRange> _split(ChunkRange range) {
    final w = range.maxX - range.minX + 1, h = range.maxY - range.minY + 1;
    if (range.count <= splitAbove || (w <= block && h <= block)) return [range];
    final cx = (range.minX + range.maxX) / 2, cy = (range.minY + range.maxY) / 2;
    // Blocks centred on the middle chunk, so the first one is the middle.
    final ox = range.minX + ((cx - range.minX - (block - 1) / 2).round() % block);
    final oy = range.minY + ((cy - range.minY - (block - 1) / 2).round() % block);
    final blocks = <ChunkRange>[];
    for (var y = oy - block; y <= range.maxY; y += block) {
      for (var x = ox - block; x <= range.maxX; x += block) {
        final b = ChunkRange(
          math.max(x, range.minX),
          math.max(y, range.minY),
          math.min(x + block - 1, range.maxX),
          math.min(y + block - 1, range.maxY),
        );
        if (b.minX <= b.maxX && b.minY <= b.maxY) blocks.add(b);
      }
    }
    double distance(ChunkRange b) {
      final dx = (b.minX + b.maxX) / 2 - cx, dy = (b.minY + b.maxY) / 2 - cy;
      return dx * dx + dy * dy;
    }

    return blocks..sort((a, b) => distance(a).compareTo(distance(b)));
  }

  /// Reads the next block of the current request, if any.
  void _readNext() {
    while (_blocks.isNotEmpty && !_disposed) {
      final range = _blocks.removeAt(0);
      if (!_read(range)) return; // In flight.
    }
  }

  /// Reads [range]; false while the read is in flight.
  bool _read(ChunkRange range) {
    _removed.clear();
    final generation = _generation;
    final FutureOr<ChunkLoad> result;
    try {
      result = reader.read(surfaceId, range, skip: skipFor(range));
    } on Object catch (error, stack) {
      _report(error, stack);
      return true;
    }
    if (result is ChunkLoad) {
      onLoad(result);
      return true;
    }
    _inFlight = true;
    result.then(
      (load) {
        if (_disposed || generation != _generation) return;
        _inFlight = false;
        onLoad(_withoutRemoved(load));
        _next();
      },
      onError: (Object error, StackTrace stack) {
        if (_disposed || generation != _generation) return;
        _inFlight = false;
        _report(error, stack);
        _next();
      },
    );
    return false;
  }

  /// Records that a stroke or element left memory, so a read in flight
  /// cannot bring back a stale copy.
  void noteRemoved(String id) {
    if (_inFlight) _removed.add(id);
  }

  /// Forgets any read in flight or queued; their results are ignored.
  void reset() {
    _generation++;
    _inFlight = false;
    _queued = null;
    _blocks.clear();
    _completeIdle();
  }

  void dispose() {
    _disposed = true;
    _completeIdle();
  }

  ChunkLoad _withoutRemoved(ChunkLoad load) {
    if (_removed.isEmpty) return load;
    return ChunkLoad(
      chunks: load.chunks,
      strokes: <Stroke>[
        for (final s in load.strokes)
          if (!_removed.contains(s.id)) s,
      ],
      elements: <SurfaceElement>[
        for (final e in load.elements)
          if (!_removed.contains(e.id)) e,
      ],
    );
  }

  void _next() {
    final queued = _queued;
    _queued = null;
    if (queued != null) {
      request(queued);
    } else {
      _readNext();
    }
    if (!_inFlight) _completeIdle();
  }

  void _completeIdle() {
    _idle?.complete();
    _idle = null;
  }

  void _report(Object error, StackTrace stack) => FlutterError.reportError(
    FlutterErrorDetails(exception: error, stack: stack, library: 'len surface loading'),
  );
}
