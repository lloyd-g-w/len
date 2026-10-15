import 'dart:async';
import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/foundation.dart' show visibleForTesting;
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
  SendPort? _port;
  bool _closed = false;

  /// Its exit, heard on the port it is spawned with: requests still
  /// waiting fall back then, later ones too.
  final _exit = Completer<void>();
  RawReceivePort? _exitPort;

  /// Where the requests still waiting hear their answer: told [_gone] when
  /// the worker exits or is closed. (Never wait on [_exit] per request: a
  /// wait on a future that never completes keeps each answer alive.)
  final _waiting = <SendPort>{};

  /// Requests waiting for an answer (tests check none is left behind).
  @visibleForTesting
  int get waiting => _waiting.length;

  /// The worker isolate once started (tests watch it exit).
  @visibleForTesting
  Future<Isolate?> get isolate async {
    await (_worker ??= _spawn());
    return _isolate;
  }

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
    if (_port case final port?) Isolate.current.removeOnExitListener(port);
    _isolate?.kill(priority: Isolate.immediate);
    _isolate = null;
    _exitPort?.close();
    _stopped();
  }

  /// The worker is gone (or closed): requests waiting fall back.
  void _stopped() {
    if (!_exit.isCompleted) _exit.complete();
    for (final reply in _waiting) {
      reply.send(_gone);
    }
    _waiting.clear();
  }

  Future<T> _call<T>(_Request request, FutureOr<T> Function() orElse) async {
    final worker = _closed ? null : await (_worker ??= _spawn());
    if (worker == null || _exit.isCompleted) return orElse();
    final reply = ReceivePort();
    _waiting.add(reply.sendPort);
    worker.send((request, reply.sendPort));
    final answer = await reply.first;
    _waiting.remove(reply.sendPort);
    if (answer is _Failure) return orElse();
    return answer as T;
  }

  Future<SendPort?> _spawn() async {
    final ready = ReceivePort();
    final exit = _exitPort = RawReceivePort((_) {
      _stopped();
      _exitPort?.close();
    });
    try {
      _isolate = await Isolate.spawn(
        _serve,
        (path, ready.sendPort),
        debugName: 'stroke reader',
        onExit: exit.sendPort,
      );
      final port = await Future.any<Object?>([ready.first, _exit.future.then((_) => _gone)]);
      if (port is! SendPort || _closed) {
        // Failed, or closed while it started: never left running.
        _isolate?.kill(priority: Isolate.immediate);
        return null;
      }
      // Added while this isolate surely lives: the worker hears it exit
      // (the engine destroyed on Android, the process living on) and
      // exits too, closing its connection, instead of living on orphaned.
      Isolate.current.addOnExitListener(port, response: _ownerExited);
      return _port = port;
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
      if (message == _ownerExited) {
        inbox.close();
        db.close();
        Isolate.exit();
      }
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

/// What the worker hears when the isolate that started it exits.
const _ownerExited = 'owner exited';

/// A request's answer once the worker is gone.
const _gone = _Failure('the worker stopped');

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
