import 'dart:async';

import 'package:flutter/material.dart';

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
        final (icon, tooltip) = switch (sync.state) {
          SyncState.disabled => (Icons.cloud_off_outlined, 'Set up sync'),
          SyncState.idle => (Icons.cloud_done_outlined, 'Synced — tap to sync now'),
          SyncState.syncing => (Icons.cloud_sync_outlined, 'Syncing…'),
          SyncState.error => (Icons.cloud_off_rounded, 'Sync failed: ${sync.lastError}'),
        };
        final color = sync.state == SyncState.error ? Theme.of(context).colorScheme.error : null;
        return IconButton(
          tooltip: tooltip,
          icon: Icon(icon, color: color),
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
