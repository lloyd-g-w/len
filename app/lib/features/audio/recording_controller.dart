import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../core/clock.dart';
import '../../data/blob_store.dart';
import '../../data/recording_repository.dart';
import '../../domain/recording.dart';
import '../../domain/waveform.dart';
import 'backends/audio_backends.dart';
import 'keep_alive_link.dart';
import 'recording_journal.dart';
import 'recording_parts.dart';

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
      final inUse = busy?.call();
      if (inUse != null) throw AudioUnavailable(inUse);
      final reason = await backends.unavailable?.call();
      if (reason != null) throw AudioUnavailable(reason);
      if (!await capture.requestPermission()) {
        throw const AudioUnavailable('Microphone access was not allowed.');
      }
      await _keepAlive.prepare();
      final format = await capture.format();
      final spool = format.recoverable ? await backends.spool?.call() : null;
      if (_disposed) throw const _ShutDown();
      final now = clock.nowMs();
      final parts = _parts = RecordingParts(
        RecordingJournal(
          recordingId: clock.newId(),
          notebookId: notebookId,
          title: defaultTitle(now),
          mime: format.mime,
          openSince: now,
        ),
        blobs: blobs,
        repository: repository,
        spool: spool,
        extension: format.extension,
      );
      active.add(parts.journal.recordingId);
      await capture.start(await parts.nextFile());
      if (_disposed) {
        // Shut down while starting (the editor closed during the
        // permission prompt): don't leave the microphone running.
        await capture.stop().then((audio) => audio == null ? null : capture.discard(audio));
        throw const _ShutDown();
      }
    } on Object catch (e) {
      if (e is! _ShutDown) {
        lastError = e is AudioUnavailable ? e.message : 'Could not start recording ($e).';
      }
      await _closeParts();
      _set(RecorderState.idle);
      return false;
    }
    _segments.clear();
    _waveform.clear();
    _fileStartMs = 0;
    _segmentStart = clock.nowMs();
    await _journalTimeline();
    _levels = capture.levels.listen((l) {
      if (_state != RecorderState.recording) return;
      _level = l;
      _waveform.add(elapsedMs, l);
      notifyListeners();
    });
    _ticker = Timer.periodic(const Duration(milliseconds: 250), (_) => _tick());
    _set(RecorderState.recording);
    await _showKeepAlive();
    return true;
  }

  /// Starts or updates the background keep-alive for the current state.
  Future<void> _showKeepAlive() async {
    if (!_state.isActive) return;
    await _keepAlive.show(
      title: describe?.call() ?? '',
      paused: _state == RecorderState.paused,
      elapsedMs: elapsedMs,
    );
  }

  Future<void> pause() async {
    if (_state != RecorderState.recording) return;
    _closeSegment();
    _level = 0;
    _set(RecorderState.paused);
    unawaited(_journalTimeline());
    try {
      await _capture?.pause();
    } on Object catch (e) {
      // (Called from the notification too: never an unhandled error.)
      lastError = 'Could not pause recording ($e).';
      notifyListeners();
    }
    await _showKeepAlive();
  }

  Future<void> resume() async {
    if (_state != RecorderState.paused) return;
    try {
      await _capture?.resume();
    } on Object catch (e) {
      lastError = 'Could not resume recording ($e).';
      notifyListeners();
      return;
    }
    if (_state != RecorderState.paused) return; // Stopped meanwhile.
    _segmentStart = clock.nowMs();
    _set(RecorderState.recording);
    unawaited(_journalTimeline());
    await _showKeepAlive();
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
    final parts = _parts;
    var failed = false;
    try {
      await _work;
      final audio = await _capture?.stop();
      if (parts == null) return null;
      final measured = segments.fold(0, (sum, s) => sum + s.durationMs) - _fileStartMs;
      if (!parts.saved && (audio?.durationMs ?? measured) < minimumMs) {
        if (audio != null) await _capture?.discard(audio);
        return null;
      }
      await parts.timeline(segments, null);
      await parts.store(audio, measured, waveform: _waveform.build, capture: _capture!);
      if (!parts.saved) return null;
      final recording = repository.get(parts.journal.recordingId);
      if (recording != null) onSaved?.call(recording);
      return recording;
    } on Object catch (e) {
      lastError = 'The recording could not be saved ($e).';
      failed = true;
      return null;
    } finally {
      // A recording that failed to save stays in the spool, to recover.
      await _closeParts(keepFiles: failed);
      // Saved (or failed): the app may be suspended again from here on.
      await _keepAlive.hide();
      _set(RecorderState.idle);
    }
  }

  /// Forgets the recording's spool files (stored, or not worth keeping).
  Future<void> _closeParts({bool keepFiles = false}) async {
    final parts = _parts;
    _parts = null;
    if (parts == null) return;
    active.remove(parts.journal.recordingId);
    if (keepFiles) return;
    try {
      await parts.close();
    } on Object {
      // Left for the next start's recovery check to clean up.
    }
  }

  void _tick() {
    unawaited(nextPartIfDue());
    notifyListeners();
  }

  /// Moves on to the next part once the current one holds [partMs] of
  /// audio (checked by the ticker; tests call it directly).
  Future<void> nextPartIfDue() async {
    if (_state == RecorderState.recording && _work == null && elapsedMs - _fileStartMs >= partMs) {
      try {
        await (_work = _split());
      } finally {
        _work = null;
      }
    } else {
      await _work;
    }
  }

  /// Moves the capture on to a new file and stores the finished one.
  Future<void> _split() async {
    final parts = _parts, capture = _capture;
    if (parts == null || capture == null) return;
    try {
      final at = elapsedMs;
      final audio = await capture.split(await parts.nextFile());
      final measured = at - _fileStartMs;
      _fileStartMs = at;
      await parts.store(audio, measured, waveform: _waveform.build, capture: capture);
    } on Object catch (e) {
      // The audio stays in its file; stop stores what it can.
      lastError = 'Part of the recording could not be stored ($e).';
    }
  }

  /// Journals the capture's stretches (for recovery).
  Future<void> _journalTimeline() async {
    try {
      await _parts?.timeline(List.of(_segments), _segmentStart);
    } on Object {
      // Recovery only: never stop a recording over it.
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

/// [RecordingController.start] gave up because the controller shut down.
class _ShutDown implements Exception {
  const _ShutDown();
}
