import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../data/page_repository.dart';
import '../../../domain/notebook.dart';
import '../../../domain/notebook_page.dart';
import '../../../ui/app_theme.dart';
import '../progress_dialog.dart';
import 'scan_import.dart';
import 'scan_screen.dart';
import 'scan_session.dart';
import 'scan_sources.dart';

/// Scans pages (the scan screen) into a new notebook titled after today,
/// e.g. "Scan Oct 14". Returns it, or null if the user left or it failed
/// (they have then been told why).
Future<Notebook?> scanToNewNotebookFlow(
  BuildContext context, {
  ScanSources sources = ScanSources.system,
}) {
  final title = 'Scan ${MaterialLocalizations.of(context).formatShortMonthDay(DateTime.now())}';
  return _scanFlow(
    context,
    doneLabel: 'Create notebook',
    progressTitle: 'Creating notebook',
    sources: sources,
    store: (importer, specs) =>
        importer.createNotebook(specs, title: title, cover: Palette.covers.first),
  );
}

/// Scans pages (the scan screen) into notebook [notebookId] after [after]
/// (at the end if null). Returns the new pages, or null if the user left
/// or it failed (they have then been told why).
Future<List<NotebookPage>?> scanIntoNotebookFlow(
  BuildContext context, {
  required String notebookId,
  NotebookPage? after,
  ScanSources sources = ScanSources.system,
}) => _scanFlow(
  context,
  doneLabel: 'Insert',
  progressTitle: 'Inserting pages',
  sources: sources,
  store: (importer, specs) => importer.insertPages(specs, notebookId: notebookId, after: after),
);

Future<T?> _scanFlow<T>(
  BuildContext context, {
  required String doneLabel,
  required String progressTitle,
  required ScanSources sources,
  required T Function(ScanImporter importer, List<PageSpec> specs) store,
}) async {
  final services = AppScope.read(context);
  final session = ScanSession();
  try {
    final done = await Navigator.of(context).push<bool>(
      MaterialPageRoute(
        builder: (_) => ScanScreen(session: session, doneLabel: doneLabel, sources: sources),
      ),
    );
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
    session.dispose();
  }
}
