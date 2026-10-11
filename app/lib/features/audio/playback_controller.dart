import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/blob_store.dart';
import '../../domain/recording.dart';
import 'backends/audio_backends.dart';

/// Plays one recording at a time and relates the playback position to the
/// ink: [wallTime] is the moment being heard, so strokes written after it
/// can be dimmed, and [seekToInk] jumps to when a stroke was written.
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

  /// How far [skip] buttons and ← / → jump.
  static const int skipMs = 10000;

  /// Jumps [deltaMs] forwards (or backwards when negative).
  Future<void> skip(int deltaMs) => seek(_positionMs + deltaMs);

  /// The last problem, for a message.
  String? lastError;

  /// The wall time (epoch ms) being heard, or null without a recording.
  int? get wallTime => _timeline?.wallTimeAt(_positionMs);

  /// Opens [recording] and starts playing it. Returns false (with
  /// [lastError]) if it cannot be played.
  Future<bool> open(Recording recording, {bool autoplay = true}) async {
    lastError = null;
    _loading = true;
    _recording = recording;
    _timeline = recording.timeline;
    _positionMs = 0;
    _playing = false;
    notifyListeners();
    final player = _player ??= _createPlayer();
    try {
      await player.open(recording, blobs, fetch);
    } on Object catch (e) {
      lastError = e is AudioUnavailable ? e.message : 'This recording cannot be played ($e).';
      _loading = false;
      if (_recording == recording) close();
      return false;
    }
    _loading = false;
    if (_rate != 1 && _recording == recording) await player.setRate(_rate);
    if (autoplay && _recording == recording) await play();
    notifyListeners();
    return true;
  }

  AudioPlayback _createPlayer() {
    final player = backends.playback();
    _positions = player.positions.listen((p) {
      _positionMs = p.inMilliseconds;
      notifyListeners();
    });
    _completed = player.completed.listen((_) {
      _playing = false;
      _positionMs = _recording?.durationMs ?? _positionMs;
      notifyListeners();
    });
    return player;
  }

  Future<void> play() async {
    final recording = _recording;
    if (recording == null || _loading) return;
    // Replaying from the end starts again.
    if (_positionMs >= recording.durationMs - 50) await seek(0);
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
    _positionMs = positionMs.clamp(0, recording.durationMs);
    notifyListeners();
    await _player?.seek(Duration(milliseconds: _positionMs));
  }

  /// Plays from shortly before ink written at [createdAt] (epoch ms).
  /// Returns false when it was not written during the open recording.
  Future<bool> seekToInk(int createdAt) async {
    final position = _timeline?.positionOf(createdAt);
    if (position == null) return false;
    await seek(position - leadMs);
    if (!_playing) await play();
    return true;
  }

  /// Stops playback and hides the bar.
  void close() {
    final player = _player;
    _recording = null;
    _timeline = null;
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
