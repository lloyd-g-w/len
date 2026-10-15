import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;

import '../core/clock.dart';
import '../data/app_database.dart';
import '../data/repositories.dart';
import '../data/settings_repository.dart';
import '../platform/write_signal_native.dart';
import 'pull_applier.dart';
import 'pull_page.dart';
import 'pull_worker.dart';
import 'remote_changes.dart';

/// A [PullWorker] in an isolate of its own, over its own connection to the
/// database file (WAL: the UI isolate keeps reading meanwhile). Its
/// slices end as soon as the app begins a transaction (the app's
/// [AppDatabase.writeSignal], a [SharedWriteSignal]) and wait until that
/// is over: the app's write waits for one record. Writes outside a
/// transaction wait at most a slice ([sliceUs], then [gap]).
///
/// Pages arrive as bytes (one buffer copy, no objects), are decoded there and
/// applied by a [PullApplier] as on the UI isolate. Native only (imported
/// by `platform/pull_worker_native.dart`).
class BackgroundPullWorker implements PullWorker {
  BackgroundPullWorker._(this._isolate, this._port, this._database, this._signal);

  /// How long (µs) a slice (one transaction) may run: as long as the UI
  /// isolate may have to wait to write.
  static const int sliceUs = 8000;

  /// The pause after each slice, in which the UI isolate's writes get the
  /// lock (its waits poll every few milliseconds).
  static const Duration gap = Duration(milliseconds: 1);

  final Isolate _isolate;
  final SendPort _port;
  final AppDatabase _database;
  final SharedWriteSignal _signal;
  bool _closed = false;
  bool _dead = false;

  /// Starts a worker on the file of [database] (the app's connection,
  /// which it yields to) for device [deviceId] ([clock] stamps what
  /// deletion conflicts bring back; it is copied over). Null if it cannot
  /// start.
  static Future<BackgroundPullWorker?> start(
    AppDatabase database, {
    required String deviceId,
    Clock clock = const Clock(),
  }) async {
    final path = database.path;
    if (path == null || database.writeSignal != null) return null;
    final signal = SharedWriteSignal();
    final ready = ReceivePort();
    Isolate? isolate;
    try {
      isolate = await Isolate.spawn(_serve, (
        path: path,
        deviceId: deviceId,
        clock: clock,
        signal: signal.address,
        ready: ready.sendPort,
      ), debugName: 'pull worker');
      final answer = await ready.first;
      if (answer is SendPort) {
        database.writeSignal = signal;
        return BackgroundPullWorker._(isolate, answer, database, signal);
      }
      debugPrint('The pull worker did not start: $answer');
    } on Object catch (e) {
      debugPrint('The pull worker did not start: $e');
    } finally {
      ready.close();
    }
    if (isolate != null) {
      // Whether it read the signal yet or not, it may: never freed then.
      isolate.kill(priority: Isolate.immediate);
    } else {
      signal.free();
    }
    return null;
  }

