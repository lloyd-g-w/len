import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../domain/notebook.dart';
import '../../../domain/notebook_page.dart';
import '../../../ui/app_theme.dart';
import '../progress_dialog.dart';
import 'pdf_import.dart';

const _pdfTypes = [
  XTypeGroup(label: 'PDF', extensions: ['pdf'], mimeTypes: ['application/pdf']),
];

/// Creates a notebook from PDF [file] (one page per PDF page,
/// annotatable), letting the user pick one if not given. Returns null if
/// cancelled or failed (the user has then been told why).
Future<Notebook?> importPdfFlow(BuildContext context, {XFile? file}) async {
  final services = AppScope.read(context);
  final picked = file ?? await openFile(acceptedTypeGroups: _pdfTypes);
  if (picked == null || !context.mounted) return null;
  final importer = PdfImporter(services);
  try {
    return await runWithSteps(context, 'Importing PDF', subject: picked.name, (progress) async {
      progress.stageStarted('Copying file…');
      final sha = await importer.store(picked);
      progress.stageStarted('Reading pages…');
      return importer.createNotebook(
        sha,
        title: PdfImporter.titleFor(picked.name),
        cover: Palette.covers[3],
        onPages: (n) => progress.stageStarted('Creating pages…', note: _pages(n)),
      );
    });
  } on Exception catch (e) {
    if (context.mounted) showMessage(context, _failure(picked.name, e));
    return null;
  } finally {
    await importer.dispose();
  }
}

/// Inserts the pages of PDF [file] (picked by the user if not given)
/// after [after] (at the end if null). Returns the inserted pages, or null.
Future<List<NotebookPage>?> insertPdfPagesFlow(
  BuildContext context, {
  required String notebookId,
  NotebookPage? after,
  XFile? file,
}) async {
  final services = AppScope.read(context);
  final picked = file ?? await openFile(acceptedTypeGroups: _pdfTypes);
  if (picked == null || !context.mounted) return null;
  final importer = PdfImporter(services);
  try {
    return await runWithSteps(context, 'Inserting pages', subject: picked.name, (progress) async {
      progress.stageStarted('Copying file…');
      final sha = await importer.store(picked);
      progress.stageStarted('Reading pages…');
      return importer.insertPages(
        sha,
        notebookId: notebookId,
        after: after,
        onPages: (n) => progress.stageStarted('Inserting pages…', note: _pages(n)),
      );
    });
  } on Exception catch (e) {
    if (context.mounted) showMessage(context, _failure(picked.name, e));
    return null;
  } finally {
    await importer.dispose();
  }
}

String _failure(String name, Exception e) {
  debugPrint('PDF import of $name failed: $e');
  return 'Couldn’t open “$name”. Is it a valid, unencrypted PDF?';
}

String _pages(int n) => n == 1 ? '1 page' : '$n pages';
