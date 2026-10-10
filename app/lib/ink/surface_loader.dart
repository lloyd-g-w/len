import 'dart:async';

import 'package:flutter/foundation.dart';

import '../data/stroke_reader.dart';
import '../domain/chunk_grid.dart';
import '../domain/stroke.dart';

/// Schedules reads of one surface's chunks from a [StrokeReader].
///
/// With an asynchronous reader (a background isolate) panning never waits
/// for SQLite. The loader keeps that safe and cheap:
///  * at most one read is in flight; while it runs, newer requests replace
///    each other and only the newest range is read next;
///  * [reset] (e.g. a reload after sync) drops a read in flight;
///  * strokes removed while a read is in flight (erased, undone) are
///    filtered out of its result, since the read may predate the removal.
///
/// A synchronous reader delivers results immediately, inside [request].
class SurfaceLoader {
  SurfaceLoader({
    required this.reader,
    required this.surfaceId,
    required this.skipFor,
    required this.onLoad,
  });

  final StrokeReader reader;
  final String surfaceId;

  /// Chunks already in memory within a range (not read again).
  final Set<ChunkKey> Function(ChunkRange range) skipFor;

  /// Receives each result (on the UI isolate).
  final void Function(ChunkLoad load) onLoad;

  int _generation = 0;
  bool _inFlight = false;
  ChunkRange? _queued;
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
    _removed.clear();
    final generation = _generation;
    final FutureOr<ChunkLoad> result;
    try {
      result = reader.read(surfaceId, range, skip: skipFor(range));
    } on Object catch (error, stack) {
      _report(error, stack);
      return;
    }
    if (result is ChunkLoad) {
      onLoad(result);
      return;
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
  }

  /// Records that a stroke left memory, so a read in flight cannot bring
  /// back a stale copy.
  void noteRemoved(String strokeId) {
    if (_inFlight) _removed.add(strokeId);
  }

  /// Forgets any read in flight or queued; their results are ignored.
  void reset() {
    _generation++;
    _inFlight = false;
    _queued = null;
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
    );
  }

  void _next() {
    final queued = _queued;
    _queued = null;
    if (queued != null) request(queued);
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
