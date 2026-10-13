import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../sync/sync_controller.dart';
import '../library/library_format.dart';
import 'settings_screen.dart';

/// "Not synced since Monday" (or "Not synced yet"), from [sync]'s last
/// success.
String notSyncedSince(SyncController sync) => switch (sync.lastSuccess) {
  final last? => 'Not synced since ${formatLibraryDate(last.millisecondsSinceEpoch)}',
  null => 'Not synced yet',
};

/// A quiet mark that sync has been failing a while (UX_AUDIT R7-14): the
/// cloud-alert glyph in the error colour, nothing otherwise; a tap opens
/// Settings → Sync, which says what went wrong. Where the sidebar's sync
/// status isn't on screen: the phone library's header, the editor's bar.
class SyncAlertButton extends StatelessWidget {
  const SyncAlertButton({super.key, required this.sync, this.button});

  final SyncController sync;

  /// Builds the button (the editor's bar buttons); default an
  /// [IconButton].
  final Widget Function(String tooltip, Color color, VoidCallback onPressed)? button;

  /// How long sync fails before the mark shows (a moment offline is fine).
  static const Duration after = Duration(minutes: 15);

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: sync,
    builder: (context, _) {
      if (!sync.failingFor(after)) return const SizedBox.shrink();
      final tooltip = '${notSyncedSince(sync)}: open Sync settings';
      final color = Theme.of(context).colorScheme.error;
      void open() => unawaited(
        Navigator.of(context)
            .push(MaterialPageRoute<void>(builder: (_) => const SettingsScreen(showSync: true))),
      );
      return KeyedSubtree(
        key: const ValueKey('sync-alert'),
        child:
            button?.call(tooltip, color, open) ??
            IconButton(
              tooltip: tooltip,
              color: color,
              icon: const Icon(Symbols.cloud_alert_sharp),
              onPressed: open,
            ),
      );
    },
  );
}
