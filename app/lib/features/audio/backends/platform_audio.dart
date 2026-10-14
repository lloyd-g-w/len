import 'package:flutter/foundation.dart';

import '../../../platform/audio_files.dart';
import '../../../platform/media_controls.dart';
import '../../../platform/spool_storage.dart';
import 'android_keep_alive.dart';
import 'audio_backends.dart';
import 'audioplayers_playback.dart';
import 'record_capture.dart';

/// The real audio backends: `record` for capture, `audioplayers` for
/// playback, and on Android a foreground service that keeps recording
/// while the app is in the background; the system's media controls for
/// the player; in-progress recordings are spooled under the app support
/// directory (none in browsers).
AudioBackends platformAudioBackends() => AudioBackends(
  capture: RecordCapture.new,
  playback: AudioplayersPlayback.new,
  unavailable: recordingUnavailableReason,
  keepAlive: !kIsWeb && defaultTargetPlatform == TargetPlatform.android
      ? AndroidKeepAlive.new
      : null,
  mediaControls: systemMediaControls(),
  spool: openRecordingSpool,
);
