import 'dart:async';
import 'dart:developer' as developer;
import 'dart:ui' show FramePhase;

import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;

/// Launch milestones, for measuring startup (docs/PERFORMANCE.md,
/// "Startup"). Each is a Timeline instant event `len.startup.<label>`
/// (`flutter run --trace-startup`, DevTools); in builds made with
/// `--dart-define=LEN_STARTUP_TRACE=true` also a line on stdout:
///
///     len-startup <label> <µs since the epoch> +<ms since main>
///
/// and, for [watchWindow] after [watchTurns], every UI-thread turn over
/// [longTurn] (`len-startup-turn <ms> ending +<ms since main>`) and a last
/// `interactive` line: when the last of them ended (the library answers
/// input from then on).
abstract final class StartupTrace {
  /// Whether this build prints the milestones.
  static const bool enabled = bool.fromEnvironment('LEN_STARTUP_TRACE');

  /// Turns at least this long count as the app not answering.
  static const Duration longTurn = Duration(milliseconds: 50);

  /// How long after `runApp` long turns are watched for.
  static const Duration watchWindow = Duration(seconds: 6);

  static final Stopwatch _sinceMain = Stopwatch();
  static final Set<String> _seen = {};

  /// Called first thing in `main`: times are relative to it.
  static void begin() {
    _sinceMain.start();
    _mainMicros = developer.Timeline.now;
    mark('main');
  }

  static int _mainMicros = 0;
  static int _framesShown = 0;

  /// Labels marked after a frame ([markAfterFrame]) whose frame is not
  /// on screen yet, with when they were marked (Timeline µs).
  static final Map<String, int> _awaitingRaster = {};

  /// Prints the phases of the first [frames] frames (only in tracing
  /// builds), in ms since main:
  ///
  ///     len-startup-frame <n> build <start>-<end> raster <start>-<end>
  ///
  /// and, for each [markAfterFrame] label, when its frame was on screen
  /// (`len-startup <label> shown …`, rasterised).
  static void watchFrames({int frames = 12}) {
    if (!enabled) return;
    SchedulerBinding.instance.addTimingsCallback((timings) {
      for (final t in timings) {
        int at(FramePhase phase) => t.timestampInMicroseconds(phase);
        String ms(FramePhase phase) => ((at(phase) - _mainMicros) / 1000).toStringAsFixed(0);
        if (_framesShown++ < frames) {
          _print(
            'len-startup-frame ${t.frameNumber} build ${ms(FramePhase.buildStart)}-'
            '${ms(FramePhase.buildFinish)} raster ${ms(FramePhase.rasterStart)}-'
            '${ms(FramePhase.rasterFinish)}',
          );
        }
        // A post-frame callback runs before its frame's build finishes.
        for (final (label, marked) in [for (final e in _awaitingRaster.entries) (e.key, e.value)]) {
          if (at(FramePhase.buildFinish) < marked) continue;
          _awaitingRaster.remove(label);
          _printShown(label, at(FramePhase.rasterFinish));
        }
      }
    });
  }

  /// Prints that [label]'s frame was on screen at [shown] (Timeline µs).
  static void _printShown(String label, int shown) {
    final epoch = DateTime.now().microsecondsSinceEpoch - (developer.Timeline.now - shown);
    _print('len-startup $label shown $epoch +${((shown - _mainMicros) / 1000).round()}ms');
  }

  /// Milliseconds since [begin].
  static int get elapsedMs => _sinceMain.elapsedMilliseconds;

  /// Records milestone [label] (the first time only).
  static void mark(String label) {
    if (!_seen.add(label)) return;
    developer.Timeline.instantSync('len.startup.$label');
    if (!enabled) return;
    _print('len-startup $label ${DateTime.now().microsecondsSinceEpoch} +${elapsedMs}ms');
  }

  /// Records [label] once the frame being built is (the UI thread's part
  /// of it is) done.
  static void markAfterFrame(String label) {
    if (_seen.contains(label)) return;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      if (enabled && !_seen.contains(label)) {
        // The first frame reports no timings: it is on screen when the
        // binding says so.
        final binding = WidgetsBinding.instance;
        if (binding.firstFrameRasterized) {
          _awaitingRaster[label] = developer.Timeline.now;
        } else {
          unawaited(
            binding.waitUntilFirstFrameRasterized.then(
              (_) => _printShown(label, developer.Timeline.now),
            ),
          );
        }
      }
      mark(label);
    });
  }

  /// Watches the UI thread's turns from now for [watchWindow] (only in
  /// tracing builds): a timer ticking every few milliseconds sees how long
  /// each turn in between held the thread.
  static void watchTurns() {
    if (!enabled) return;
    const tick = Duration(milliseconds: 4);
    final turn = Stopwatch()..start();
    final window = Stopwatch()..start();
    var lastLongEnd = (DateTime.now().microsecondsSinceEpoch, elapsedMs);
    Timer.periodic(tick, (timer) {
      final held = turn.elapsed - tick;
      turn.reset();
      if (held >= longTurn) {
        lastLongEnd = (DateTime.now().microsecondsSinceEpoch, elapsedMs);
        _print('len-startup-turn ${held.inMilliseconds} ending +${lastLongEnd.$2}ms');
      }
      if (window.elapsed < watchWindow) return;
      timer.cancel();
      _print('len-startup interactive ${lastLongEnd.$1} +${lastLongEnd.$2}ms');
    });
  }

  // Plain print: debugPrint throttles long bursts.
  // ignore: avoid_print
  static void _print(String line) => print(line);
}
