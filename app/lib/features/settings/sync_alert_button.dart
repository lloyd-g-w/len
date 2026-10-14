import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../sync/sync_controller.dart';
import '../../sync/sync_errors.dart';
import '../library/library_format.dart';
import 'settings_screen.dart';

/// "Not synced since Monday", "…since just now" (or "Not synced yet"),
/// from [sync]'s last success.
String notSyncedSince(SyncController sync) => switch (sync.lastSuccess) {
  final last? => libraryDateAfter(
    'Not synced since',
    last.millisecondsSinceEpoch,
    now: sync.clock.nowDate(),
  ),
  null => 'Not synced yet',
};

/// What the sync mark says, and whether it is something to fix (red) or
/// only to know (UX_AUDIT R8-12): files left to upload, or being offline,
/// fix themselves; a refused token or another server need Settings.
({String tooltip, bool fix, bool offline}) syncAlert(SyncController sync) {
  final files = sync.filesNotUploaded;
  if (files > 0) {
    return (
      tooltip: '${files == 1 ? '1 file' : '$files files'} not uploaded yet',
      fix: false,
      offline: false,
    );
  }
  if (sync.lastFailure == SyncFailure.network) {
    final since = notSyncedSince(sync);
    return (
      tooltip: 'Offline: ${since[0].toLowerCase()}${since.substring(1)}',
      fix: false,
      offline: true,
    );
  }
  return (tooltip: '${notSyncedSince(sync)}: open Sync settings', fix: true, offline: false);
}

/// A quiet mark that sync has been failing a while (UX_AUDIT R7-14): the
/// cloud-alert glyph in the error colour where something needs fixing, a
/// Graphite one while offline or only files wait ([syncAlert]); nothing
/// otherwise. A tap opens Settings → Sync, which says what went wrong. Where the sidebar's sync
/// status isn't on screen: the phone library's header, the editor's bar.
class SyncAlertButton extends StatelessWidget {
  const SyncAlertButton({super.key, required this.sync, this.button});

  final SyncController sync;

  /// Builds the button (the editor's bar buttons); default an
  /// [IconButton].
  final Widget Function(String tooltip, IconData icon, Color color, VoidCallback onPressed)? button;

  /// How long sync fails before the mark shows (a moment offline is fine).
  static const Duration after = Duration(minutes: 15);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: sync,
    builder: (context, _) {
      if (!sync.failingFor(after)) return const SizedBox.shrink();
      final alert = syncAlert(sync);
      final tooltip = alert.tooltip;
      final scheme = Theme.of(context).colorScheme;
      final color = alert.fix ? scheme.error : scheme.onSurfaceVariant;
      final icon = alert.offline ? Symbols.cloud_off_sharp : Symbols.cloud_alert_sharp;
      void open() => unawaited(
        Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen(showSync: true))),
      );
      return KeyedSubtree(
        key: const ValueKey('sync-alert'),
        child:
            button?.call(tooltip, icon, color, open) ??
            IconButton(tooltip: tooltip, color: color, icon: Icon(icon), onPressed: open),
      );
    },
  );
}
