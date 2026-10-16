import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/clock.dart';
import '../../data/blob_store.dart';
import '../../data/recording_repository.dart';
import '../../data/spool_storage.dart';
import '../../domain/recording.dart';
import '../../domain/waveform.dart';
import 'backends/audio_backends.dart';
import 'keep_alive_link.dart';
import 'recorder_state.dart';
import 'recording_journal.dart';
import 'recording_parts.dart';
import 'recording_stopwatch.dart';

export 'recorder_state.dart';

part 'recording_start.dart';
part 'recording_storage.dart';

/// Records audio for one notebook: start / pause / resume / stop, the
/// elapsed time and the input level. The audio is stored in parts of
/// [partMs] (see [RecordingParts]): each finished part becomes a blob and
/// the `recordings` row — whose segments map audio time to wall time (see
/// [RecordingTimeline]) — is saved with the parts so far, so they sync
/// while recording continues; stop stores the last part.
class RecordingController extends ChangeNotifier {
  RecordingController({
    required this.notebookId,
    required this.backends,
    required this.blobs,
    required this.repository,
    Clock? clock,
    this.onSaved,
    this.describe,
    this.busy,
    this.partMs = defaultPartMs,
  }) : clock = clock ?? repository.clock;

  final String notebookId;
  final AudioBackends backends;
  final BlobStore blobs;
  final RecordingRepository repository;
  final Clock clock;

  /// Called with each recording once it is stored.
  final void Function(Recording recording)? onSaved;

  /// What is being recorded (the notebook's title), for the background
  /// notification.
  final String Function()? describe;

  /// Why the microphone can't be used now (another notebook is recording),
  /// or null when it can.
  final String? Function()? busy;

  /// Recordings shorter than this are discarded (an accidental tap).
  static const int minimumMs = 500;

  /// How much audio goes into one part.
  static const int defaultPartMs = 5 * 60 * 1000;

  /// Audio per part: once the current capture file holds this much, the
  /// capture moves on to a new file and the finished one is stored.
  final int partMs;

  /// Ids of recordings being made in this app (not interrupted ones).
  static final Set<String> active = {};

  RecordingParts? _parts;

  /// The id of the recording being made (its row exists once a part is
  /// stored), or null — also once it is being saved.
  String? get recordingId => _state == RecorderState.saving ? null : _parts?.journal.recordingId;

  /// Audio position at which the current capture file began.
  int _fileStartMs = 0;

  /// The part being stored, or null: none (so no future outlives the zone
  /// it was made in, e.g. a widget test's fake time — awaiting a completed
  /// future made there never resumes outside it).
  Future<void>? _work;

  RecorderState _state = RecorderState.idle;
  RecorderState get state => _state;

  AudioCapture? _capture;
  late final KeepAliveLink _keepAlive = KeepAliveLink(
    backends.keepAlive,
    onAction: (action) => unawaited(switch (action) {
      KeepAliveAction.pause => pause(),
      KeepAliveAction.resume => resume(),
      _ => stop(),
    }),
  );

  /// Whether the running recording continues while the app is in the
  /// background (Android: its foreground service is up).
  bool get recordsInBackground => _keepAlive.background;

  /// Tries once more to start the keep-alive if it is not up (it could not
  /// start, or failed since): called as the app is about to go to the
  /// background, while Android still lets a foreground service start.
  /// Completes with [recordsInBackground].
  Future<bool> keepInBackground() {
    if (!_state.isActive || recordsInBackground) return Future.value(recordsInBackground);
    return _retryingKeepAlive ??= _showKeepAlive().then((_) {
      _retryingKeepAlive = null;
      return recordsInBackground;
    });
  }

  /// The [keepInBackground] attempt under way, if any.
  Future<bool>? get retryingKeepAlive => _retryingKeepAlive;
  Future<bool>? _retryingKeepAlive;
  StreamSubscription<double>? _levels;
  Timer? _ticker;

  /// The stretches recorded between pauses.
  late final RecordingStopwatch _stopwatch = RecordingStopwatch(clock);

  double _level = 0;

  /// The loudness outline of the current recording (see [Waveform]).
  final WaveformBuilder _waveform = WaveformBuilder();

  /// Input level, 0…1.
  double get level => _level;

  /// Why recording can't start when the microphone permission is refused:
  /// the way to allow it (with a Settings button where the system has a
  /// page for it, see `platform/system_settings`).
  static const String microphoneDenied = kIsWeb
      ? 'Allow microphone access for Len in the browser’s site settings'
      : 'Allow microphone access for Len in system settings';

