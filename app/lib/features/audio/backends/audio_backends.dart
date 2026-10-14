import 'dart:async';

import 'package:cross_file/cross_file.dart';

import '../../../data/blob_store.dart';
import '../../../data/spool_storage.dart';
import '../../../domain/recording.dart';
import '../../../platform/media_controls_api.dart';

/// A finished capture file: the audio (a file natively, a blob URL in
/// browsers), its MIME type and, when the backend knows it exactly (ADTS
/// frames counted), its duration.
typedef CapturedAudio = ({XFile file, String mime, int? durationMs});

/// What an [AudioCapture] writes: MIME type and file extension, and
/// whether its files are [recoverable] — readable up to the last whole
/// frame while still being written (raw AAC in ADTS frames), so a capture
/// cut off by the app being killed can be saved afterwards.
typedef CaptureFormat = ({String mime, String extension, bool recoverable});

/// Thrown when recording or playback cannot work on this device; the
/// message is shown to the user.
class AudioUnavailable implements Exception {
  const AudioUnavailable(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Captures microphone audio to a file. Implemented with `package:record`
/// ([RecordCapture]); tests use fakes.
abstract interface class AudioCapture {
  /// Asks for microphone access where the platform needs it (Android,
  /// browsers); false when refused.
  Future<bool> requestPermission();

  /// Chooses the format of the next capture. Throws [AudioUnavailable]
  /// if there is none.
  Future<CaptureFormat> format();

  /// Starts capturing into file [path] (null: wherever the backend likes,
  /// e.g. memory in browsers). Throws [AudioUnavailable] if it cannot.
  Future<void> start(String? path);

  Future<void> pause();
  Future<void> resume();

  /// Finishes the current file and goes on capturing into [nextPath]
  /// with as little audio lost in between as the platform allows (none
  /// where the recorder streams to Len). Returns the finished file; null
  /// if nothing was captured.
  Future<CapturedAudio?> split(String? nextPath);

  /// Finishes the capture; null if nothing was captured.
  Future<CapturedAudio?> stop();

  /// Input level from 0 (silence) to 1 while capturing.
  Stream<double> get levels;

  /// Removes a capture file once it has been stored as a blob.
  Future<void> discard(CapturedAudio audio);

  Future<void> dispose();
}

/// Plays a recording's audio. Implemented with `package:audioplayers`
/// ([AudioplayersPlayback]); tests use fakes.
abstract interface class AudioPlayback {
  /// Loads [recording]'s audio from [blobs] (fetching it first with
  /// [fetch] if it is not on the device). Throws [AudioUnavailable] when
  /// the audio is missing or cannot be played.
  Future<void> open(Recording recording, BlobStore blobs, Future<bool> Function(String) fetch);

  Future<void> play();
  Future<void> pause();
  Future<void> seek(Duration position);

  /// Plays at [rate] × normal speed (pitch kept where the platform can).
  Future<void> setRate(double rate);

  /// Plays at [volume] (0…1) of the recording's loudness (ducking).
  Future<void> setVolume(double volume);

  /// The playback position, a few times a second while playing.
  Stream<Duration> get positions;

  /// Fires when playback reaches the end.
  Stream<void> get completed;

  Future<void> dispose();
}

/// What the user did in a [RecordingKeepAlive]'s notification, or
/// [failed] when it stopped being able to keep the recording alive.
enum KeepAliveAction { pause, resume, stop, failed }

/// Keeps a recording running while the app is in the background. On
/// Android a foreground service of type "microphone" with a notification
/// (time, pause / resume, stop): without one the system hands
/// backgrounded apps silence. Other platforms need none.
abstract interface class RecordingKeepAlive {
  /// Asks once for what it needs (Android 13+: permission to show the
  /// notification; recording works without it, the notification is then
  /// only listed in the system's task manager).
  Future<void> prepare();

  /// Starts it for a recording of [title], or updates it. [elapsedMs] is
  /// the audio recorded so far. False if it could not start.
  Future<bool> show({required String title, required bool paused, required int elapsedMs});

  /// Ends it (the recording stopped).
  Future<void> hide();

  /// Taps on the notification's buttons, and failures.
  Stream<KeepAliveAction> get actions;

  Future<void> dispose();
}

/// Creates the audio backends of an editor. They are made only when the
/// user records or plays something, so platforms (and tests) that never
/// do never touch the audio plugins.
class AudioBackends {
  const AudioBackends({
    required this.capture,
    required this.playback,
    this.unavailable,
    this.keepAlive,
    this.mediaControls,
    this.spool,
  });

  final AudioCapture Function() capture;
  final AudioPlayback Function() playback;

  /// Why recording cannot work here (e.g. missing tools on Linux), or null.
  final Future<String?> Function()? unavailable;

  /// Keeps recordings alive in the background, where a platform needs it
  /// (Android); null elsewhere.
  final RecordingKeepAlive Function()? keepAlive;

  /// The system's media controls for the player (Android's notification
  /// and lock screen, MPRIS, the browser's); null where there are none.
  final MediaControls Function()? mediaControls;

  /// Opens the directory recordings in progress are written to, so they
  /// can be recovered after the app was killed; null (or returning null)
  /// where there is none (browsers).
  final Future<SpoolStorage?> Function()? spool;
}
