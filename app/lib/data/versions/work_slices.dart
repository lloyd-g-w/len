/// Lets a long run of work (a version of a notebook of a thousand pages)
/// yield to the event loop after every [budget] of it, so it never makes a
/// long task on the web's main thread, and pause while [hold] says so (a
/// pen or finger is down: no slice then lands in a frame while writing).
class WorkSlices {
  WorkSlices({this.budget = const Duration(milliseconds: 4), this.hold});

  final Duration budget;

  /// Whether to wait (checked at every slice, then every [holdPoll]).
  final bool Function()? hold;

  /// How often a held run looks again.
  static const holdPoll = Duration(milliseconds: 50);

  final Stopwatch _watch = Stopwatch()..start();

  /// Yields a turn once [budget] has passed since the last, and waits
  /// while [hold] is true.
  Future<void> yieldIfDue() async {
    if (hold?.call() ?? false) {
      while (hold!()) {
        await Future<void>.delayed(holdPoll);
      }
      _watch.reset();
      return;
    }
    if (_watch.elapsed < budget) return;
    await Future<void>.delayed(Duration.zero);
    _watch.reset();
  }
}
