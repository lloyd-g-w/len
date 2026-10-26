import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../app_services.dart';
import '../../data/schema_reset.dart';
import '../../platform/browser_storage.dart';
import '../../ui/messages.dart';
import '../../ui/sync_status_button.dart';
import '../audio/notebook_audio.dart';
import '../audio/recording_controller.dart';
import '../audio/ui/audio_bar_button.dart';
import '../audio/ui/audio_format.dart';
import '../backup/len_file_flows.dart';
import '../editor/shared/recording_elsewhere_notice.dart';
import '../editor/shared/shared_notebooks.dart';
import '../settings/settings_screen.dart';
import '../storage/storage_attention.dart';
import 'library_format.dart';
import 'library_notice_strip.dart';

export 'library_notice_strip.dart';

/// Puts a notice above the library's [child] while something needs the
/// user's attention: changes that can't be saved yet (a full browser
/// storage); files that won't be kept (a browser that refused storage,
/// UX_AUDIT P0-1); else, once, storage from another Len version that was
/// started afresh (`AppDatabase.schemaReset`); else, once, a browser that
/// may clear Len's data while sync is off (P2-30), once there is a notebook
/// to lose (R14-1); else, once, that notes
/// kept a day or more are only on this device while sync is off and no
/// backup was made (R7-12).
class LibraryNotices extends StatefulWidget {
  const LibraryNotices({super.key, required this.child, this.storage, this.notebooks});

  final Widget child;

  /// Notifies when notebooks may have been added or removed (the library's
  /// controller): the "may clear" notice waits for the first.
  final Listenable? notebooks;

  /// The browser's storage (default: `browserStorage`; null natively).
  final BrowserStorage? storage;

  /// The one-time tip id of the "may clear your data" notice.
  static const evictionTip = 'storage_not_persisted';

  /// The one-time tip id of the "only on this device" notice (a backup
  /// that grew stale adds `@` and its time).
  static const deviceOnlyTip = 'notes_device_only';

  /// How old a backup is before the notice comes back (once per backup).
  static const staleAfter = Duration(days: 30);

  @override
  State<LibraryNotices> createState() => _LibraryNoticesState();
}

class _LibraryNoticesState extends State<LibraryNotices> {
  late final AppServices _services = AppScope.read(context);
  late final BrowserStorage? _storage = widget.storage ?? browserStorage;
  // Len files: a backup (from Settings too) or a restore changes what the
  // device-only notice says.
  late final Listenable _changes = Listenable.merge([
    _services.sync,
    _services.writes,
    _services.lenFiles,
    _services.sharedNotebooks.unattended,
    _services.sharedNotebooks.stoppedInBackground,
    ?widget.notebooks,
  ]);

  /// Whether the browser may evict Len's data (null until known).
  bool? _evictable;

  /// The tip id that dismisses the "only on this device" notice now:
  /// once before the first backup, and once more per backup that grew
  /// stale (R8-8). Null while it has nothing to say: no notebook a day
  /// old or more (the empty library's "Set up sync…" covers the first
  /// day), or a backup under [staleAfter] old, or nothing changed since.
  String? _deviceOnlyTip() {
    final notebooks = _services.notebooks.list();
    final now = _services.clock.nowMs();
    final last = _services.settings.lastBackupAt;
    final String tip;
    if (last == null) {
      if (!notebooks.any((n) => now - n.createdAt > Duration.millisecondsPerDay)) return null;
      tip = LibraryNotices.deviceOnlyTip;
    } else {
      if (now - last < LibraryNotices.staleAfter.inMilliseconds) return null;
      if (!notebooks.any((n) => n.editedAt > last)) return null;
      tip = '${LibraryNotices.deviceOnlyTip}@$last';
    }
    return _services.settings.seenTips.contains(tip) ? null : tip;
  }

  late String? _deviceOnly = _deviceOnlyTip();

  /// The last backup [_deviceOnly] was worked out for.
  late int? _deviceOnlyFor = _services.settings.lastBackupAt;

  @override
  void initState() {
    super.initState();
    unawaited(_check());
  }

  void _dismissDeviceOnly() {
    if (_deviceOnly case final tip?) _services.settings.markTipSeen(tip);
    setState(() => _deviceOnly = null);
  }

