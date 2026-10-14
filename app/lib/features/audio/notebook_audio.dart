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
import 'playback_session.dart';
import 'recording_controller.dart';
import 'recording_export.dart';
import 'recording_overview.dart';
import 'trim_release.dart';

/// Everything audio for one open notebook: the recorder, the player and
/// the notebook's recordings (kept current with local edits and sync).
///
/// One per open notebook, shared by its editors (see `SharedNotebook`);
/// `microphoneBusy` keeps to one recorder at a time across notebooks. Lives
/// as long as the notebook is open: a recording continues across page
/// changes and is stopped and saved when its last editor closes, and — on
/// mobile, where a backgrounded app loses the microphone — when the app is
/// paused unless a foreground service keeps it going (Android). Playback
/// likewise goes on in the background with the system's media controls.
class NotebookAudio extends ChangeNotifier {
  NotebookAudio(
    this.services, {
    required this.notebookId,
    TargetPlatform? platform,
    String? Function()? microphoneBusy,
  }) : _platform = platform ?? defaultTargetPlatform {
    final backends = services.audio;
    recorder = RecordingController(
      notebookId: notebookId,
      backends: backends,
      blobs: services.blobs,
      repository: services.recordings,
      onSaved: (_) => reload(),
      describe: () => services.notebooks.get(notebookId)?.title ?? '',
      busy: microphoneBusy,
    );
    playback = PlaybackController(
      backends: backends,
      blobs: services.blobs,
      fetch: services.sync.fetchBlob,
    );
    session = PlaybackSession(
      playback,
      create: backends.mediaControls,
      album: () => services.notebooks.get(notebookId)?.title ?? '',
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

  /// The system's media controls for [playback] (notification, lock
  /// screen, media keys); with them up, playback goes on in the background.
  late final PlaybackSession session;

  /// Waveforms and ink activity of the recordings, for the scrubber.
  late final RecordingOverviews overviews;

  /// Height of the audio strip docked along the bottom of the editor (0
  /// while hidden), set by `AudioLayer`: chrome that peeks above the bottom
  /// edge (the page indicator, tips) sits above it.
  final stripHeight = ValueNotifier<double>(0);
  String? _openId;
  late final StreamSubscription<RemoteChanges> _remote;
  late final AppLifecycleListener _lifecycle;

  List<Recording> _recordings = const [];

  /// The notebook's recordings, oldest first.
  List<Recording> get recordings => _recordings;

  AudioBackends get backends => services.audio;

  bool _disposed = false;

  /// Set by [dispose] when it stopped a recording: completes once that
  /// recording is saved (or failed to save).
  Future<void>? get saving => _saving;
  Future<void>? _saving;

  /// Shows a message about something that happened without the user
  /// asking (a recording stopped and saved, or lost, in the background).
  void Function(String message)? onNotice;

  void reload() {
    if (_disposed) return;
    // The recording being made is saved part by part; it is listed once
    // it is finished.
    final recording = recorder.recordingId;
    _recordings = [
      for (final r in services.recordings.listOf(notebookId))
        if (r.id != recording) r,
    ];
    final open = playback.recording;
    if (open != null) {
      final current = _recordings.where((r) => r.id == open.id).firstOrNull;
      current == null ? playback.close() : playback.update(current);
    }
    notifyListeners();
  }

  /// Renames recording [id].
  void rename(String id, String title) {
    services.recordings.rename(id, title);
    reload();
  }

  /// Keeps only audio [startMs]…[endMs] of recording [id] (`0` and its
  /// duration keep all of it). Not in the editor's undo history (like
  /// renaming): the trim is undone by trimming back (see `TrimActions`).
  void trim(String id, int startMs, int endMs) {
    services.recordings.trim(id, startMs, endMs);
    reload();
  }

  /// The bytes freeing [recording]'s audio outside its trim would release
  /// on this device, or null when no part lies wholly outside it.
  int? releasableSize(Recording recording) => releasableBytes(
    recording,
    blobs: services.blobs,
    shared: services.recordings.audioBlobsBesides(recording.id),
  );

  /// Drops recording [id]'s parts lying wholly outside its trim (see
  /// [releaseOutsideTrim]); returns the recording as it was, for [restore].
  Future<Recording?> freeUpSpace(String id) async {
    final released = await releaseOutsideTrim(
      id,
      repository: services.recordings,
      blobs: services.blobs,
      fetch: services.sync.fetchBlob,
    );
    reload();
    return released?.before;
  }

  /// Puts back [recording] as it was before [freeUpSpace] (its blobs stay
  /// until garbage collection's grace period has passed).
  void restore(Recording recording) {
    services.recordings.replace(recording);
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

  /// Whether recordings can also be saved through the system's save dialog
  /// ("Save to device" beside Share, Android; tests set it).
  bool canSaveToDevice = platform.canSaveToDevice;

  /// Exports [recordings]' audio (save dialog, share sheet or download;
  /// with [toDevice] the system's save dialog, see [canSaveToDevice]).
  Future<void> export(BuildContext context, List<Recording> recordings, {bool toDevice = false}) =>
      exportRecordings(
        context,
        recordings,
        blobs: services.blobs,
        fetch: services.sync.fetchBlob,
        save: saveFiles,
        toDevice: toDevice,
      );

  /// Size of [recording]'s audio on this device (null while not here).
  int? sizeOf(Recording recording) {
    var total = 0;
    for (final sha in recording.blobs) {
      final size = services.blobs.sizeOf(sha);
      if (size == null) return null;
      total += size;
    }
    return total;
  }

  /// Opens [recording] in the player and plays it.
  Future<bool> play(Recording recording) => playback.open(recording);

  /// Plays from when ink created at [createdAt] (epoch ms) was written:
  /// in the open recording if it covers that time, else in the (latest)
  /// recording of this notebook that does. False if none does.
  Future<bool> playInk(int createdAt) async {
    final open = playback.recording;
    if (open != null && open.inkPositionOf(createdAt) != null) return playback.seekToInk(createdAt);
    final other = _recordings.reversed.where((r) => r.inkPositionOf(createdAt) != null).firstOrNull;
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
  /// is stopped and saved. Playback continues while its media controls are
  /// up (Android's media session service), else it pauses.
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
      if (playback.playing && !session.background) unawaited(playback.pause());
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _lifecycle.dispose();
    unawaited(_remote.cancel());
    // Saving continues after the editor is gone; services outlive it.
    final recording = recorder.state != RecorderState.idle;
    final shutdown = recorder.shutdown();
    if (recording) _saving = shutdown;
    unawaited(shutdown);
    recorder.dispose();
    playback.removeListener(_onPlayback);
    session.dispose();
    playback.dispose();
    overviews.dispose();
    stripHeight.dispose();
    super.dispose();
  }
}
