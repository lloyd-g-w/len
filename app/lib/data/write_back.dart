import 'dart:async';

import 'package:flutter/foundation.dart';

/// Why changes could not be stored.
enum WriteFailure {
  /// The storage is out of space (a browser's quota).
  full,

  /// Any other error.
  failed,
}

/// Thrown by storage when it is out of space (a browser's
/// `QuotaExceededError`).
class StorageFullException implements Exception {
  const StorageFullException([this.message = 'Storage is full']);

  final String message;

  @override
  String toString() => 'StorageFullException: $message';
}

/// The [WriteFailure] behind [error].
WriteFailure writeFailureOf(Object error) =>
    error is StorageFullException ? WriteFailure.full : WriteFailure.failed;

/// A store that keeps changes in memory and writes them to durable storage
/// shortly after (the web's IndexedDB). Changes that fail to be written are
/// kept and retried ([WriteBackRetry]), never dropped.
abstract interface class WriteBackStore implements Listenable {
  /// Whether some changes are not stored yet.
  bool get pending;

  /// Why the last attempt to store changes failed; null once one succeeds.
  WriteFailure? get failure;

  /// Tries to store the pending changes now; completes with whether every
  /// change made before the call is stored.
  Future<bool> flush();

  /// Stops accepting changes (later ones throw) and stores the pending
  /// ones; completes with whether they are stored (if not, it keeps
  /// retrying, and [pending] turns false once they are).
  Future<bool> close();
}

/// All of the app's [WriteBackStore]s (none on native platforms, where
/// writes are synchronous): whether anything is unsaved, why saving fails,
/// and a way to save everything now.
class StorageWrites extends ChangeNotifier {
  final List<WriteBackStore> _stores = [];
  bool _closed = false;

  /// Adds [store]; this notifies when it does. Once [close]d, [store] is
  /// closed right away (another tab may own the data).
  void add(WriteBackStore store) {
    if (_closed) unawaited(store.close());
    _stores.add(store);
    store.addListener(notifyListeners);
    notifyListeners();
  }

  /// Whether some changes are not stored yet.
  bool get pending => _stores.any((s) => s.pending);

  /// The most serious current failure ([WriteFailure.full] first).
  WriteFailure? get failure {
    final failures = {for (final s in _stores) s.failure}..remove(null);
    if (failures.contains(WriteFailure.full)) return WriteFailure.full;
    return failures.isEmpty ? null : WriteFailure.failed;
  }

  /// Stores everything now; completes with whether all of it is stored.
  Future<bool> flush() async {
    final results = await Future.wait([for (final s in _stores) s.flush()]);
    return results.every((ok) => ok);
  }

  /// Closes every store ([WriteBackStore.close]): before another tab takes
  /// over the data.
  Future<bool> close() async {
    _closed = true;
    final results = await Future.wait([for (final s in _stores) s.close()]);
    return results.every((ok) => ok);
  }

  @override
  void dispose() {
    for (final s in _stores) {
      s.removeListener(notifyListeners);
    }
    super.dispose();
  }
}

/// Schedules retries after failed writes: 2 s, then 5, 15 and every 30 s
/// (space may be freed at any time; we can't be told when).
class WriteBackRetry {
  WriteBackRetry(this._retry);

  final void Function() _retry;
  Timer? _timer;
  int _failures = 0;

  static const _delays = [2, 5, 15, 30];

  /// A write failed: retries after the next delay.
  void failed() {
    final seconds = _delays[_failures < _delays.length ? _failures : _delays.length - 1];
    _failures++;
    _timer?.cancel();
    _timer = Timer(Duration(seconds: seconds), _retry);
  }

  /// A write succeeded: starts over.
  void succeeded() {
    _failures = 0;
    cancel();
  }

  /// Whether a retry is scheduled.
  bool get scheduled => _timer?.isActive ?? false;

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}
