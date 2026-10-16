part of 'playback_controller.dart';

/// The kept range of a [PlaybackController]'s recording, and editing its
/// trim.
mixin _PlaybackTrim on ChangeNotifier {
  /// The open recording.
  Recording? get recording;

  /// Its timeline (wall times of positions).
  RecordingTimeline? get _timeline;

  /// The position heard.
  int get positionMs;

  /// Jumps to [positionMs] (kept to [startMs]…[endMs]).
  Future<void> seek(int positionMs);

  /// The trim being edited (start and end in the whole audio), or null.
  TrimRange? get trimDraft => _trimDraft;
  TrimRange? _trimDraft;

  /// Where the kept audio begins (0 without a recording).
  int get startMs => _trimDraft?.start ?? recording?.trimStartMs ?? 0;

  /// Where the kept audio ends (0 without a recording).
  int get endMs => _trimDraft?.end ?? recording?.trimEndMs ?? 0;

  /// The wall time after which ink was made after the kept audio (it is
  /// not veiled), or null when the audio is kept to its end.
  int? get veilUntil {
    final open = recording;
    if (open == null || endMs >= open.durationMs) return null;
    return _timeline?.wallTimeAt(endMs);
  }

  /// Starts editing the trim of the open recording (from its current one).
  void beginTrim() {
    final open = recording;
    if (open == null) return;
    _trimDraft = (start: open.trimStartMs, end: open.trimEndMs);
    notifyListeners();
  }

  /// Moves the edited trim to [range] (see [TrimEditing]); the position
  /// follows into it.
  void setTrimDraft(TrimRange range) {
    if (_trimDraft == null || _trimDraft == range) return;
    _trimDraft = range;
    notifyListeners();
    if (positionMs < range.start || positionMs > range.end) unawaited(seek(positionMs));
  }

  /// Leaves trim editing (after saving it or not).
  void endTrim() {
    if (_trimDraft == null) return;
    _trimDraft = null;
    notifyListeners();
    if (positionMs < startMs || positionMs > endMs) unawaited(seek(positionMs));
  }
}
