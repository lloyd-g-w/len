part of 'background_pull_worker.dart';

// What the app and its pull worker tell each other, and how the app hears
// the worker's isolate stop.

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
  const _Header(this.nextSince, this.hasMore, this.lastSeq, this.malformed);
  final int nextSince;
  final bool hasMore;
  final int lastSeq;
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

final class _Exited {
  const _Exited();
}

/// What the worker hears when the app's isolate exits.
const _ownerExited = 'owner exited';

/// Hears a worker isolate's exit and errors (on the port it is spawned
/// with).
class _WorkerLife {
  _WorkerLife() {
    port.listen((message) {
      if (message is List && message.isNotEmpty) {
        // An uncaught error: fatal, its exit follows.
        _error ??= '${message.first}';
        debugPrint('The pull worker failed: ${message.first}\n${message.last}');
      } else if (!_exit.isCompleted) {
        _exit.complete();
      }
    });
  }

  final port = ReceivePort();
  final _exit = Completer<void>();
  String? _error;

  /// Completes once the isolate exited.
  Future<void> get exited => _exit.future;

  bool get dead => _exit.isCompleted;

  /// Why it stopped, for the pull's error.
  String get reason => _error == null ? 'the worker stopped' : 'the worker stopped: $_error';

  void close() => port.close();
}
