import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

import '../../app_services.dart';
import '../../domain/recording.dart';
import '../../platform/file_export.dart' as platform;
import '../../sync/sync_engine.dart';
import '../documents/export/export_flow.dart' show ExportSaver;
import 'backends/audio_backends.dart';
import 'playback_controller.dart';
import 'recording_controller.dart';
import 'recording_export.dart';
import 'recording_overview.dart';

/// Everything audio for one open notebook: the recorder, the player and
/// the notebook's recordings (kept current with local edits and sync).
///
/// Lives as long as the editor: a recording continues across page changes
/// and is stopped and saved when the editor closes, and — on mobile, where
/// a backgrounded app loses the microphone — when the app is paused unless
/// a foreground service keeps it going (Android).
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
      describe: () => services.notebooks.get(notebookId)?.title ?? '',
    );
    playback = PlaybackController(
      backends: backends,
      blobs: services.blobs,
      fetch: services.sync.fetchBlob,
    );
    overviews = RecordingOverviews(
      blobs: services.blobs,
      fetch: services.sync.fetchBlob,
      contentTimes: (from, to) => services.recordings.contentTimes(notebookId, from: from, to: to),
    );
    playback.addListener(_onPlayback);
    _remote = services.sync.remoteChanges.listen(_onRemoteChanges);
    _lifecycle = AppLifecycleListener(onPause: _onAppPaused);
    reload();
  }

  final AppServices services;
  final String notebookId;
  final TargetPlatform _platform;

  late final RecordingController recorder;
  late final PlaybackController playback;

  /// Waveforms and ink activity of the recordings, for the scrubber.
  late final RecordingOverviews overviews;
  String? _openId;
  late final StreamSubscription<RemoteChanges> _remote;
  late final AppLifecycleListener _lifecycle;

  List<Recording> _recordings = const [];

  /// The notebook's recordings, oldest first.
  List<Recording> get recordings => _recordings;

  AudioBackends get backends => services.audio;

  bool _disposed = false;

  /// Shows a message about something that happened without the user
  /// asking (a recording stopped and saved, or lost, in the background).
  void Function(String message)? onNotice;

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

  /// Deletes several recordings at once.
  void deleteAll(Set<String> ids) {
    if (ids.contains(playback.recording?.id)) playback.close();
    services.recordings.deleteAll(ids);
    reload();
  }

  /// Hands exported files to the user (tests replace it).
  @visibleForTesting
  ExportSaver saveFiles = platform.saveOrShareAll;

  /// Exports [recordings]' audio (save dialog, share sheet or download).
  Future<void> export(BuildContext context, List<Recording> recordings) => exportRecordings(
    context,
    recordings,
    blobs: services.blobs,
    fetch: services.sync.fetchBlob,
    save: saveFiles,
  );

  /// Size of [recording]'s audio on this device (null while not here).
  int? sizeOf(Recording recording) => services.blobs.sizeOf(recording.blob);

  /// Opens [recording] in the player and plays it.
  Future<bool> play(Recording recording) => playback.open(recording);

  /// Plays from when ink created at [createdAt] (epoch ms) was written:
  /// in the open recording if it covers that time, else in the (latest)
  /// recording of this notebook that does. False if none does.
  Future<bool> playInk(int createdAt) async {
    final open = playback.recording;
    if (open != null && open.timeline.covers(createdAt)) return playback.seekToInk(createdAt);
    final other = _recordings.reversed.where((r) => r.timeline.covers(createdAt)).firstOrNull;
    if (other == null) return false;
    if (!await playback.open(other, autoplay: false)) return false;
    return playback.seekToInk(createdAt);
  }

  /// Ink times are read afresh whenever a recording is opened (the
  /// notebook may have been edited since).
  void _onPlayback() {
    final id = playback.recording?.id;
    if (id == _openId) return;
    _openId = id;
    if (id != null) overviews.invalidateInk();
  }

  void _onRemoteChanges(RemoteChanges changes) {
    if (changes.recordingsOfNotebooks.contains(notebookId)) reload();
  }

  /// Mobile systems take the microphone from backgrounded apps (Android 9+
  /// records silence). With its foreground service running (see
  /// `RecordingKeepAlive`) an Android recording continues — screen off,
  /// another app in front — controlled from its notification; otherwise it
  /// is stopped and saved.
  void _onAppPaused() {
    if (_platform == TargetPlatform.android || _platform == TargetPlatform.iOS) {
      if (recorder.state.isActive && !recorder.recordsInBackground) {
        unawaited(
          recorder.stop().then((saved) {
            final message = saved != null
                ? 'Recording stopped in the background and saved as “${saved.title}”'
                : recorder.lastError;
            if (message != null && !_disposed) onNotice?.call(message);
          }),
        );
      }
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
    playback.removeListener(_onPlayback);
    playback.dispose();
    overviews.dispose();
    super.dispose();
  }
}
