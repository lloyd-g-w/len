import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../app_services.dart';
import '../../core/format.dart';
import '../../sync/sync_controller.dart';
import '../backup/len_file_flows.dart';
import '../backup/len_import_flow.dart';
import 'settings_section.dart';

/// Backup: "Back up library…" (one Len file of everything, with when it was
/// last done; nothing to do in an empty library) and "Restore from
/// backup…" (`importLenFlow`: asks first, nothing here is replaced).
/// Says plainly where notes are kept: only here while sync is off
/// (UX_AUDIT R7-12), and what Android's own backup holds (R7-13).
class BackupSettings extends StatefulWidget {
  const BackupSettings({super.key});

  /// What the section says about where notes are kept.
  static String describe({required bool syncing, required bool android}) => [
    syncing
        ? 'Sync keeps a copy of your notes on your server. A backup is a copy you keep yourself.'
        // Sync's line just above says the notes are only on this device (R8-9).
        : 'Back up your library now and then, or set up sync to keep a copy on your server.',
    if (android)
      'Handwriting and text are included in your Android backup; PDFs, images and audio '
          'are not.',
  ].join(' ');

  /// When the library was last backed up ([at], ms since epoch; null:
  /// never): "Last backup today at 14:05", "Last backup 3 Oct".
  static String lastBackup(int? at, {DateTime? now}) {
    if (at == null) {
      return 'One Len file with every notebook, folder and template. Not backed up yet';
    }
    final label = formatEdited(at, now: now);
    if (label == 'Just now') return 'Backed up just now';
    return label.contains(':') ? 'Last backup today at $label' : 'Last backup $label';
  }

  @override
  State<BackupSettings> createState() => _BackupSettingsState();
}

class _BackupSettingsState extends State<BackupSettings> {
  late final AppServices _services = AppScope.read(context);

  Future<void> _backUp() async {
    await backupLibraryFlow(context);
    if (mounted) setState(() {}); // The last backup changed.
  }

  @override
  Widget build(BuildContext context) {
    // Len files: a restore fills an empty library.
    return ListenableBuilder(
      listenable: Listenable.merge([_services.sync, _services.lenFiles]),
      builder: (context, _) => _section(context),
    );
  }

  Widget _section(BuildContext context) {
    final last = _services.settings.lastBackupAt;
    final empty = _services.notebooks.list().isEmpty && _services.folders.list().isEmpty;
    return SettingsSection(
      title: 'Backup',
      description: BackupSettings.describe(
        syncing: _services.sync.state != SyncState.disabled,
        android: !kIsWeb && defaultTargetPlatform == TargetPlatform.android,
      ),
      children: [
        SettingsTile(
          icon: Symbols.backup_sharp,
          title: 'Back up library…',
          subtitle: empty ? 'Nothing to back up yet' : BackupSettings.lastBackup(last),
          onTap: empty ? null : () => unawaited(_backUp()),
        ),
        SettingsTile(
          icon: Symbols.settings_backup_restore_sharp,
          title: 'Restore from backup…',
          subtitle: 'Brings back a Len backup; nothing here is replaced',
          onTap: () => unawaited(importLenFlow(context)),
        ),
      ],
    );
  }
}
