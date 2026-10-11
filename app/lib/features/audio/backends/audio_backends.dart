import 'dart:async';

import 'package:cross_file/cross_file.dart';

import '../../../data/blob_store.dart';
import '../../../domain/recording.dart';

/// A finished capture: the audio file (a temporary file natively, a blob
/// URL in browsers) and its MIME type.
typedef CapturedAudio = ({XFile file, String mime});

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

  /// Starts capturing. Throws [AudioUnavailable] if it cannot.
  Future<void> start();

  Future<void> pause();
  Future<void> resume();

  /// Finishes the capture; null if nothing was captured.
  Future<CapturedAudio?> stop();

  /// Input level from 0 (silence) to 1 while capturing.
  Stream<double> get levels;

  /// Removes the temporary capture once it has been stored as a blob.
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

  /// The playback position, a few times a second while playing.
  Stream<Duration> get positions;

  /// Fires when playback reaches the end.
  Stream<void> get completed;

  Future<void> dispose();
}

/// Creates the audio backends of an editor. They are made only when the
/// user records or plays something, so platforms (and tests) that never
/// do never touch the audio plugins.
class AudioBackends {
  const AudioBackends({required this.capture, required this.playback, this.unavailable});

  final AudioCapture Function() capture;
  final AudioPlayback Function() playback;

  /// Why recording cannot work here (e.g. missing tools on Linux), or null.
  final Future<String?> Function()? unavailable;
}
