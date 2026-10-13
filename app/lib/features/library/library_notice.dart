import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../app_services.dart';
import '../../data/schema_reset.dart';
import '../../platform/browser_storage.dart';
import '../../ui/app_theme.dart';
import '../storage/storage_attention.dart';

/// Puts a notice above the library's [child] while something needs the
/// user's attention: changes that can't be saved yet (a full browser
/// storage); files that won't be kept (a browser that refused storage,
/// UX_AUDIT P0-1); else, once, storage from another Len version that was
/// started afresh (`AppDatabase.schemaReset`); else, once, a browser that
/// may clear Len's data while sync is off (P2-30).
class LibraryNotices extends StatefulWidget {
  const LibraryNotices({super.key, required this.child, this.storage});

  final Widget child;

  /// The browser's storage (default: `browserStorage`; null natively).
  final BrowserStorage? storage;

  /// The one-time tip id of the "may clear your data" notice.
  static const evictionTip = 'storage_not_persisted';

  @override
  State<LibraryNotices> createState() => _LibraryNoticesState();
}

class _LibraryNoticesState extends State<LibraryNotices> {
  late final AppServices _services = AppScope.read(context);
  late final BrowserStorage? _storage = widget.storage ?? browserStorage;
  late final Listenable _changes = Listenable.merge([_services.sync, _services.writes]);

  /// Whether the browser may evict Len's data (null until known).
  bool? _evictable;

  @override
  void initState() {
    super.initState();
    unawaited(_check());
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
    if (granted) _dismiss();
  }

  void _dismiss() {
    _services.settings.markTipSeen(LibraryNotices.evictionTip);
    setState(() => _evictable = false);
  }

  Widget? _notice() {
    if (_services.writes.failure case final failure?) {
      return LibraryNotice(
        icon: Symbols.save_sharp,
        title: StorageAttention.unsavedTitle,
        body: StorageAttention.unsavedBody(failure),
        action: TextButton(
          onPressed: () => unawaited(_services.writes.flush()),
          child: const Text('Try again'),
        ),
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
    if (_evictable != true || _services.sync.isConfigured) return null;
    return LibraryNotice(
      icon: Symbols.storage_sharp,
      title: 'This browser may clear your notebooks',
      body:
          'Browsers can delete site data when space runs low. Let Len keep its data, '
          'or turn on sync for a copy on your server.',
      tone: NoticeTone.info,
      action: TextButton(onPressed: () => unawaited(_keepData()), child: const Text('Keep data')),
      onDismiss: _dismiss,
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
/// an optional [action] and ✕. No tinted plate.
class LibraryNotice extends StatelessWidget {
  const LibraryNotice({
    super.key,
    required this.icon,
    required this.title,
    required this.body,
    this.detail,
    this.action,
    this.onDismiss,
    this.tone = NoticeTone.warning,
  });

  final IconData icon;
  final String title;
  final String body;

  /// Shown selectable under [body] (e.g. a file path to copy).
  final String? detail;

  /// A button at the end (e.g. "Keep data").
  final Widget? action;

  /// Shows ✕, which calls this.
  final VoidCallback? onDismiss;

  final NoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tint = tone == NoticeTone.warning ? scheme.error : scheme.primary;
    // The screen's margin column (DESIGN §3).
    final margin = Breakpoints.libraryCompact(MediaQuery.sizeOf(context)) ? Gaps.lg : Gaps.xl;
    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        padding: EdgeInsets.fromLTRB(
          margin,
          Gaps.md,
          onDismiss == null ? margin : Gaps.sm,
          action == null ? Gaps.md : Gaps.xs,
        ),
        decoration: BoxDecoration(
          color: Surfaces.chrome(scheme),
          border: Border(bottom: Surfaces.chromeEdge(scheme)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: Gaps.xxs),
              child: Icon(icon, size: Glyphs.bar, color: tint),
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
                    style: theme.textTheme.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
                  ),
                  if (detail case final detail?) ...[
                    const SizedBox(height: Gaps.xxs),
                    SelectableText(detail, style: theme.textTheme.bodySmall),
                  ],
                  if (action case final action?)
                    Align(alignment: AlignmentDirectional.centerEnd, child: action),
                ],
              ),
            ),
            if (onDismiss case final dismiss?)
              IconButton(
                tooltip: 'Dismiss',
                visualDensity: VisualDensity.compact,
                icon: const Icon(Symbols.close_sharp, size: Glyphs.menu),
                onPressed: dismiss,
              ),
          ],
        ),
      ),
    );
  }
}
