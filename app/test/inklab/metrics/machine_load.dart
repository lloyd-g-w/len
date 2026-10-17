import 'dart:io';

/// How busy the machine is while timing metrics are measured. On a busy
/// machine (the default tier runs a test file per core, beside builds and
/// other agents) a wall-clock time measures the scheduler as much as the
/// code, so `judge.dart` relaxes absolute timing limits there; the slow
/// tier (`test/perf/inklab_timing_perf_test.dart`) judges them strictly.
abstract final class MachineLoad {
  /// Share of [body]'s wall time its thread waited for a CPU, above which
  /// the timings it took are the machine's rather than the code's.
  static const double busyWaitShare = 0.05;

  /// Runs [body] (synchronous, so on one thread) and returns its result
  /// with the share of its wall time the thread spent runnable but waiting
  /// for a CPU (`/proc/thread-self/schedstat`; 0 where unavailable).
  static (T, double) waitShare<T>(T Function() body) {
    final before = _schedstat();
    final watch = Stopwatch()..start();
    final result = body();
    final wall = watch.elapsedMicroseconds * 1000;
    final after = _schedstat();
    if (before == null || after == null || wall <= 0) return (result, 0);
    return (result, ((after.$2 - before.$2) / wall).clamp(0.0, 1.0));
  }

  /// Whether the 1-minute load average is at least half the cores: other
  /// work competes for them, though maybe not this moment.
  static bool get loadAverageHigh {
    try {
      final load = double.parse(File('/proc/loadavg').readAsStringSync().split(' ').first);
      return load >= Platform.numberOfProcessors / 2;
    } on Object {
      return false;
    }
  }

  /// (time run, time waiting to run) of this thread so far, in ns.
  static (int, int)? _schedstat() {
    try {
      final f = File('/proc/thread-self/schedstat').readAsStringSync().trim().split(' ');
      return (int.parse(f[0]), int.parse(f[1]));
    } on Object {
      return null;
    }
  }
}
