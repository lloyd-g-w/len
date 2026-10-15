import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

/// Tells the low-latency overlay about every frame Flutter builds while it
/// may draw ink (`progress`), so it lets go of ink only once a frame
/// showing it is on screen (`WetInkHandover.kt`).
///
/// One report per frame, however many surfaces have input (the overlay
/// counts frames: a frame built [trailingFrames] frames after another
/// means the raster thread is done with that one). After the newest input
/// (or a message sent after a frame) it keeps reporting [trailingFrames]
/// more frames, asking for them if nothing else does, so the last input's
/// frame can be judged on screen too.
class LowLatencyFrames {
  LowLatencyFrames(this._send);

  final void Function(List<Object?> message) _send;

  /// Frames reported after the last input: `WetInkHandover.PIPELINE_FRAMES`.
  static const int trailingFrames = 3;

  int _upToUs = 0;
  int _trailing = 0;
  int _frameId = 0;
  bool _scheduled = false;
  final List<void Function()> _afterReport = [];
  final List<bool Function()> _watchers = [];

  /// The id of the newest frame reported.
  int get frameId => _frameId;

  /// Input up to [timeUs] (event time) is handled: the next frame shows it.
  void input(int timeUs) {
    if (timeUs > _upToUs) _upToUs = timeUs;
    _keep();
  }

  /// Runs [action] right after the next frame's report (that frame is
  /// built with everything handled so far).
  void afterNextFrame(void Function() action) {
    _afterReport.add(action);
    _keep();
  }

  /// Calls [watcher] after every frame built from now on (without asking
  /// for frames) until it returns false.
  void watch(bool Function() watcher) {
    _watchers.add(watcher);
    _schedule(request: false);
  }

  /// Forgets everything pending (tests: a new binding's frames).
  @visibleForTesting
  void reset() {
    _upToUs = 0;
    _trailing = 0;
    _scheduled = false;
    _requested = false;
    _afterReport.clear();
    _watchers.clear();
  }

  void _keep() {
    _trailing = trailingFrames + 1; // The next frame, then the trailing ones.
    _schedule(request: true);
  }

  bool _requested = false;

  void _schedule({required bool request}) {
    final binding = SchedulerBinding.instance;
    if (!_scheduled) {
      _scheduled = true;
      binding.addPostFrameCallback(_report, debugLabel: 'LowLatencyFrames');
    }
    if (request && !_requested) {
      _requested = true;
      binding.ensureVisualUpdate();
    }
  }

  void _report(Duration _) {
    _scheduled = false;
    _requested = false;
    final reporting = _trailing > 0 || _afterReport.isNotEmpty;
    if (reporting) {
      _send(['progress', _upToUs.toDouble(), ++_frameId]);
      final after = [..._afterReport];
      _afterReport.clear();
      for (final a in after) {
        a();
      }
      _trailing--;
    }
    _watchers.retainWhere((w) => w());
    if (_trailing > 0) {
      _schedule(request: true);
    } else if (_watchers.isNotEmpty) {
      _schedule(request: false);
    }
  }
}
