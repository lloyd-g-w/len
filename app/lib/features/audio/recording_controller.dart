import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';

import '../../core/clock.dart';
import '../../data/blob_store.dart';
import '../../data/recording_repository.dart';
import '../../domain/recording.dart';
import '../../domain/waveform.dart';
import 'backends/audio_backends.dart';

/// Where a [RecordingController] is.
enum RecorderState {
  idle,

  /// Asking for permission / starting the recorder.
  starting,
  recording,
  paused,

  /// Storing the finished recording.
  saving;

  /// Recording or paused (the bar shows the recording controls).
  bool get isActive => this == recording || this == paused;
}

/// Records audio for one notebook: start / pause / resume / stop, the
/// elapsed time and the input level, and on stop stores the audio as a
/// blob plus a `recordings` row whose segments map audio time to wall time
/// (see [RecordingTimeline]).
class RecordingController extends ChangeNotifier {
  RecordingController({
    required this.notebookId,
    required this.backends,
    required this.blobs,
    required this.repository,
    Clock? clock,
    this.onSaved,
  }) : clock = clock ?? repository.clock;

  final String notebookId;
  final AudioBackends backends;
  final BlobStore blobs;
  final RecordingRepository repository;
  final Clock clock;

  /// Called with each recording once it is stored.
  final void Function(Recording recording)? onSaved;

  /// Recordings shorter than this are discarded (an accidental tap).
  static const int minimumMs = 500;

  RecorderState _state = RecorderState.idle;
  RecorderState get state => _state;

  AudioCapture? _capture;
  StreamSubscription<double>? _levels;
  Timer? _ticker;

  /// Closed segments of the current recording.
  final List<RecordingSegment> _segments = [];

  /// Wall time the running segment started (while recording).
  int? _segmentStart;

  double _level = 0;

  /// The loudness outline of the current recording (see [Waveform]).
  final WaveformBuilder _waveform = WaveformBuilder();

  /// Input level, 0…1.
  double get level => _level;

  /// The last problem (permission refused, recorder failed), for a message.
  String? lastError;

  /// Audio recorded so far, in ms.
  int get elapsedMs {
    final closed = _segments.fold(0, (sum, s) => sum + s.durationMs);
    final start = _segmentStart;
    return start == null ? closed : closed + (clock.nowMs() - start).clamp(0, 1 << 30);
  }

  /// Starts a new recording. Returns false (with [lastError]) if it could
  /// not start.
  Future<bool> start() async {
    if (_state != RecorderState.idle) return false;
    _set(RecorderState.starting);
    lastError = null;
    final capture = _capture ??= backends.capture();
    try {
      final reason = await backends.unavailable?.call();
      if (reason != null) throw AudioUnavailable(reason);
      if (!await capture.requestPermission()) {
        throw const AudioUnavailable('Microphone access was not allowed.');
      }
      await capture.start();
    } on Object catch (e) {
      lastError = e is AudioUnavailable ? e.message : 'Could not start recording ($e).';
      _set(RecorderState.idle);
      return false;
    }
    _segments.clear();
    _waveform.clear();
    _segmentStart = clock.nowMs();
    _levels = capture.levels.listen((l) {
      if (_state != RecorderState.recording) return;
      _level = l;
      _waveform.add(elapsedMs, l);
      notifyListeners();
    });
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => notifyListeners());
    _set(RecorderState.recording);
    return true;
  }

  Future<void> pause() async {
    if (_state != RecorderState.recording) return;
    _closeSegment();
    _level = 0;
    _set(RecorderState.paused);
    await _capture?.pause();
  }

  Future<void> resume() async {
    if (_state != RecorderState.paused) return;
    _segmentStart = clock.nowMs();
    _set(RecorderState.recording);
    await _capture?.resume();
  }

  /// Stops and stores the recording. Returns it, or null if nothing was
  /// kept (too short, or the recorder failed).
  Future<Recording?> stop() async {
    if (!_state.isActive) return null;
    _closeSegment();
    _ticker?.cancel();
    unawaited(_levels?.cancel());
    _levels = null;
    _level = 0;
    _set(RecorderState.saving);
    final segments = List.of(_segments);
    _segments.clear();
    try {
      final audio = await _capture?.stop();
      if (audio == null) return null;
      final duration = segments.fold(0, (sum, s) => sum + s.durationMs);
      if (duration < minimumMs) {
        await _capture?.discard(audio);
        return null;
      }
      // Streamed into the blob store (no full copy in memory natively).
      final sha = await blobs.putFile(audio.file, mime: audio.mime);
      await _capture?.discard(audio);
      // Small (≈ 36 KB per hour): hashed in place, no isolate.
      final waveform = await blobs.putFile(
        XFile.fromData(_waveform.build(duration).encode(), mimeType: Waveform.mime),
        mime: Waveform.mime,
      );
      final recording = repository.create(
        notebookId: notebookId,
        blob: sha,
        mime: audio.mime,
        title: defaultTitle(segments.first.startedAt),
        segments: segments,
        waveform: waveform,
      );
      onSaved?.call(recording);
      return recording;
    } on Object catch (e) {
      lastError = 'The recording could not be saved ($e).';
      return null;
    } finally {
      _set(RecorderState.idle);
    }
  }

  /// "Recording 14:05".
  static String defaultTitle(int epochMs) {
    final at = DateTime.fromMillisecondsSinceEpoch(epochMs);
    String two(int n) => n.toString().padLeft(2, '0');
    return 'Recording ${two(at.hour)}:${two(at.minute)}';
  }

  void _closeSegment() {
    final start = _segmentStart;
    if (start == null) return;
    _segments.add(RecordingSegment(start, (clock.nowMs() - start).clamp(0, 1 << 30)));
    _segmentStart = null;
  }

  bool _disposed = false;

  void _set(RecorderState state) {
    _state = state;
    if (!_disposed) notifyListeners();
  }

  /// Stops and saves a running recording (the editor is closing), then
  /// releases the recorder.
  Future<void> shutdown() async {
    _disposed = true;
    _ticker?.cancel();
    if (_state.isActive) await stop();
    unawaited(_levels?.cancel());
    await _capture?.dispose();
    _capture = null;
  }

  @override
  void notifyListeners() {
    if (!_disposed) super.notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    super.dispose();
  }
}
