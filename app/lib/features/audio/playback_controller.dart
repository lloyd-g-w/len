import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../../data/blob_store.dart';
import '../../domain/recording.dart';
import 'backends/audio_backends.dart';
import 'trim_range.dart';

/// Plays one recording at a time and relates the playback position to the
/// ink: [wallTime] is the moment being heard, so strokes written after it
/// can be dimmed, and [seekToInk] jumps to when a stroke was written.
///
/// Positions are in the whole audio of the recording; playback keeps to
/// its kept range ([startMs]…[endMs]: the trim, or the [trimDraft] being
/// edited).
class PlaybackController extends ChangeNotifier {
  PlaybackController({required this.backends, required this.blobs, required this.fetch});

  final AudioBackends backends;
  final BlobStore blobs;

  /// Fetches a blob from the sync server (see `SyncController.fetchBlob`).
  final Future<bool> Function(String sha) fetch;

  /// How far before a stroke's time (when it was begun) [seekToInk]
  /// starts, so the words that led to it are heard.
  static const int leadMs = 1500;

  AudioPlayback? _player;
  StreamSubscription<Duration>? _positions;
  StreamSubscription<void>? _completed;

  Recording? _recording;

  /// The open recording (the playback bar is shown while there is one).
  Recording? get recording => _recording;
  RecordingTimeline? _timeline;

  int _positionMs = 0;
  int get positionMs => _positionMs;

  bool _playing = false;
  bool get playing => _playing;

  bool _loading = false;
  bool get loading => _loading;

  /// Whether tapping ink seeks to when it was written (instead of drawing).
  bool _tapToSeek = true;
  bool get tapToSeek => _tapToSeek;
  set tapToSeek(bool value) {
    if (value == _tapToSeek) return;
    _tapToSeek = value;
    notifyListeners();
  }

  /// Playback speeds offered by the player.
  static const List<double> rates = [0.75, 1, 1.25, 1.5, 2];

  double _rate = 1;

  /// Playback speed (one of [rates]); kept when another recording opens.
  double get rate => _rate;

  Future<void> setRate(double rate) async {
    if (rate == _rate) return;
    _rate = rate;
    notifyListeners();
    if (_recording != null && !_loading) await _player?.setRate(rate);
  }

  /// Counts jumps of the position ([seek], [skip]), so media controls
  /// that extrapolate it (lock screen, notification) can follow.
  int get seeks => _seeks;
  int _seeks = 0;

  /// Plays quieter while another app's sound is mixed over it (ducking).
  Future<void> setDucked(bool ducked) async {
    if (ducked == _ducked) return;
    _ducked = ducked;
    await _player?.setVolume(ducked ? duckedVolume : 1);
  }

  bool _ducked = false;

  /// The volume while [setDucked].
  static const double duckedVolume = 0.2;

  /// How far [skip] buttons and ← / → jump.
  static const int skipMs = 10000;

  /// Jumps [deltaMs] forwards (or backwards when negative).
  Future<void> skip(int deltaMs) => seek(_positionMs + deltaMs);

  /// The last problem, for a message.
  String? lastError;

  /// The wall time (epoch ms) being heard, or null without a recording.
  int? get wallTime => _timeline?.wallTimeAt(_positionMs);

  /// The trim being edited (start and end in the whole audio), or null.
  TrimRange? get trimDraft => _trimDraft;
  TrimRange? _trimDraft;

  /// Where the kept audio begins (0 without a recording).
  int get startMs => _trimDraft?.start ?? _recording?.trimStartMs ?? 0;

  /// Where the kept audio ends (0 without a recording).
  int get endMs => _trimDraft?.end ?? _recording?.trimEndMs ?? 0;

  /// The wall time after which ink was made after the kept audio (it is
  /// not veiled), or null when the audio is kept to its end.
  int? get veilUntil {
    final recording = _recording;
    if (recording == null || endMs >= recording.durationMs) return null;
    return _timeline?.wallTimeAt(endMs);
  }

  /// Starts editing the trim of the open recording (from its current one).
  void beginTrim() {
    final recording = _recording;
    if (recording == null) return;
    _trimDraft = (start: recording.trimStartMs, end: recording.trimEndMs);
    notifyListeners();
  }

  /// Moves the edited trim to [range] (see [TrimEditing]); the position
  /// follows into it.
  void setTrimDraft(TrimRange range) {
    if (_trimDraft == null || _trimDraft == range) return;
    _trimDraft = range;
    notifyListeners();
    if (_positionMs < range.start || _positionMs > range.end) unawaited(seek(_positionMs));
  }

