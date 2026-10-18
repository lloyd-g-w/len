import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../app_services.dart';
import '../../data/versions/versions.dart';
import '../../sync/remote_changes.dart';
import '../../ui/app_theme.dart';
import '../../ui/dialog_or_sheet.dart';
import '../../ui/section_label.dart';
import '../../ui/sheet_parts.dart';
import '../documents/pdf/pdf_background_cache.dart';
import '../editor/document/notebook_backgrounds.dart';
import 'version_flows.dart';
import 'version_labels.dart';
import 'version_preview.dart';
import 'version_row.dart';
import 'version_surface_view.dart';

/// "Version history…" (docs/ARCHITECTURE.md, "Version history"): the
/// versions of notebook [notebookId], newest first, grouped by day. A
/// version opens its preview; its ⋯ restores, copies, renames or deletes.
/// Restores are told on [context]'s screen, the rest on the sheet.
Future<void> showVersionHistory(BuildContext context, AppServices services, String notebookId) =>
    showDialogOrSheet<void>(
      context: context,
      maxHeight: 720,
      sheetHeightFactor: 0.85,
      builder: (sheet, wide) {
        final history = VersionHistory(
          services: services,
          notebookId: notebookId,
          wide: wide,
          message: context,
        );
        // A sheet covers the screen's snack bars: what is done in it
        // (saved, copied, deleted) is said on the sheet.
        return wide
            ? history
            : ScaffoldMessenger(
                child: Scaffold(backgroundColor: Colors.transparent, body: history),
              );
      },
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
  late final VersionSheets _sheets = VersionSheets(
    widget.services.versions,
    backgrounds: NotebookBackgrounds(
      pdf: PdfBackgroundCache(blobs: widget.services.blobs, fetch: widget.services.sync.fetchBlob),
      images: widget.services.images,
    ),
  );
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
    _sheets.dispose();
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
        final entries = _entries(versions, now);
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              // The progress bar below takes the rest of the gap.
              padding: EdgeInsets.fromLTRB(
                Gaps.lg,
                widget.wide ? Gaps.lg : 0,
                Gaps.lg,
                Gaps.sm - Hairline.rule,
              ),
              child: LayoutBuilder(
                builder: (context, box) => SheetHeader(
                  title: 'Version history',
                  subtitle: title,
                  onClose: () => Navigator.of(context).pop(),
                  trailing: _saveButton(context, box.maxWidth),
                ),
              ),
            ),
            // A restore or copy from a row's ⋯ runs with the list in view.
            ValueListenableBuilder(
              valueListenable: versionWork,
              builder: (context, running, _) => SizedBox(
                height: Hairline.rule,
                child: running == null ? null : const LinearProgressIndicator(),
              ),
            ),
            Flexible(
              child: versions.isEmpty
                  ? _empty(context)
                  : ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(bottom: Gaps.lg),
                      itemCount: entries.length,
                      // Nothing in a row keeps it alive scrolled away.
                      addAutomaticKeepAlives: false,
                      itemBuilder: (context, i) => _entry(entries[i]),
                      findChildIndexCallback: (key) {
                        final i = entries.indexWhere((e) => ValueKey(e.key) == key);
                        return i < 0 ? null : i;
                      },
                    ),
            ),
          ],
        );
      },
    );
  }

  /// The list's rows: a heading for each day, then its versions, newest
  /// first (with what their rows say worked out here, once).
  List<_Entry> _entries(List<NotebookVersion> versions, DateTime now) {
    final thisDevice = widget.services.strokes.deviceId;
    final entries = <_Entry>[];
    String? day;
    for (final (i, v) in versions.indexed) {
      final label = VersionLabels.day(v.createdAt, now: now);
      if (label != day) {
        day = label;
        entries.add((key: 'day-$label', day: label, version: null, labels: null, hasOlder: false));
      }
      final last = i == versions.length - 1;
      entries.add((
        key: 'version-${v.id}',
        day: null,
        version: v,
        labels: VersionRowLabels(v, first: last, thisDevice: thisDevice),
        hasOlder: !last,
      ));
    }
    return entries;
  }

  Widget _entry(_Entry e) {
    final v = e.version;
    if (v == null) {
      return Padding(
        key: ValueKey(e.key),
        padding: const EdgeInsets.fromLTRB(Gaps.lg, Gaps.md, Gaps.lg, Gaps.xs),
        child: SectionLabel(e.day!),
      );
    }
    return VersionRow(
      key: ValueKey(e.key),
      version: v,
      labels: e.labels!,
      hasOlder: e.hasOlder,
      sheets: _sheets,
      services: widget.services,
      onOpen: () => _open(v),
      onAction: (a) => _act(a, v),
    );
  }

  /// "Save version…" as a text button, or as an icon where its label would
  /// squeeze the title (phones, large text).
  Widget _saveButton(BuildContext context, double width) {
    void save() => unawaited(saveVersionFlow(widget.message, widget.services, widget.notebookId));
    const label = 'Save version…';
    final text = Theme.of(context).textTheme;
    final scaler = MediaQuery.textScalerOf(context);
    double measure(String s, TextStyle? style) {
      final painter = TextPainter(
        text: TextSpan(text: s, style: style),
        textScaler: scaler,
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      final width = painter.width;
      painter.dispose();
      return width;
    }

    // Title, label, the button's padding and the ✕.
    final needed =
        measure('Version history', text.titleMedium) +
        measure(label, text.labelLarge) +
        Gaps.xxl +
        Targets.barHit(context);
    if (needed <= width) return TextButton(onPressed: save, child: const Text(label));
    return IconButton(
      tooltip: label,
      icon: const Icon(Symbols.bookmark_add_sharp),
      onPressed: save,
    );
  }

  Widget _empty(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.all(Gaps.xl),
      child: Text(
        'No versions yet. Len keeps one when you pause writing, and you can save one '
        'yourself at any time.',
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

  Future<void> _act(VersionAction action, NotebookVersion v) async {
    final services = widget.services;
    switch (action) {
      case VersionAction.restore:
        if (await restoreVersionFlow(context, services, v, message: widget.message)) _close();
      case VersionAction.copy:
        await copyVersionFlow(context, services, v);
      case VersionAction.rename:
        await renameVersionFlow(context, services, v);
      case VersionAction.delete:
        deleteVersionFlow(context, services, v);
      case VersionAction.deleteOlder:
        await deleteOlderFlow(context, services, v);
    }
  }
}

/// A row of the history: a day's heading ([day]) or a [version].
typedef _Entry = ({
  String key,
  String? day,
  NotebookVersion? version,
  VersionRowLabels? labels,
  bool hasOlder,
});
