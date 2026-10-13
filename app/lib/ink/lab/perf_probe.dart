import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Rendering performance probe for measurements on devices (profile builds
/// with `--dart-define=LEN_PERF=true`; see docs/INK_LAB.md, "Performance").
///
/// Collects every frame's build and raster times and, for each committed
/// stroke, the pen-up → on-screen latency: from the lift event's time stamp
/// to the end of rasterising the first frame built after the commit. After
/// each burst of frames (no frame for [idle]) it logs a summary line
/// starting with `LENPERF`.
///
/// Counters ([count]) let hot paths report work per burst (pictures
/// recorded, tiles rasterised, …). Everything is a no-op unless [start]ed.
abstract final class PerfProbe {
  /// Whether this build asked for the probe.
  static const bool requested = bool.fromEnvironment('LEN_PERF');

  static bool _running = false;
  static final List<ui.FrameTiming> _frames = [];
  static final List<_Lift> _lifts = [];
  static final List<int> _latencies = [];
  static final List<int> _commitToShown = [];
  static final Map<String, int> _counters = {};
  static int _lastFrameUs = 0;
  static Duration idle = const Duration(milliseconds: 1500);

  /// Whether the probe is collecting.
  static bool get running => _running;

  /// Starts collecting (idempotent).
  static void start() {
    if (_running) return;
    _running = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
    _scheduleFlush();
  }

  /// Adds [n] to counter [name] for the current burst.
  static void count(String name, [int n = 1]) {
    if (!_running) return;
    _counters[name] = (_counters[name] ?? 0) + n;
  }

  /// Counts [count]s without collecting frames or logging (tests).
  @visibleForTesting
  static void startCounting() => _running = true;

  /// Counter [name] of the current burst (tests).
  @visibleForTesting
  static int counter(String name) => _counters[name] ?? 0;

  /// A stroke lifted at [liftTime] (pointer event time stamp) was just
  /// committed.
  static void lift(Duration? liftTime) {
    if (!_running) return;
    final now = developer.Timeline.now;
    _lifts.add(_Lift(liftTime?.inMicroseconds ?? now, now));
  }

  static void _onTimings(List<ui.FrameTiming> timings) {
    for (final t in timings) {
      _frames.add(t);
      final buildStart = t.timestampInMicroseconds(ui.FramePhase.buildStart);
      final shown = t.timestampInMicroseconds(ui.FramePhase.rasterFinish);
      _lastFrameUs = shown;
      _lifts.removeWhere((lift) {
        if (buildStart < lift.committedUs) return false;
        _latencies.add(shown - lift.eventUs);
        _commitToShown.add(shown - lift.committedUs);
        return true;
      });
    }
  }

  static void _scheduleFlush() {
    Future<void>.delayed(const Duration(milliseconds: 250), () {
      if (!_running) return;
      final quiet = developer.Timeline.now - _lastFrameUs > idle.inMicroseconds;
      if (quiet && _frames.isNotEmpty && _lifts.isEmpty) flush();
      _scheduleFlush();
    });
  }

  /// Logs and resets the current burst.
  static void flush() {
    if (_frames.isEmpty) return;
    final build = [for (final t in _frames) t.buildDuration.inMicroseconds];
    final raster = [for (final t in _frames) t.rasterDuration.inMicroseconds];
    final total = [for (final t in _frames) t.totalSpan.inMicroseconds];
    final line = StringBuffer('LENPERF frames=${_frames.length}')
      ..write(' build[${_stats(build)}]')
      ..write(' raster[${_stats(raster)}]')
      ..write(' total[${_stats(total)}]')
      ..write(' over16ms=${total.where((us) => us > 16667).length}');
    if (_latencies.isNotEmpty) {
      line
        ..write(' lifts=${_latencies.length}')
        ..write(' liftToShown[${_stats(_latencies)}]')
        ..write(' commitToShown[${_stats(_commitToShown)}]');
    }
    for (final entry in _counters.entries) {
      line.write(' ${entry.key}=${entry.value}');
    }
    debugPrint(line.toString());
    _frames.clear();
    _latencies.clear();
    _commitToShown.clear();
    _counters.clear();
  }

  /// "p50/p90/p99/max" in milliseconds.
  static String _stats(List<int> us) {
    final sorted = [...us]..sort();
    String at(double q) {
      final i = math.min(sorted.length - 1, (q * sorted.length).floor());
      return (sorted[i] / 1000).toStringAsFixed(1);
    }

    return '${at(.5)}/${at(.9)}/${at(.99)}/${(sorted.last / 1000).toStringAsFixed(1)}';
  }
}

class _Lift {
  _Lift(this.eventUs, this.committedUs);
  final int eventUs;
  final int committedUs;
}
