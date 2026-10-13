import '../../core/clock.dart';
import '../../domain/recording.dart';

/// The wall-time stretches of a recording in progress: the closed
/// [RecordingSegment]s between pauses plus the running one, from which
/// the audio recorded so far is measured.
class RecordingStopwatch {
  RecordingStopwatch(this.clock);

  final Clock clock;

  /// Closed segments of the current recording.
  final List<RecordingSegment> _segments = [];

  /// Wall time the running segment started (while recording).
  int? _runningSince;

  /// Wall time the running segment started, or null while paused.
  int? get runningSince => _runningSince;

  /// A copy of the closed segments.
  List<RecordingSegment> get closed => List.of(_segments);

  /// Audio recorded so far, in ms.
  int get elapsedMs {
    final closed = _segments.fold(0, (sum, s) => sum + s.durationMs);
    final start = _runningSince;
    return start == null ? closed : closed + (clock.nowMs() - start).clamp(0, 1 << 30);
  }

  /// Starts a running segment now.
  void run() => _runningSince = clock.nowMs();

  /// Closes the running segment, if any.
  void halt() {
    final start = _runningSince;
    if (start == null) return;
    _segments.add(RecordingSegment(start, (clock.nowMs() - start).clamp(0, 1 << 30)));
    _runningSince = null;
  }

  /// Forgets the closed segments.
  void clear() => _segments.clear();
}
