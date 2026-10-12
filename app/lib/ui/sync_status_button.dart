import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../sync/sync_controller.dart';

/// Toolbar button showing sync status; tapping syncs now (or calls
/// [onConfigure] when sync is not set up yet).
class SyncStatusButton extends StatelessWidget {
  const SyncStatusButton({super.key, required this.sync, required this.onConfigure});

  final SyncController sync;
  final VoidCallback onConfigure;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        final tooLarge = sync.state == SyncState.disabled ? null : sync.tooLargeSummary;
        final (icon, status) = switch (sync.state) {
          SyncState.disabled => (Symbols.cloud_off_rounded, 'Set up sync'),
          SyncState.idle => (Symbols.cloud_done_rounded, 'Synced — tap to sync now'),
          SyncState.syncing => (Symbols.cloud_sync_rounded, 'Syncing…'),
          SyncState.error => (Symbols.cloud_off_rounded, 'Sync failed: ${sync.lastError}'),
        };
        final scheme = Theme.of(context).colorScheme;
        final color = sync.state == SyncState.error ? scheme.error : null;
        return IconButton(
          tooltip: tooLarge == null ? status : '$status\n$tooLarge',
          // A small badge: some files stay on this device (see Settings → Sync).
          icon: Badge(
            isLabelVisible: tooLarge != null,
            smallSize: 8,
            backgroundColor: scheme.tertiary,
            child: Icon(icon, color: color),
          ),
          onPressed: switch (sync.state) {
            SyncState.disabled => onConfigure,
            SyncState.syncing => null,
            _ => () => unawaited(sync.syncNow()),
          },
        );
      },
    );
  }
}
