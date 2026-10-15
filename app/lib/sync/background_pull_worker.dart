import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;

import '../core/clock.dart';
import '../data/app_database.dart';
import '../data/repositories.dart';
import '../data/settings_repository.dart';
import '../platform/write_signal_native.dart';
import 'pull_applier.dart';
import 'pull_page.dart';
import 'pull_worker.dart';
import 'remote_changes.dart';

part 'background_pull_worker_messages.dart';

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
  BackgroundPullWorker._(this._isolate, this._port, this._database, this._signal, this._life);

  /// How long (µs) a slice (one transaction) may run: as long as the UI
  /// isolate may have to wait to write.
  static const int sliceUs = 8000;

  /// The pause after each slice, in which the UI isolate's writes get the
  /// lock (its waits poll every few milliseconds).
  static const Duration gap = Duration(milliseconds: 1);

  /// Runs first thing in the worker isolate (tests make it die there).
  @visibleForTesting
  static void Function()? debugOnServe;

  final Isolate _isolate;
  final SendPort _port;
  final AppDatabase _database;
  final SharedWriteSignal _signal;
  final _WorkerLife _life;
  bool _closed = false;

  /// The worker isolate (tests watch it exit).
  @visibleForTesting
  Isolate get isolate => _isolate;

  /// Starts a worker on the file of [database] (the app's connection,
  /// which it yields to) for device [deviceId] ([clock] stamps what
  /// deletion conflicts bring back; it is copied over). Null if it cannot
  /// start (or dies before it is ready).
  ///
  /// The worker hears when this isolate exits (the engine destroyed on
  /// Android, the process living on): it closes its connection and exits
  /// too, instead of living on orphaned.
  static Future<BackgroundPullWorker?> start(
    AppDatabase database, {
    required String deviceId,
    Clock clock = const Clock(),
  }) async {
    final path = database.path;
    if (path == null || database.writeSignal != null) return null;
    final signal = SharedWriteSignal();
    final ready = ReceivePort();
    final life = _WorkerLife();
    Isolate? isolate;
    try {
      isolate = await Isolate.spawn(
        _serve,
        (
          path: path,
          deviceId: deviceId,
          clock: clock,
          signal: signal.address,
          ready: ready.sendPort,
          onServe: debugOnServe,
          sliceRecords: PullApplier.debugSliceRecords,
        ),
        debugName: 'pull worker',
        // Set up with the spawn: an exit before a listener added later
        // would never be heard (and a pull would wait for it forever).
        onExit: life.port.sendPort,
        onError: life.port.sendPort,
      );
      final Object? answer = await Future.any<Object?>([
        ready.first,
        life.exited.then((_) => life.reason),
      ]);
      if (answer is SendPort) {
        final port = answer;
        // Added here, while this isolate surely lives: its exit is heard.
        Isolate.current.addOnExitListener(port, response: _ownerExited);
        database.writeSignal = signal;
        return BackgroundPullWorker._(isolate, port, database, signal, life);
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
    life.close();
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
    if (_life.dead) throw PullWorkerException(_life.reason);
    final replies = ReceivePort();
    // Its exit (it died between pages, or now) ends the wait for replies.
    unawaited(_life.exited.then((_) => replies.sendPort.send(const _Exited())));
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
          case _Header(:final nextSince, :final hasMore, :final lastSeq, :final malformed):
            header = (
              nextSince: nextSince,
              hasMore: hasMore,
              lastSeq: lastSeq,
              malformed: malformed,
            );
            onHeader(header);
          case _Done(:final applied, :final total, :final changes):
            return WorkedPage(header: header!, applied: applied, total: total, changes: changes);
          case _Failed(:final message, :final changes):
            throw PullWorkerException(message, changes: changes);
          case _Exited():
            throw PullWorkerException(_life.reason);
        }
      }
      throw const PullWorkerException('no answer');
    } finally {
      watch.cancel();
      replies.close();
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    if (identical(_database.writeSignal, _signal)) _database.writeSignal = null;
    Isolate.current.removeOnExitListener(_port);
    if (!_life.dead) _port.send(const _Close());
    // It closes its connection and exits; never wait long for that.
    final exited = await _life.exited
        .then((_) => true)
        .timeout(const Duration(seconds: 1), onTimeout: () => false);
    _isolate.kill(priority: Isolate.immediate);
    _life.close();
    // Freed only once the worker surely reads it no more.
    if (exited) _signal.free();
  }

  static void _serve(
    ({
      String path,
      String deviceId,
      Clock clock,
      int signal,
      SendPort ready,
      void Function()? onServe,
      int? sliceRecords,
    })
    args,
  ) {
    args.onServe?.call();
    PullApplier.debugSliceRecords = args.sliceRecords;
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
    // The app writing: wait until it is done (it holds the lock, or is
    // about to). False once cancelled.
    Future<bool> yieldToApp() async {
      while (writing() && !cancelled) {
        await Future<void>.delayed(const Duration(milliseconds: 1));
      }
      return !cancelled;
    }

    final inbox = ReceivePort();
    args.ready.send(inbox.sendPort);
    inbox.listen((message) async {
      switch (message) {
        case _Cancel():
          cancelled = true;
        case _Close():
          inbox.close();
          database.close();
        case _ownerExited:
          // The app's isolate is gone (the engine destroyed, the process
          // living on): nobody to pull for. Between slices: no
          // transaction open.
          cancelled = true;
          inbox.close();
          database.close();
          Isolate.exit();
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
            reply.send(_Header(page.nextSince, page.hasMore, page.lastSeq, page.malformed));
            if (!await yieldToApp()) {
              reply.send(_Done(0, page.records.length, changes));
              return;
            }
            final applied = await applier.applyPage(
              page,
              changes,
              hadChanges: hadChanges,
              budgetUs: sliceUs,
              yieldNow: writing.call,
              pause: () async {
                await Future<void>.delayed(gap);
                return yieldToApp();
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
