import 'package:flutter/scheduler.dart';

import '../../ink/lab/input_recording.dart';
import '../../ink/lab/replay.dart';
import 'inklab_session.dart';

/// Plays a recording back on screen in real time: the surface is cleared,
/// then each real frame handles the input up to the next recorded frame
/// boundary through the real pipeline ([ReplayDriver]).
///
/// Recording is paused meanwhile; the statistics show the recording's
/// own entries (its frame timings included) as they are replayed.
class InkLabReplay {
  InkLabReplay(this.session, this.recording, {required TickerProvider vsync, this.pen}) {
    _ticker = vsync.createTicker(_onTick);
  }

  final InkLabSession session;
  final InputRecording recording;

  /// The pen to replay with (null: the recorded one).
  final PenSettings? pen;
  late final Ticker _ticker;
  ReplayDriver? _driver;
  int _fed = 0;

  /// Called once the whole recording was replayed (not after [stop]).
  void Function()? onDone;

  bool get running => _ticker.isActive;

  /// Clears the surface and starts playing.
  void start() {
    session
      ..stopRecording()
      ..clear();
    _driver = ReplayDriver(
      recording,
      model: session.model,
      live: session.live,
      viewport: session.viewport,
      pen: pen,
    );
    _ticker.start();
  }

  void _onTick(Duration _) {
    final step = _driver?.step();
    _feedStats(step?.frame?.t);
    if (step == null || step.frame == null) _finish(done: true);
  }

  /// Adds the recording's entries up to [untilUs] (all: null) to the stats.
  void _feedStats(int? untilUs) {
    final entries = recording.entries;
    while (_fed < entries.length && (untilUs == null || entries[_fed].t <= untilUs)) {
      session.stats.add(entries[_fed++]);
    }
  }

  /// Stops playing (what was replayed so far stays on the surface).
  void stop() => _finish(done: false);

  void _finish({required bool done}) {
    if (_driver == null) return;
    _driver = null;
    _ticker.stop();
    session
      ..recorder.clear()
      ..startRecording();
    if (done) onDone?.call();
  }

  void dispose() {
    _driver = null;
    _ticker.dispose();
  }
}
