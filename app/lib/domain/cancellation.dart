import 'dart:async';

/// Thrown by a long operation that stopped because the user cancelled it.
class Cancelled implements Exception {
  const Cancelled();

  @override
  String toString() => 'Cancelled';
}

/// Asked by long operations whether to stop; [check] throws [Cancelled]
/// once [cancel] was called.
class CancellationToken {
  final Completer<void> _cancelled = Completer<void>();

  /// Whether [cancel] was called.
  bool get isCancelled => _cancelled.isCompleted;

  /// Asks the operation to stop at its next [check].
  void cancel() {
    if (!_cancelled.isCompleted) _cancelled.complete();
  }

  /// Throws [Cancelled] if the operation should stop.
  void check() {
    if (isCancelled) throw const Cancelled();
  }

  /// [work]'s outcome, or [Cancelled] as soon as [cancel] is called, for
  /// work that can't check by itself (one long call into a library). The
  /// work then goes on unseen and its outcome is dropped, so it must have
  /// no lasting effects.
  Future<T> race<T>(Future<T> work) {
    check();
    final outcome = Completer<T>();
    work.then(
      (value) {
        if (!outcome.isCompleted) outcome.complete(value);
      },
      onError: (Object error, StackTrace stack) {
        if (!outcome.isCompleted) outcome.completeError(error, stack);
      },
    );
    unawaited(
      _cancelled.future.then((_) {
        if (!outcome.isCompleted) outcome.completeError(const Cancelled());
      }),
    );
    return outcome.future;
  }

  /// [data], throwing [Cancelled] at the next chunk once [cancel] is called.
  Stream<T> guard<T>(Stream<T> data) => data.map((chunk) {
    check();
    return chunk;
  });
}
