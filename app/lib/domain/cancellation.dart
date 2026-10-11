/// Thrown by a long operation that stopped because the user cancelled it.
class Cancelled implements Exception {
  const Cancelled();

  @override
  String toString() => 'Cancelled';
}

/// Asked by long operations whether to stop; [check] throws [Cancelled]
/// once [cancel] was called.
class CancellationToken {
  bool _cancelled = false;

  /// Whether [cancel] was called.
  bool get isCancelled => _cancelled;

  /// Asks the operation to stop at its next [check].
  void cancel() => _cancelled = true;

  /// Throws [Cancelled] if the operation should stop.
  void check() {
    if (_cancelled) throw const Cancelled();
  }
}
