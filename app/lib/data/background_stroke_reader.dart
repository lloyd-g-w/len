import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:sqlite3/sqlite3.dart';

import '../domain/chunk_digest.dart';
import '../domain/chunk_grid.dart';
import 'stroke_queries.dart';
import 'stroke_reader.dart';

/// Reads strokes in a background isolate over its own read-only SQLite
/// connection, so lazy loading while panning never blocks a frame.
///
/// SQLite in WAL mode lets this reader run alongside the UI isolate's
/// writer; a read sees every write committed before it started. The
/// isolate is spawned on first use. If it cannot be started (or a query
/// fails there), requests fall back to [fallback] on the calling isolate.
class BackgroundStrokeReader implements StrokeReader {
  BackgroundStrokeReader(this.path, {required this.fallback});

  /// The database file.
  final String path;

  /// Used when the worker is unavailable.
  final StrokeReader fallback;

  Future<SendPort?>? _worker;
  Isolate? _isolate;
  bool _closed = false;

  @override
  Future<ChunkLoad> read(String surfaceId, ChunkRange range, {Set<ChunkKey> skip = const {}}) =>
      _call(_Read(surfaceId, range, skip), () => fallback.read(surfaceId, range, skip: skip));

  @override
  Future<Map<ChunkKey, ChunkDigest>> chunkDigests(String surfaceId, ChunkRange range) =>
      _call(_Digests(surfaceId, range), () => fallback.chunkDigests(surfaceId, range));

  @override
  Future<Map<ChunkKey, int>> chunkDensity(String surfaceId) =>
      _call(_Density(surfaceId), () => fallback.chunkDensity(surfaceId));

  @override
  Future<Rect?> contentBounds(String surfaceId) =>
      _call(_Bounds(surfaceId), () => fallback.contentBounds(surfaceId));

  /// Stops the worker isolate.
  void close() {
    _closed = true;
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
  }

  Future<T> _call<T>(_Request request, FutureOr<T> Function() orElse) async {
    final worker = _closed ? null : await (_worker ??= _spawn());
    if (worker == null) return orElse();
    final reply = ReceivePort();
    worker.send((request, reply.sendPort));
    final answer = await reply.first;
    reply.close();
    if (answer is _Failure) return orElse();
    return answer as T;
  }

  Future<SendPort?> _spawn() async {
    final ready = ReceivePort();
    try {
      _isolate = await Isolate.spawn(_serve, (path, ready.sendPort), debugName: 'stroke reader');
      final port = await ready.first;
      return port is SendPort ? port : null;
    } on Object {
      return null;
    } finally {
      ready.close();
    }
  }

  static void _serve((String, SendPort) args) {
    final (path, ready) = args;
    final Database db;
    try {
      db = sqlite3.open(path, mode: OpenMode.readOnly);
    } on Object catch (e) {
      ready.send(_Failure('$e'));
      return;
    }
    final queries = StrokeQueries(db);
    final inbox = ReceivePort();
    ready.send(inbox.sendPort);
    inbox.listen((message) {
      final (request, reply) = message as (_Request, SendPort);
      try {
        reply.send(switch (request) {
          _Read(:final surfaceId, :final range, :final skip) => queries.read(
            surfaceId,
            range,
            skip: skip,
          ),
          _Digests(:final surfaceId, :final range) => queries.chunkDigests(surfaceId, range),
          _Density(:final surfaceId) => queries.chunkDensity(surfaceId),
          _Bounds(:final surfaceId) => queries.contentBounds(surfaceId),
        });
      } on Object catch (e) {
        reply.send(_Failure('$e'));
      }
    });
  }
}

sealed class _Request {
  const _Request(this.surfaceId);
  final String surfaceId;
}

final class _Read extends _Request {
  const _Read(super.surfaceId, this.range, this.skip);
  final ChunkRange range;
  final Set<ChunkKey> skip;
}

final class _Digests extends _Request {
  const _Digests(super.surfaceId, this.range);
  final ChunkRange range;
}

final class _Density extends _Request {
  const _Density(super.surfaceId);
}

final class _Bounds extends _Request {
  const _Bounds(super.surfaceId);
}

final class _Failure {
  const _Failure(this.message);
  final String message;
}
