import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../data/page_repository.dart';
import '../../../domain/notebook.dart';
import '../../../domain/notebook_page.dart';
import '../../../ui/app_theme.dart';
import '../../camera/camera_purpose.dart';
import '../progress_dialog.dart';
import 'scan_import.dart';
import 'scan_screen.dart';
import 'scan_session.dart';
import 'scan_sources.dart';

/// Scans pages (the scan screen) into a new notebook titled after today,
/// e.g. "Scan Oct 14", starting with [photos] if any. Returns it, or null
/// if the user left or it failed (they have then been told why).
Future<Notebook?> scanToNewNotebookFlow(
  BuildContext context, {
  ScanSources? sources,
  List<XFile> photos = const [],
}) {
  final today = AppScope.read(context).clock.nowDate();
  final title = 'Scan ${MaterialLocalizations.of(context).formatShortMonthDay(today)}';
  return _scanFlow(
    context,
    doneLabel: 'Create notebook',
    progressTitle: 'Creating notebook',
    sources: sources,
    purpose: const ScanNewNotebook(),
    photos: photos,
    store: (importer, specs) =>
        importer.createNotebook(specs, title: title, cover: Palette.covers.first),
  );
}

/// Scans pages (the scan screen) into notebook [notebookId] after [after]
/// (at the end if null), starting with [photos] if any. Returns the new
/// pages, or null if the user left or it failed (they have then been told
/// why).
Future<List<NotebookPage>?> scanIntoNotebookFlow(
  BuildContext context, {
  required String notebookId,
  NotebookPage? after,
  ScanSources? sources,
  List<XFile> photos = const [],
}) => _scanFlow(
  context,
  doneLabel: 'Insert',
  progressTitle: 'Inserting pages',
  sources: sources,
  purpose: ScanIntoNotebook(notebookId, afterPageId: after?.id),
  photos: photos,
  store: (importer, specs) => importer.insertPages(specs, notebookId: notebookId, after: after),
);

Future<T?> _scanFlow<T>(
  BuildContext context, {
  required String doneLabel,
  required String progressTitle,
  required ScanSources? sources,
  required CameraPurpose purpose,
  required List<XFile> photos,
  required T Function(ScanImporter importer, List<PageSpec> specs) store,
}) async {
  final services = AppScope.read(context);
  final settings = services.settings;
  final session = ScanSession(
    filter: ScanFilter.parse(settings.scanFilter),
    onFilterChanged: (f) => settings.scanFilter = f.name,
  );
  final route = MaterialPageRoute<bool>(
    builder: (_) => ScanScreen(
      session: session,
      doneLabel: doneLabel,
      sources: sources ?? ScanSources.current,
      purpose: purpose,
      initialPhotos: photos,
    ),
  );
  try {
    final done = await Navigator.of(context).push(route);
    if (done != true || session.pages.isEmpty || !context.mounted) return null;
    final importer = ScanImporter(services);
    try {
      return await runWithSteps(context, progressTitle, cancellable: true, (progress) async {
        final specs = await importer.render(
          session.pages,
          session.filter,
          onPage: (i, n) => progress.step(i, n, stage: 'Preparing pages…'),
        );
        progress.check();
        return store(importer, specs);
      });
    } on Cancelled {
      await importer.discard();
      return null;
    } on Object catch (e, stack) {
      debugPrint('Scan import failed: $e\n$stack');
      await importer.discard();
      if (context.mounted) showMessage(context, 'Couldn’t add the scanned pages');
      return null;
    }
  } finally {
    // The screen still paints the session's images while it slides away.
    unawaited(route.completed.whenComplete(session.dispose));
  }
}