  void _setUpSync() => unawaited(
    Navigator.of(context)
        .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen(showSync: true))),
  );

  Future<void> _backUp() async {
    if (await backupLibraryFlow(context) && mounted) _dismissDeviceOnly();
  }

  Future<void> _check() async {
    final storage = _storage;
    if (storage == null || _services.settings.seenTips.contains(LibraryNotices.evictionTip)) {
      return;
    }
    final persisted = await storage.isPersisted().catchError((Object _) => true);
    if (mounted) setState(() => _evictable = !persisted);
  }

  Future<void> _keepData() async {
    final granted = await _storage!.requestPersistence().catchError((Object _) => false);
    if (!mounted) return;
    if (granted) return _dismiss();
    // Browsers refuse silently (often until Len is installed or used more).
    showMessage(context, 'This browser didn’t allow it: install Len as an app, or set up sync');
  }

  void _dismiss() {
    _services.settings.markTipSeen(LibraryNotices.evictionTip);
    if (mounted) setState(() => _evictable = false);
  }

  Widget? _notice() {
    if (_services.sharedNotebooks.unattended.value case final shared?) {
      return _recordingNotice(shared);
    }
    if (_services.sharedNotebooks.stoppedInBackground.value case final stop?) {
      return LibraryNotice(
        key: const ValueKey('recording-stopped'),
        icon: Symbols.mic_off_rounded,
        title: NotebookAudio.stoppedInBackground,
        shortTitle: 'Recording stopped and saved',
        body: backgroundStopDetail(stop),
        actions: [
          if (stop.saved != null)
            TextButton(
              onPressed: () => showStoppedRecording(context, stop),
              child: const Text('Show'),
            ),
        ],
        onDismiss: () => _services.sharedNotebooks.stoppedInBackground.value = null,
      );
    }
    if (_services.writes.failure case final failure?) {
      return LibraryNotice(
        icon: Symbols.save_rounded,
        title: StorageAttention.unsavedTitle,
        body: StorageAttention.unsavedBody(failure),
        actions: [
          TextButton(
            onPressed: () => unawaited(_services.writes.flush()),
            child: const Text('Try again'),
          ),
        ],
      );
    }
    if (!_services.blobsArePersistent) {
      return const LibraryNotice(
        icon: Symbols.cloud_off_rounded,
        title: 'Files you add won’t be kept in this browser window',
        body:
            'This browser doesn’t let Len store files, so PDFs, images and recordings '
            'are lost when the tab closes (your handwriting is kept). Use a normal '
            'window, allow site data, or turn on sync.',
      );
    }
    if (_services.database.schemaReset case final reset?) return _resetNotice(reset);
    if (_services.sync.isConfigured) return null;
    // Nothing to lose yet: no warning on a first visit (R14-1).
    if (_evictable != true || _services.notebooks.list().isEmpty) return _deviceOnlyNotice();
    return LibraryNotice(
      icon: Symbols.storage_rounded,
      title: 'This browser may clear your notebooks',
      body:
          'Browsers can delete site data when space runs low. Let Len keep its data, '
          'or turn on sync for a copy on your server.',
      tone: NoticeTone.info,
      actions: [
        TextButton(onPressed: () => unawaited(_keepData()), child: const Text('Keep data')),
      ],
      onDismiss: _dismiss,
    );
  }

  LibraryNotice? _deviceOnlyNotice() {
    final last = _services.settings.lastBackupAt;
    if (last != _deviceOnlyFor) {
      _deviceOnlyFor = last;
      _deviceOnly = _deviceOnlyTip();
    }
    if (_deviceOnly == null) return null;
    return LibraryNotice(
      icon: Symbols.devices_rounded,
      title: 'Your notes are only on this device',
      // Phones and short windows: one line, the title and "Back up…" (the
      // explanation is in Settings → Backup; sync in the sidebar).
      shortTitle: deviceOnlyCaption,
      body: last == null
          ? 'Back up your library now and then, or set up sync'
          : 'Your last backup is from ${formatLibraryDate(last, now: _services.clock.nowDate())}. Back up your library now '
                'and then, or set up sync',
      tone: NoticeTone.info,
      actions: [
        TextButton(onPressed: () => unawaited(_backUp()), child: const Text('Back up…')),
        TextButton(onPressed: _setUpSync, child: const Text('Set up sync…')),
      ],
      onDismiss: _dismissDeviceOnly,
    );
  }

  /// A notebook left while recording (R17-1): it goes on until stopped.
  Widget _recordingNotice(SharedNotebook shared) {
    final audio = shared.audio;
    final recorder = audio.recorder;
    return ListenableBuilder(
      listenable: recorder,
      builder: (context, _) {
        final time = formatClock(recorder.elapsedMs);
        final paused = recorder.state == RecorderState.paused;
        final what = paused ? 'Recording paused' : 'Recording';
        return LibraryNotice(
          key: const ValueKey('recording-elsewhere'),
          icon: Symbols.mic_rounded,
          title: '$what in “${shared.notebook.title}” · $time',
          shortTitle: '$what · $time',
          body: 'It goes on until you stop it',
          actions: [
            TextButton(
              onPressed: () => showRecordingNotebook(context, shared),
              child: const Text('Show'),
            ),
            TextButton(
              onPressed: () => unawaited(stopRecording(context, audio)),
              child: const Text('Stop'),
            ),
          ],
        );
      },
    );
  }

  LibraryNotice _resetNotice(SchemaReset reset) {
    final version = reset.fromNewer ? 'a newer' : 'an older';
    final sync = reset.keptSync
        ? 'Notebooks you synced come back from your server.'
        : 'Notebooks you synced come back from your server when you turn on sync again.';
    final backup = reset.backupPath;
    final kept = backup == null
        ? 'The old data couldn’t be kept in this browser.'
        : 'The old data was kept in';
    return LibraryNotice(
      icon: Symbols.restart_alt_rounded,
      title: 'Len started fresh',
      body: 'Len’s storage was from $version version, so it started fresh. $sync $kept',
      detail: backup,
      tone: NoticeTone.info,
      onDismiss: () => setState(_services.database.acknowledgeSchemaReset),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: _changes,
    builder: (context, _) {
      final notice = _notice();
      if (notice == null) return widget.child;
      return Column(
        children: [
          SafeArea(bottom: false, child: notice),
          Expanded(
            child: MediaQuery.removePadding(context: context, removeTop: true, child: widget.child),
          ),
        ],
      );
    },
  );
}