  @override
  Future<WorkedPage?> apply(
    Uint8List body, {
    required int since,
    required bool hadChanges,
    required void Function(PullHeader header) onHeader,
    required bool Function() cancelled,
  }) async {
    if (_closed) throw const PullWorkerException('closed');
    final replies = ReceivePort();
    _isolate.addOnExitListener(replies.sendPort, response: _exited);
    var cancelSent = false;
    final watch = Timer.periodic(const Duration(milliseconds: 10), (_) {
      if (cancelSent || !cancelled()) return;
      cancelSent = true;
      _port.send(const _Cancel());
    });
    try {
      _port.send(
        _Page(TransferableTypedData.fromList([body]), since, hadChanges, replies.sendPort),
      );
      PullHeader? header;
      await for (final answer in replies) {
        switch (answer) {
          case _Invalid():
            return null;
          case _Header(:final nextSince, :final hasMore, :final malformed):
            header = (nextSince: nextSince, hasMore: hasMore, malformed: malformed);
            onHeader(header);
          case _Done(:final applied, :final total, :final changes):
            return WorkedPage(header: header!, applied: applied, total: total, changes: changes);
          case _Failed(:final message, :final changes):
            throw PullWorkerException(message, changes: changes);
          case _exited:
            _dead = true;
            throw const PullWorkerException('the worker stopped');
        }
      }
      throw const PullWorkerException('no answer');
    } finally {
      watch.cancel();
      _isolate.removeOnExitListener(replies.sendPort);
      replies.close();
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (identical(_database.writeSignal, _signal)) _database.writeSignal = null;
    var exited = _dead;
    if (!exited) {
      final exit = ReceivePort();
      _isolate.addOnExitListener(exit.sendPort, response: _exited);
      _port.send(const _Close());
      // It closes its connection and exits; never wait long for that.
      exited = await exit.first.timeout(const Duration(seconds: 1), onTimeout: () => null) != null;
      exit.close();
    }
    _isolate.kill(priority: Isolate.immediate);
    // Freed only once the worker surely reads it no more.
    if (exited) _signal.free();
  }

  static void _serve(
    ({String path, String deviceId, Clock clock, int signal, SendPort ready}) args,
  ) {
    final writing = WriterWaiting(args.signal);
    final AppDatabase database;
    try {
      database = AppDatabase.attach(args.path);
    } on Object catch (e) {
      args.ready.send('$e');
      return;
    }
    final repositories = Repositories(database, deviceId: args.deviceId, clock: args.clock);
    final applier = PullApplier(
      database: database,
      settings: SettingsRepository(database),
      repositories: repositories,
      stores: repositories.byCollection,
    );
    var cancelled = false;
    final inbox = ReceivePort();
    args.ready.send(inbox.sendPort);
    inbox.listen((message) async {
      switch (message) {
        case _Cancel():
          cancelled = true;
        case _Close():
          inbox.close();
          database.close();
        case _Page(:final body, :final since, :final hadChanges, :final reply):
          // What the slices committed, also when a later one fails.
          final changes = RemoteChanges();
          try {
            final page = decodePullPage(body.materialize().asUint8List(), since: since);
            if (page == null) {
              reply.send(const _Invalid());
              return;
            }
            if (page.malformed > 0) {
              debugPrint('Skipped ${page.malformed} malformed records after seq $since');
            }
            reply.send(_Header(page.nextSince, page.hasMore, page.malformed));
            final applied = await applier.applyPage(
              page,
              changes,
              hadChanges: hadChanges,
              budgetUs: sliceUs,
              yieldNow: writing.call,
              pause: () async {
                await Future<void>.delayed(gap);
                // The app writing: wait until it is done (it holds the lock).
                while (writing() && !cancelled) {
                  await Future<void>.delayed(const Duration(milliseconds: 1));
                }
                return !cancelled;
              },
            );
            reply.send(_Done(applied, page.records.length, changes));
          } on Object catch (e) {
            reply.send(_Failed('$e', changes));
          }
      }
    });
  }
}

final class _Page {
  const _Page(this.body, this.since, this.hadChanges, this.reply);
  final TransferableTypedData body;
  final int since;
  final bool hadChanges;
  final SendPort reply;
}

final class _Cancel {
  const _Cancel();
}

final class _Close {
  const _Close();
}

final class _Invalid {
  const _Invalid();
}

final class _Header {
  const _Header(this.nextSince, this.hasMore, this.malformed);
  final int nextSince;
  final bool hasMore;
  final int malformed;
}

final class _Done {
  const _Done(this.applied, this.total, this.changes);
  final int applied;
  final int total;
  final RemoteChanges changes;
}

final class _Failed {
  const _Failed(this.message, this.changes);
  final String message;
  final RemoteChanges changes;
}

/// What the worker's exit notice says.
const _exited = 'exited';
