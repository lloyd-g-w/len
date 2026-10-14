import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../app_services.dart';
import '../../data/schema_reset.dart';
import '../../platform/browser_storage.dart';
import '../../ui/app_theme.dart';
import '../../ui/messages.dart';
import '../../ui/sync_status_button.dart';
import '../backup/len_file_flows.dart';
import '../settings/settings_screen.dart';
import '../storage/storage_attention.dart';
import 'library_format.dart';

/// Puts a notice above the library's [child] while something needs the
/// user's attention: changes that can't be saved yet (a full browser
/// storage); files that won't be kept (a browser that refused storage,
/// UX_AUDIT P0-1); else, once, storage from another Len version that was
/// started afresh (`AppDatabase.schemaReset`); else, once, a browser that
/// may clear Len's data while sync is off (P2-30); else, once, that notes
/// kept a day or more are only on this device while sync is off and no
/// backup was made (R7-12).
class LibraryNotices extends StatefulWidget {
  const LibraryNotices({super.key, required this.child, this.storage});

  final Widget child;

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
    final now = DateTime.now().millisecondsSinceEpoch;
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
    if (_services.writes.failure case final failure?) {
      return LibraryNotice(
        icon: Symbols.save_sharp,
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
        icon: Symbols.cloud_off_sharp,
        title: 'Files you add won\'t be kept in this browser window',
        body:
            'This browser doesn\'t let Len store files, so PDFs, images and recordings '
            'are lost when the tab closes (your handwriting is kept). Use a normal '
            'window, allow site data, or turn on sync.',
      );
    }
    if (_services.database.schemaReset case final reset?) return _resetNotice(reset);
    if (_services.sync.isConfigured) return null;
    if (_evictable != true) return _deviceOnlyNotice();
    return LibraryNotice(
      icon: Symbols.storage_sharp,
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
      icon: Symbols.devices_sharp,
      title: 'Your notes are only on this device',
      // Phones and short windows: one line, the title and "Back up…" (the
      // explanation is in Settings → Backup; sync in the sidebar).
      shortTitle: deviceOnlyCaption,
      body: last == null
          ? 'Back up your library now and then, or set up sync'
          : 'Your last backup is from ${formatLibraryDate(last)}. Back up your library now '
                'and then, or set up sync',
      tone: NoticeTone.info,
      actions: [
        TextButton(onPressed: () => unawaited(_backUp()), child: const Text('Back up…')),
        TextButton(onPressed: _setUpSync, child: const Text('Set up sync…')),
      ],
      onDismiss: _dismissDeviceOnly,
    );
  }

  LibraryNotice _resetNotice(SchemaReset reset) {
    final version = reset.fromNewer ? 'a newer' : 'an older';
    final sync = reset.keptSync
        ? 'Notebooks you synced come back from your server.'
        : 'Notebooks you synced come back from your server when you turn on sync again.';
    final backup = reset.backupPath;
    final kept = backup == null
        ? 'The old data couldn\'t be kept in this browser.'
        : 'The old data was kept in';
    return LibraryNotice(
      icon: Symbols.restart_alt_sharp,
      title: 'Len started fresh',
      body: 'Len\'s storage was from $version version, so it started fresh. $sync $kept',
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

/// The colour of a [LibraryNotice]'s glyph.
enum NoticeTone {
  /// Something is being lost: a red glyph.
  warning,

  /// Worth knowing: an accent glyph.
  info,
}

/// A calm strip docked above the library (DESIGN §0: chrome is ruled
/// paper): flat on the Board with a hairline under it, a glyph in the
/// tone's colour on the margin column, a title and a sentence or two, with
/// optional [actions] and ✕. No tinted plate.
///
/// With a [shortTitle], phones and short windows get one line instead
/// (R8-7): the glyph, the short title, the first action and ✕, so the
/// notice doesn't push the notebooks off the screen.
class LibraryNotice extends StatelessWidget {
  const LibraryNotice({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.shortTitle,
    this.detail,
    this.actions = const [],
    this.onDismiss,
    this.tone = NoticeTone.warning,
  });

  final IconData icon;
  final String title;
  final String body;

  /// The one-line notice's title on phones and short windows (none: the
  /// whole notice everywhere).
  final String? shortTitle;

  /// Shown selectable under [body] (e.g. a file path to copy).
  final String? detail;

  /// Buttons at the end (e.g. "Keep data"); the one-line notice keeps
  /// the first.
  final List<Widget> actions;

  /// Shows ✕, which calls this.
  final VoidCallback? onDismiss;

  final NoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tint = tone == NoticeTone.warning ? scheme.error : scheme.primary;
    final compact = Breakpoints.libraryCompact(MediaQuery.sizeOf(context));
    // The screen's margin column (DESIGN §3).
    final margin = compact ? Gaps.lg : Gaps.xl;
    final oneLine = compact ? shortTitle : null;
    final dismiss = onDismiss == null
        ? null
        : IconButton(
            tooltip: 'Dismiss',
            // 48 on touch, 40 with a pointer.
            constraints: BoxConstraints.tightFor(
              width: Targets.barHit(context),
              height: Targets.barHit(context),
            ),
            icon: const Icon(Symbols.close_sharp, size: Glyphs.menu),
            onPressed: onDismiss,
          );
    final glyph = Icon(icon, size: Glyphs.bar, color: tint);
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          margin,
          oneLine != null ? 0 : Gaps.md,
          dismiss == null ? margin : Gaps.sm,
          oneLine != null ? 0 : (actions.isEmpty ? Gaps.md : Gaps.xs),
        ),
        constraints: BoxConstraints(minHeight: Targets.barHit(context)),
        decoration: BoxDecoration(
          color: Surfaces.chrome(scheme),
          border: Border(bottom: Surfaces.chromeEdge(scheme)),
        ),
        child: oneLine != null
            ? Row(
                children: [
                  glyph,
                  const SizedBox(width: Gaps.md),
                  Expanded(
                    child: Text(
                      oneLine,
                      style: theme.textTheme.labelLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (actions.isNotEmpty) actions.first,
                  ?dismiss,
                ],
              )
            : Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: Gaps.xxs),
                    child: glyph,
                  ),
                  const SizedBox(width: Gaps.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: theme.textTheme.labelLarge),
                        const SizedBox(height: Gaps.xxs),
                        Text(
                          body,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                        if (detail case final detail?) ...[
                          const SizedBox(height: Gaps.xxs),
                          SelectableText(detail, style: theme.textTheme.bodySmall),
                        ],
                        if (actions.isNotEmpty)
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: Wrap(spacing: Gaps.xs, children: actions),
                          ),
                      ],
                    ),
                  ),
                  ?dismiss,
                ],
              ),
      ),
    );
  }
}
