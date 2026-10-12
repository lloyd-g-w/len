import 'dart:math' as math;

import '../../domain/recording.dart';

/// The audio of a recording kept by a trim: [start]…[end] in the whole
/// audio (ms).
typedef TrimRange = ({int start, int end});

/// Moving the handles of a trim being edited: each stays within the audio
/// and at least [Recording.minTrimMs] from the other (all of a recording
/// shorter than that stays).
extension TrimEditing on TrimRange {
  /// The range with its start moved to [ms].
  TrimRange withStart(int ms, int durationMs) {
    final latest = math.max(0, end - Recording.minTrimMs);
    return (start: ms.clamp(0, latest), end: end);
  }

  /// The range with its end moved to [ms].
  TrimRange withEnd(int ms, int durationMs) {
    final earliest = math.min(durationMs, start + Recording.minTrimMs);
    return (start: start, end: ms.clamp(earliest, math.max(earliest, durationMs)));
  }

  /// Length of the kept audio.
  int get lengthMs => end - start;

  /// Whether the range keeps all of [durationMs].
  bool keepsAll(int durationMs) => start <= 0 && end >= durationMs;
}

/// Maps between audio positions and x offsets on a track [width] wide
/// showing [durationMs] of audio.
extension type const TrimTrack._(({double width, int durationMs}) _t) {
  const TrimTrack(double width, int durationMs) : this._((width: width, durationMs: durationMs));

  double xOf(int ms) => _t.durationMs <= 0 ? 0 : ms / _t.durationMs * _t.width;

  int msAt(double x) =>
      (x / math.max(1, _t.width) * _t.durationMs).round().clamp(0, math.max(0, _t.durationMs));
}
