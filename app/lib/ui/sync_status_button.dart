import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../sync/sync_controller.dart';
import 'announce.dart';
import 'app_theme.dart';

/// The one phrase for notes that aren't synced (R8-9): the sidebar's
/// caption, the library's one-line notice; sentences say "only on this
/// device".
const deviceOnlyCaption = 'Only on this device';

/// The short sync status the sidebar shows (REDESIGN §3): "Synced 2m",
/// "Synced just now", "Syncing…" ("Syncing… 40%" through a long pull,
/// [progress], R16-5), "Sync failed", and without sync [deviceOnlyCaption]
/// (where the notes are, UX_AUDIT R7-12; the tooltip says it in full).
String syncCaption(SyncState state, DateTime? lastSuccess, DateTime now, {double? progress}) {
  switch (state) {
    case SyncState.disabled:
      return deviceOnlyCaption;
    case SyncState.syncing:
      return syncingCaption(progress);
    case SyncState.error:
      return 'Sync failed';
    case SyncState.idle:
      if (lastSuccess == null) return 'Not synced yet';
      final ago = now.difference(lastSuccess);
      if (ago.inMinutes < 1) return 'Synced just now';
      if (ago.inHours < 1) return 'Synced ${ago.inMinutes}m';
      if (ago.inDays < 1) return 'Synced ${ago.inHours}h';
      return 'Synced ${ago.inDays}d';
  }
}

/// "Syncing…", with how far a long pull is when [progress] is known.
String syncingCaption(double? progress) =>
    progress == null ? 'Syncing…' : 'Syncing… ${(progress * 100).floor()}%';

/// Toolbar button showing sync status; tapping syncs now, or calls
/// [onOpenSettings] when sync is not set up yet or failed (Settings → Sync
/// says what went wrong and what to do). With [caption], the status
/// is also written beside the icon ([syncCaption]), kept current.
class SyncStatusButton extends StatefulWidget {
  const SyncStatusButton({
    super.key,
    required this.sync,
    required this.onOpenSettings,
    this.caption = false,
  });

  final SyncController sync;
  final VoidCallback onOpenSettings;
  final bool caption;

  @override
  State<SyncStatusButton> createState() => _SyncStatusButtonState();
}

class _SyncStatusButtonState extends State<SyncStatusButton> {
  /// Refreshes "Synced 2m" as time passes (only with a caption).
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    if (widget.caption) {
      _tick = Timer.periodic(const Duration(seconds: 30), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  SyncController get sync => widget.sync;
  VoidCallback get onOpenSettings => widget.onOpenSettings;

  /// Syncs, then tells screen readers how it went (the icon only turns).
  Future<void> _syncNow(BuildContext context) async {
    announce(context, 'Syncing');
    await sync.syncNow();
    if (!context.mounted) return;
    announce(context, switch (sync.state) {
      SyncState.error => 'Sync failed: ${sync.lastError}',
      SyncState.syncing => 'Syncing',
      _ => 'Synced',
    });
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        final tooLarge = sync.state == SyncState.disabled ? null : sync.tooLargeSummary;
        final (icon, status) = switch (sync.state) {
          SyncState.disabled => (
            Symbols.cloud_off_rounded,
            'Your notes are only on this device: set up sync',
          ),
          SyncState.idle => (Symbols.cloud_done_rounded, 'Synced: tap to sync now'),
          SyncState.syncing => (Symbols.cloud_sync_rounded, syncingCaption(sync.progress)),
          SyncState.error => (Symbols.cloud_off_rounded, '${sync.lastError}\nTap for details'),
        };
        final scheme = Theme.of(context).colorScheme;
        final color = sync.state == SyncState.error ? scheme.error : null;
        // A small badge: some files stay on this device (see Settings → Sync).
        final glyph = Badge(
          isLabelVisible: tooLarge != null,
          smallSize: 8,
          backgroundColor: scheme.primary,
          child: Icon(icon, color: color, size: widget.caption ? 18 : null),
        );
        final onPressed = switch (sync.state) {
          SyncState.disabled || SyncState.error => onOpenSettings,
          SyncState.syncing => null,
          SyncState.idle => () => unawaited(_syncNow(context)),
        };
        final tooltip = tooLarge == null ? status : '$status\n$tooLarge';
        if (!widget.caption) {
          return IconButton(tooltip: tooltip, icon: glyph, onPressed: onPressed);
        }
        final theme = Theme.of(context);
        // Merged, so the tooltip describes the button to screen readers (on
        // its own it named the whole screen).
        return MergeSemantics(
          child: Tooltip(
            message: tooltip,
            child: TextButton.icon(
              key: const ValueKey('sync-status'),
              onPressed: onPressed,
              style: TextButton.styleFrom(
                foregroundColor: color ?? scheme.onSurfaceVariant,
                disabledForegroundColor: scheme.onSurfaceVariant,
                textStyle: theme.textTheme.bodySmall,
                padding: const EdgeInsetsDirectional.only(start: Gaps.sm, end: Gaps.md),
                minimumSize: Size.square(Targets.menuRowHeight(context)),
              ),
              icon: glyph,
              label: Text(
                syncCaption(
                  sync.state,
                  sync.lastSuccess,
                  sync.clock.nowDate(),
                  progress: sync.progress,
                ),
                style: const TextStyle(fontFeatures: AppTheme.tabularFigures),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        );
      },
    );
  }
}