  /// The last problem (permission refused, recorder failed), for a message.
  String? lastError;

  /// Audio recorded so far, in ms.
  int get elapsedMs => _stopwatch.elapsedMs;

  /// Starts a new recording. Returns false (with [lastError]) if it could
  /// not start.
  Future<bool> start() {
    if (_state != RecorderState.idle) return Future.value(false);
    final starting = _starting = _start();
    unawaited(
      starting.whenComplete(() {
        if (identical(_starting, starting)) _starting = null;
      }),
    );
    return starting;
  }

  /// The start under way, if any ([shutdown] lets it settle first).
  Future<bool>? _starting;

  /// A new input [level] while recording: the meter and the waveform.
  void _onLevel(double level) {
    if (_state != RecorderState.recording) return;
    _level = level;
    _waveform.add(elapsedMs, level);
    notifyListeners();
  }

  /// Whether a pause or resume is under way (further taps are ignored).
  bool _switching = false;

  /// Pauses the capture, then shows *paused*. Returns false (with
  /// [lastError], still recording) if the capture could not pause.
  Future<bool> pause() async {
    if (_state != RecorderState.recording || _switching) return false;
    lastError = null;
    _switching = true;
    try {
      // A split restarts the recorder on some platforms (Linux, web): a
      // pause sent meanwhile would be lost, the "paused" audio kept.
      await _work;
      if (_state != RecorderState.recording) return false; // Stopped meanwhile.
      await _capture?.pause();
    } on Object catch (e) {
      // (Called from the notification too: never an unhandled error.)
      debugPrint('Recording failed to pause: $e');
      lastError = 'Couldn’t pause the recording';
      notifyListeners();
      return false;
    } finally {
      _switching = false;
    }
    if (_state != RecorderState.recording) return false; // Stopped meanwhile.
    _stopwatch.halt();
    _level = 0;
    _set(RecorderState.paused);
    unawaited(_journalTimeline());
    await _showKeepAlive();
    return true;
  }

  /// Resumes the capture, then shows *recording*. Returns false (with
  /// [lastError], still paused) if the capture could not resume.
  Future<bool> resume() async {
    if (_state != RecorderState.paused || _switching) return false;
    lastError = null;
    _switching = true;
    try {
      await _capture?.resume();
    } on Object catch (e) {
      debugPrint('Recording failed to resume: $e');
      lastError = 'Couldn’t resume the recording';
      notifyListeners();
      return false;
    } finally {
      _switching = false;
    }
    if (_state != RecorderState.paused) return false; // Stopped meanwhile.
    _stopwatch.run();
    _set(RecorderState.recording);
    unawaited(_journalTimeline());
    await _showKeepAlive();
    return true;
  }

  /// Stops and stores the recording. Returns it, or null if nothing was
  /// kept (too short, or the recorder failed).
  Future<Recording?> stop() {
    if (!_state.isActive) return Future.value();
    final stopping = _stopping = _stop();
    unawaited(
      stopping.whenComplete(() {
        if (identical(_stopping, stopping)) _stopping = null;
      }),
    );
    return stopping;
  }

  /// The stop under way, if any ([shutdown] lets it finish saving before
  /// the recorder goes).
  Future<Recording?>? _stopping;

  void _tick() {
    unawaited(nextPartIfDue());
    notifyListeners();
  }

  /// Moves on to the next part once the current one holds [partMs] of
  /// audio (checked by the ticker; tests call it directly).
  Future<void> nextPartIfDue() async {
    if (_state == RecorderState.recording &&
        !_switching &&
        _work == null &&
        elapsedMs - _fileStartMs >= partMs) {
      try {
        await (_work = _split());
      } finally {
        _work = null;
      }
    } else {
      await _work;
    }
  }

  /// "Recording 14:05".
  static String defaultTitle(int epochMs) {
    final at = DateTime.fromMillisecondsSinceEpoch(epochMs);
    String two(int n) => n.toString().padLeft(2, '0');
    return 'Recording ${two(at.hour)}:${two(at.minute)}';
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
    // A start under way gives up (or, past the point of no return, its
    // recording is stopped and saved here) before the recorder goes.
    await _starting;
    if (_state.isActive) await stop();
    await _stopping; // Stopped just before (Stop, then Back): saved first.
    unawaited(_levels?.cancel());
    await _capture?.dispose();
    _capture = null;
    await _keepAlive.dispose();
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