  /// Leaves trim editing (after saving it or not).
  void endTrim() {
    if (_trimDraft == null) return;
    _trimDraft = null;
    notifyListeners();
    if (_positionMs < startMs || _positionMs > endMs) unawaited(seek(_positionMs));
  }

  /// Takes over a newer version of the open recording (renamed, trimmed).
  /// Other audio (parts outside the trim dropped, or put back) is opened
  /// afresh, paused at its kept start: positions have moved.
  void update(Recording recording) {
    final open = _recording;
    if (open == null || recording.id != open.id || identical(recording, open)) return;
    if (!listEquals(recording.parts, open.parts)) {
      unawaited(this.open(recording, autoplay: false));
      return;
    }
    _recording = recording;
    _timeline = recording.timeline;
    notifyListeners();
    if (_positionMs < startMs || _positionMs > endMs) unawaited(seek(_positionMs));
  }

  /// Opens [recording] and starts playing it. Returns false (with
  /// [lastError]) if it cannot be played, or if another recording was
  /// opened (or the player closed) before it was loaded.
  Future<bool> open(Recording recording, {bool autoplay = true}) async {
    final open = ++_opens;
    lastError = null;
    _loading = true;
    _recording = recording;
    _timeline = recording.timeline;
    _positionMs = 0;
    _playing = false;
    _trimDraft = null;
    notifyListeners();
    final player = _player ??= _createPlayer();
    // One at a time: a slow open (downloading) finishing after a later one
    // would leave its audio in the player.
    final previous = _opening;
    final opened = Completer<void>();
    _opening = opened.future;
    try {
      await previous;
      if (open != _opens) return false; // Superseded before it began.
      await player.open(recording, blobs, fetch);
    } on Object catch (e) {
      if (open != _opens) return false;
      if (e is! AudioUnavailable) debugPrint('Playback failed to open: $e');
      lastError = e is AudioUnavailable ? e.message : 'This recording cannot be played';
      _loading = false;
      close();
      return false;
    } finally {
      opened.complete();
    }
    if (open != _opens) return false;
    _loading = false;
    if (_rate != 1 && open == _opens) await player.setRate(_rate);
    if (recording.trimStartMs > 0 && open == _opens) await seek(recording.trimStartMs);
    if (autoplay && open == _opens) await play();
    if (open == _opens) notifyListeners();
    return true;
  }

  /// Counts [open] and [close] calls: an open finding it changed was
  /// superseded.
  int _opens = 0;

  /// The player's open under way, if any (they run one after the other).
  Future<void>? _opening;

  AudioPlayback _createPlayer() {
    final player = backends.playback();
    _positions = player.positions.listen((p) {
      _positionMs = p.inMilliseconds;
      // The kept audio ends here: stop as if the recording did.
      if (_playing && _recording != null && _positionMs >= endMs) {
        _positionMs = endMs;
        _playing = false;
        unawaited(player.pause());
      }
      notifyListeners();
    });
    _completed = player.completed.listen((_) {
      _playing = false;
      if (_recording != null) _positionMs = endMs;
      notifyListeners();
    });
    return player;
  }

  Future<void> play() async {
    final recording = _recording;
    if (recording == null || _loading) return;
    // Replaying from the end starts again.
    if (_positionMs < startMs || _positionMs >= endMs - 50) await seek(startMs);
    _playing = true;
    notifyListeners();
    await _player?.play();
  }

  Future<void> pause() async {
    _playing = false;
    notifyListeners();
    await _player?.pause();
  }

  Future<void> toggle() => _playing ? pause() : play();

  /// Jumps to [positionMs] of the open recording.
  Future<void> seek(int positionMs) async {
    final recording = _recording;
    if (recording == null) return;
    _positionMs = positionMs.clamp(startMs, math.max(startMs, endMs));
    _seeks++;
    notifyListeners();
    await _player?.seek(Duration(milliseconds: _positionMs));
  }

  /// Plays from shortly before ink written at [createdAt] (epoch ms).
  /// Returns false when it was not written during the open recording.
  Future<bool> seekToInk(int createdAt) async {
    final position = _timeline?.positionOf(createdAt);
    if (position == null || position < startMs || position > endMs) return false;
    await seek(position - leadMs);
    if (!_playing) await play();
    return true;
  }

  /// Stops playback and hides the bar.
  void close() {
    final player = _player;
    _opens++;
    _loading = false;
    _recording = null;
    _timeline = null;
    _trimDraft = null;
    _playing = false;
    _positionMs = 0;
    if (player != null) unawaited(player.pause().catchError((Object _) {}));
    notifyListeners();
  }

  @override
  void dispose() {
    unawaited(_positions?.cancel());
    unawaited(_completed?.cancel());
    final player = _player;
    _player = null;
    if (player != null) unawaited(player.dispose());
    super.dispose();
  }
}
