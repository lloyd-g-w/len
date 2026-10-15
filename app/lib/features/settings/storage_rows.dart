import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../app_services.dart';
import '../../core/format.dart';
import '../../data/storage_queries.dart';
import '../../ui/app_dialogs.dart';
import '../../ui/app_theme.dart';
import '../../ui/messages.dart';
import '../editor/tabs/editor_workspace.dart';
import '../storage/storage_overview.dart';
import 'settings_section.dart';

/// "Space used": everything Len keeps here, then by kind (the database's
/// handwriting and text, PDFs, images, recordings, cached previews).
class SpaceUsedTile extends StatelessWidget {
  const SpaceUsedTile({super.key, required this.overview, required this.where});

  final StorageOverview overview;

  /// "on this device" / "in this browser".
  final String where;

  @override
  Widget build(BuildContext context) {
    final survey = overview.survey;
    final previews = overview.previews ?? 0;
    return SettingsTile(
      icon: Symbols.pie_chart_sharp,
      title: 'Space used',
      subtitle: survey == null ? 'Measuring…' : '${formatBytes(survey.total + previews)} $where',
      below: survey == null
          ? null
          : _Breakdown([
              ('Handwriting and text', survey.database),
              ('PDFs', survey.files[FileKind.pdf]!),
              ('Images', survey.files[FileKind.image]!),
              ('Recordings', survey.files[FileKind.audio]!),
              ('Other files', survey.files[FileKind.other]!),
              ('Cached previews', previews),
            ]),
    );
  }
}

/// Sizes by kind, those taking anything, in two columns.
class _Breakdown extends StatelessWidget {
  const _Breakdown(this.kinds);

  final List<(String, int)> kinds;

  /// Keeps the sizes near their names on wide rows.
  static const double _maxWidth = 320;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: _maxWidth),
        child: Column(
          children: [
            for (final (label, bytes) in kinds)
              if (bytes > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: Gaps.xxs),
                  child: Row(
                    children: [
                      Expanded(child: Text(label, style: style)),
                      const SizedBox(width: Gaps.lg),
                      Text(
                        formatBytes(bytes),
                        style: style?.copyWith(fontFeatures: AppTheme.tabularFigures),
                      ),
                    ],
                  ),
                ),
          ],
        ),
      ),
    );
  }
}

/// One of the notebooks taking the most: its size (and its recordings'),
/// opening it on tap; Recordings opens it at its recordings.
class NotebookSizeTile extends StatelessWidget {
  const NotebookSizeTile({super.key, required this.footprint, required this.onOpen});

  final NotebookFootprint footprint;

  /// Opens the notebook, with `recordings` at its recordings list.
  final void Function({required bool recordings}) onOpen;

  @override
  Widget build(BuildContext context) {
    final n = footprint;
    final size = formatBytes(n.bytes);
    final subtitle = n.trashed
        ? '$size, in the trash'
        : n.recordingBytes == 0
        ? size
        : formatBytes(n.recordingBytes) == size
        ? '$size, all recordings'
        : '$size, ${formatBytes(n.recordingBytes)} of it recordings';
    return SettingsTile(
      icon: Symbols.menu_book_sharp,
      title: n.title,
      subtitle: subtitle,
      trailing: n.recordings > 0 && !n.trashed
          ? TextButton(onPressed: () => onOpen(recordings: true), child: const Text('Recordings'))
          : null,
      onTap: n.trashed ? null : () => onOpen(recordings: false),
    );
  }
}

/// "Free up N MB…": copies of files the sync server holds (shown while
/// sync is on and some could go).
class FreeUpTile extends StatelessWidget {
  const FreeUpTile({super.key, required this.overview});

  final StorageOverview overview;

  @override
  Widget build(BuildContext context) {
    final bytes = overview.survey?.freeable ?? 0;
    return SettingsTile(
      icon: Symbols.cloud_done_sharp,
      title: 'Downloaded files',
      subtitle:
          '${formatBytes(bytes)} of PDFs, images and recordings are also on the sync server. '
          'Removed here, they download again when you open them.',
      control: OutlinedButton(
        onPressed: overview.freeing ? null : () => unawaited(freeUpDownloads(context, overview)),
        child: Text(overview.freeing ? 'Freeing up…' : 'Free up ${formatBytes(bytes)}…'),
      ),
    );
  }
}

/// Asks once, then removes this device's copies of files the sync server
/// holds, and says how it went.
Future<void> freeUpDownloads(BuildContext context, StorageOverview overview) async {
  final bytes = overview.survey?.freeable ?? 0;
  final count = overview.survey?.freeableIds.length ?? 0;
  final confirmed = await confirmAction(
    context,
    title: 'Free up ${formatBytes(bytes)}?',
    message:
        'Removes this device’s copies of ${count == 1 ? '1 file' : '$count files'} the sync '
        'server keeps: PDFs, images and recordings of notebooks that aren’t open. They '
        'download again when you open them, which needs a connection. This can’t be undone.',
    confirmLabel: 'Free up',
  );
  if (!confirmed || !context.mounted) return;
  final outcome = await overview.freeUp();
  if (!context.mounted) return;
  showMessage(context, freeUpMessage(outcome));
}

/// What to tell after "Free up": what went, or why nothing did.
String freeUpMessage(FreeUpOutcome outcome) => switch (outcome) {
  FreedUp(:final bytes) => 'Freed up ${formatBytes(bytes)}',
  NothingFreed(reason: NotFreed.notOnServer) =>
    'The sync server doesn’t have these files yet, so nothing was removed',
  NothingFreed(reason: NotFreed.inUse) =>
    'These files are in use (open notebooks, changes not synced yet), so nothing was removed',
  NothingFreed(reason: NotFreed.serverChanged) =>
    'The sync server changed meanwhile, so nothing was removed',
  ServerUnreachable() => 'Couldn’t reach the sync server, so nothing was removed',
};

/// "Cached previews": rasters of zoomed-out pages kept to show them
/// quickly (shown when they take enough to matter).
class CachedPreviewsTile extends StatelessWidget {
  const CachedPreviewsTile({super.key, required this.overview});

  final StorageOverview overview;

  @override
  Widget build(BuildContext context) => SettingsTile(
    icon: Symbols.photo_library_sharp,
    title: 'Cached previews',
    subtitle:
        '${formatBytes(overview.previews ?? 0)} of pages drawn zoomed out, kept so they show '
        'quickly. Cleared, they are drawn again.',
    trailing: TextButton(
      onPressed: () async {
        await overview.clearPreviews();
        if (context.mounted) showMessage(context, 'Cleared cached previews');
      },
      child: const Text('Clear'),
    ),
  );
}

/// Opens notebook [id] from Settings, with [recordings] at its recordings:
/// in the editor below if one is shown (Settings opened from it), else in
/// a new one over Settings.
Future<void> openFromStorage(BuildContext context, String id, {required bool recordings}) async {
  final services = AppScope.read(context);
  final notebook = services.notebooks.get(id);
  if (notebook == null || notebook.isTrashed) return;
  if (recordings) services.openNotebooks.requestRecordings(id);
  if (services.workspace.shown) {
    Navigator.of(context).popUntil(ModalRoute.withName(EditorWorkspace.routeName));
    services.openNotebooks.open(notebook);
    return;
  }
  await openNotebook(context, notebook);
}
