import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../app_services.dart';
import '../../data/versions/versions.dart';
import '../../sync/remote_changes.dart';
import '../../ui/app_theme.dart';
import '../../ui/dialog_or_sheet.dart';
import '../../ui/menus.dart';
import '../../ui/section_label.dart';
import '../../ui/sheet_parts.dart';
import 'version_flows.dart';
import 'version_labels.dart';
import 'version_preview.dart';
import 'version_surface_view.dart';

/// "Version history…" (docs/ARCHITECTURE.md, "Version history"): the
/// versions of notebook [notebookId], newest first, grouped by day. A
/// version opens its preview; its ⋯ restores, copies, renames or deletes.
/// Snack bars show on [context]'s screen.
Future<void> showVersionHistory(BuildContext context, AppServices services, String notebookId) =>
    showDialogOrSheet<void>(
      context: context,
      maxHeight: 720,
      sheetHeightFactor: 0.85,
      builder: (sheet, wide) =>
          VersionHistory(services: services, notebookId: notebookId, wide: wide, message: context),
    );

/// The content of [showVersionHistory].
class VersionHistory extends StatefulWidget {
  const VersionHistory({
    super.key,
    required this.services,
    required this.notebookId,
    required this.message,
    this.wide = true,
  });

  final AppServices services;
  final String notebookId;

  /// Where snack bars show (the screen the history was opened from).
  final BuildContext message;

  /// In a dialog (else a sheet with its drag handle above).
  final bool wide;

  @override
  State<VersionHistory> createState() => _VersionHistoryState();
}

class _VersionHistoryState extends State<VersionHistory> {
  late final VersionSheets _sheets = VersionSheets(widget.services.versions);
  late final StreamSubscription<RemoteChanges> _remote;

