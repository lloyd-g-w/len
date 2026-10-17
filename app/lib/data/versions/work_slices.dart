/// Lets a long run of work (a version of a notebook of a thousand pages)
/// yield to the event loop after every [budget] of it, so it never makes a
/// long task on the web's main thread.
class WorkSlices {
  WorkSlices({this.budget = const Duration(milliseconds: 8)});

  final Duration budget;
  final Stopwatch _watch = Stopwatch()..start();

  /// Yields a turn once [budget] has passed since the last.
  Future<void> yieldIfDue() async {
    if (_watch.elapsed < budget) return;
    await Future<void>.delayed(Duration.zero);
    _watch.reset();
  }
}
