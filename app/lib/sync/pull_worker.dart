import 'dart:typed_data';

import 'remote_changes.dart';

/// Starts a [PullWorker]; null where none can run (the web, an in-memory
/// database, a worker that failed to start).
typedef PullWorkerStart = Future<PullWorker?> Function();

/// The page header a [PullWorker] decoded, before it applies the records.
typedef PullHeader = ({int nextSince, bool hasMore, int lastSeq, int malformed});

/// What a [PullWorker] did with one page.
class WorkedPage {
  const WorkedPage({
    required this.header,
    required this.applied,
    required this.total,
    required this.changes,
  });

  final PullHeader header;

  /// Records applied, of [total]: fewer when the pull was cancelled.
  final int applied;
  final int total;

  /// What the page changed (with what deletion conflicts brought back).
  final RemoteChanges changes;
}

/// Decodes and applies pulled pages away from the UI isolate, over a
/// connection of its own to the same database file (`PullApplier` there,
/// with the same slices and the same transactions as on the UI isolate).
/// One pull at a time; [close] when the pull ends.
abstract interface class PullWorker {
  /// Decodes [body] (a `/v1/pull` answer to a request after [since]) and
  /// applies it. [onHeader] hears the page's header as soon as it is
  /// decoded (the next page can be fetched meanwhile). [hadChanges]: earlier
  /// pages of this pull changed something (deletion conflicts are resolved
  /// after the last page then). Polls [cancelled] while it works and stops
  /// after the current slice once it is true. Null if [body] is not a valid
  /// page. Throws [PullWorkerException] if the worker failed (a database
  /// error: the pull stops, as it would on the UI isolate).
  Future<WorkedPage?> apply(
    Uint8List body, {
    required int since,
    required bool hadChanges,
    required void Function(PullHeader header) onHeader,
    required bool Function() cancelled,
  });

  /// Stops the worker, closing its connection.
  Future<void> close();
}

/// A [PullWorker] failed while applying a page.
class PullWorkerException implements Exception {
  const PullWorkerException(this.message, {this.changes});

  final String message;

  /// What the page's slices committed before the failure, if known.
  final RemoteChanges? changes;

  @override
  String toString() => 'Applying pulled records failed: $message';
}