  @override
  void initState() {
    super.initState();
    _remote = widget.services.sync.remoteChanges.listen((changes) {
      if (changes.versionsOfNotebooks.contains(widget.notebookId) && mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    unawaited(_remote.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final services = widget.services;
    return ListenableBuilder(
      listenable: services.versions,
      builder: (context, _) {
        final versions = services.versions.of(widget.notebookId);
        final title = services.notebooks.get(widget.notebookId)?.title;
        final now = services.clock.nowDate();
        final rows = <Widget>[];
        String? day;
        for (final (i, v) in versions.indexed) {
          final label = VersionLabels.day(v.createdAt, now: now);
          if (label != day) {
            day = label;
            rows.add(
              Padding(
                padding: const EdgeInsets.fromLTRB(Gaps.lg, Gaps.md, Gaps.lg, Gaps.xs),
                child: SectionLabel(label),
              ),
            );
          }
          rows.add(
            _VersionRow(
              key: ValueKey('version-${v.id}'),
              version: v,
              first: i == versions.length - 1,
              hasOlder: i < versions.length - 1,
              sheets: _sheets,
              services: services,
              onOpen: () => _open(v),
              onAction: (a) => _act(a, v),
            ),
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(Gaps.lg, widget.wide ? Gaps.lg : 0, Gaps.lg, Gaps.sm),
              child: SheetHeader(
                title: 'Version history',
                subtitle: title,
                onClose: () => Navigator.of(context).pop(),
                trailing: TextButton(
                  onPressed: () =>
                      unawaited(saveVersionFlow(widget.message, services, widget.notebookId)),
                  child: const Text('Save version…'),
                ),
              ),
            ),
            Flexible(
              child: versions.isEmpty
                  ? _empty(context)
                  : ListView(
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(bottom: Gaps.lg),
                      children: rows,
                    ),
            ),
          ],
        );
      },
    );
  }

  Widget _empty(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(Gaps.xl),
      child: Text(
        'No versions yet. Len keeps one when you pause writing, and you can save one '
        'yourself at any time',
        textAlign: TextAlign.center,
        style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
      ),
    );
  }

  Future<void> _open(NotebookVersion version) => Navigator.of(context).push(
    MaterialPageRoute<void>(
      builder: (_) => VersionPreview(
        services: widget.services,
        version: version,
        sheets: _sheets,
        message: widget.message,
        onRestored: _close,
      ),
    ),
  );

  /// After a restore: back to the notebook, to see it.
  void _close() {
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _act(_VersionAction action, NotebookVersion v) async {
    final services = widget.services;
    switch (action) {
      case _VersionAction.restore:
        if (await restoreVersionFlow(context, services, v, message: widget.message)) _close();
      case _VersionAction.copy:
        await copyVersionFlow(widget.message, services, v);
      case _VersionAction.rename:
        await renameVersionFlow(context, services, v);
      case _VersionAction.delete:
        services.versions.delete([v.id]);
      case _VersionAction.deleteOlder:
        await deleteOlderFlow(context, services, v);
    }
  }
}

enum _VersionAction { restore, copy, rename, delete, deleteOlder }

/// One version: a thumbnail of the page it changed first, its name or
/// what made it, the time, the device and what changed.
class _VersionRow extends StatelessWidget {
  const _VersionRow({
    super.key,
    required this.version,
    required this.first,
    required this.hasOlder,
    required this.sheets,
    required this.services,
    required this.onOpen,
    required this.onAction,
  });

  final NotebookVersion version;

  /// The oldest version: its summary counts what it holds.
  final bool first;
  final bool hasOlder;
  final VersionSheets sheets;
  final AppServices services;
  final VoidCallback onOpen;
  final ValueChanged<_VersionAction> onAction;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = version;
    final device = VersionLabels.device(v, thisDevice: services.strokes.deviceId);
    final title = VersionLabels.title(v);
    final summary = VersionLabels.summary(v, first: first);
    return Semantics(
      button: true,
      label: '$title, ${VersionLabels.time(v)}, $device. $summary',
      excludeSemantics: true,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: Gaps.lg, vertical: Gaps.sm),
          child: Row(
            children: [
              SizedBox(
                width: 48,
                child: !v.isCanvas && v.summary.pages == 0
                    ? const SizedBox.shrink()
                    : ClipRRect(
                        borderRadius: BorderRadius.circular(Radii.xs),
                        child: VersionSurfaceView(
                          sheets: sheets,
                          version: v,
                          images: services.images,
                        ),
                      ),
              ),
              const SizedBox(width: Gaps.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        if (v.kind == VersionKind.named) ...[
                          const Icon(Symbols.bookmark_sharp, size: Glyphs.menu, fill: 1),
                          const SizedBox(width: Gaps.xs),
                        ],
                        Flexible(
                          child: Text(
                            title,
                            style: theme.textTheme.labelLarge,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: Gaps.sm),
                        Text(
                          VersionLabels.time(v),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontFeatures: AppTheme.tabularFigures,
                          ),
                        ),
                      ],
                    ),
                    Text(
                      '$device, ${summary[0].toLowerCase()}${summary.substring(1)}',
                      style: theme.textTheme.bodySmall,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              PopupMenuButton<_VersionAction>(
                tooltip: 'Version options',
                icon: const Icon(Symbols.more_horiz_sharp),
                onSelected: onAction,
                itemBuilder: (_) => [
                  const MenuRow(
                    value: _VersionAction.restore,
                    icon: Symbols.restore_sharp,
                    label: 'Restore…',
                  ),
                  const MenuRow(
                    value: _VersionAction.copy,
                    icon: Symbols.library_add_sharp,
                    label: 'Copy as new notebook',
                  ),
                  const MenuRow(
                    value: _VersionAction.rename,
                    icon: Symbols.edit_sharp,
                    label: 'Rename…',
                  ),
                  const PopupMenuDivider(),
                  const MenuRow(
                    value: _VersionAction.delete,
                    icon: Symbols.delete_sharp,
                    label: 'Delete version',
                    destructive: true,
                  ),
                  if (hasOlder)
                    const MenuRow(
                      value: _VersionAction.deleteOlder,
                      icon: Symbols.delete_sweep_sharp,
                      label: 'Delete older versions…',
                      destructive: true,
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
