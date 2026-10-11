import 'package:flutter/foundation.dart';

import '../../../platform/audio_files.dart';
import 'android_keep_alive.dart';
import 'audio_backends.dart';
import 'audioplayers_playback.dart';
import 'record_capture.dart';

/// The real audio backends: `record` for capture, `audioplayers` for
/// playback, and on Android a foreground service that keeps recording
/// while the app is in the background.
AudioBackends platformAudioBackends() => AudioBackends(
  capture: RecordCapture.new,
  playback: AudioplayersPlayback.new,
  unavailable: recordingUnavailableReason,
  keepAlive: !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? AndroidKeepAlive.new
      : null,
);
