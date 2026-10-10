import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../app_services.dart';
import '../../domain/recording.dart';
import '../../sync/sync_engine.dart';
import 'backends/audio_backends.dart';
import 'playback_controller.dart';
import 'recording_controller.dart';

/// Everything audio for one open notebook: the recorder, the player and
/// the notebook's recordings (kept current with local edits and sync).
///
/// Lives as long as the editor: a recording continues across page changes
/// and is stopped and saved when the editor closes, and — on Android, where
/// a backgrounded app loses the microphone — when the app is paused.
class NotebookAudio extends ChangeNotifier {
  NotebookAudio(this.services, {required this.notebookId, TargetPlatform? platform})
    : _platform = platform ?? defaultTargetPlatform {
    final backends = services.audio;
    recorder = RecordingController(
      notebookId: notebookId,
      backends: backends,
      blobs: services.blobs,
      repository: services.recordings,
      onSaved: (_) => reload(),
    );
    playback = PlaybackController(
      backends: backends,
      blobs: services.blobs,
      fetch: services.sync.fetchBlob,
    );
    _remote = services.sync.remoteChanges.listen(_onRemoteChanges);
    _lifecycle = AppLifecycleListener(onPause: _onAppPaused);
    reload();
  }

  final AppServices services;
  final String notebookId;
  final TargetPlatform _platform;

  late final RecordingController recorder;
  late final PlaybackController playback;
  late final StreamSubscription<RemoteChanges> _remote;
  late final AppLifecycleListener _lifecycle;

  List<Recording> _recordings = const [];

  /// The notebook's recordings, oldest first.
  List<Recording> get recordings => _recordings;

  AudioBackends get backends => services.audio;

  bool _disposed = false;

  void reload() {
    if (_disposed) return;
    _recordings = services.recordings.listOf(notebookId);
    final open = playback.recording;
    if (open != null && !_recordings.any((r) => r.id == open.id)) playback.close();
    notifyListeners();
  }

  /// Renames recording [id].
  void rename(String id, String title) {
    services.recordings.rename(id, title);
    reload();
  }

  /// Deletes recording [id] (closing it if it is playing).
  void delete(String id) {
    if (playback.recording?.id == id) playback.close();
    services.recordings.delete(id);
    reload();
  }

  /// Opens [recording] in the player and plays it.
  Future<bool> play(Recording recording) => playback.open(recording);

  void _onRemoteChanges(RemoteChanges changes) {
    if (changes.recordingsOfNotebooks.contains(notebookId)) reload();
  }

  /// Mobile systems take the microphone from backgrounded apps (Android 9+
  /// records silence), so a recording is stopped and saved instead.
  void _onAppPaused() {
    if (_platform == TargetPlatform.android || _platform == TargetPlatform.iOS) {
      if (recorder.state.isActive) unawaited(recorder.stop());
      if (playback.playing) unawaited(playback.pause());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _lifecycle.dispose();
    unawaited(_remote.cancel());
    // Saving continues after the editor is gone; services outlive it.
    unawaited(recorder.shutdown());
    recorder.dispose();
    playback.dispose();
    super.dispose();
  }
}
