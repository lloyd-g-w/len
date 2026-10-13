import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../core/format.dart';
import '../../sync/sync_controller.dart';
import '../../ui/app_theme.dart';
import '../../ui/error_details.dart';

/// The sync status as a chip (with the last error and its Details), and
/// any files too large to sync.
class SyncStatusLine extends StatelessWidget {
  const SyncStatusLine({super.key, required this.sync});

  final SyncController sync;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        final last = sync.lastSuccess;
        final (icon, color, text) = switch (sync.state) {
          SyncState.disabled => (Symbols.cloud_off_sharp, scheme.onSurfaceVariant, 'Sync is off'),
          SyncState.syncing => (Symbols.cloud_sync_sharp, scheme.primary, 'Syncing…'),
          SyncState.error => (
            Symbols.error_sharp,
            scheme.error,
            sync.waitsForSettings
                ? '${sync.lastError}. Sync is paused'
                : sync.lastError ?? 'Sync failed',
          ),
          SyncState.idle => (
            Symbols.cloud_done_sharp,
            scheme.primary,
            last == null ? 'Ready' : 'Last synced ${formatEdited(last.millisecondsSinceEpoch)}',
          ),
        };
        // A plain status line, its icon in the fields' icon column (not a
        // filled chip, which read as one more field).
        final status = Semantics(
          liveRegion: true,
          child: Row(
            children: [
              SizedBox(
                width: Targets.touch,
                child: Icon(icon, size: Glyphs.bar, color: color),
              ),
              Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
              if (sync.state == SyncState.error && sync.lastErrorDetails != null)
                ErrorDetailsButton(title: 'Sync error', details: sync.lastErrorDetails!),
            ],
          ),
        );
        if (sync.state == SyncState.disabled || sync.tooLargeFiles.isEmpty) return status;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            status,
            const SizedBox(height: Gaps.sm),
            _TooLargeNotice(sync: sync),
          ],
        );
      },
    );
  }
}

/// Explains files the server refuses as too large, with a retry.
class _TooLargeNotice extends StatelessWidget {
  const _TooLargeNotice({required this.sync});

  final SyncController sync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final files = sync.tooLargeFiles;
    final largest = files.map((f) => f.size).reduce((a, b) => a > b ? a : b);
    final limit = sync.serverMaxBlobBytes;
    return Container(
      padding: const EdgeInsets.fromLTRB(Gaps.md, Gaps.sm + 2, Gaps.sm, Gaps.sm),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Symbols.cloud_upload_sharp, size: Glyphs.menu, color: scheme.primary),
          ),
          const SizedBox(width: Gaps.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(sync.tooLargeSummary ?? '', style: theme.textTheme.bodyMedium),
                const SizedBox(height: 2),
                Text(
                  '${files.length == 1 ? 'It is' : 'The largest is'} ${formatBytes(largest)}; '
                  'the server accepts ${limit == null ? 'less' : 'up to ${formatBytes(limit)}'}. '
                  'It stays on this device and other devices show it as missing. '
                  'Raise LEN_BLOB_MAX_BYTES on the server (and the upload limit of any proxy), '
                  'then retry.',
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => unawaited(sync.retryTooLargeFiles()),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
