import '../../../platform/audio_files.dart';
import 'audio_backends.dart';
import 'audioplayers_playback.dart';
import 'record_capture.dart';

/// The real audio backends: `record` for capture, `audioplayers` for
/// playback.
AudioBackends platformAudioBackends() => AudioBackends(
  capture: RecordCapture.new,
  playback: AudioplayersPlayback.new,
  unavailable: recordingUnavailableReason,
);
