import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../domain/notebook.dart';
import '../../../domain/notebook_page.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/error_details.dart';
import '../progress_dialog.dart';
import 'pdf_import.dart';
import 'pdf_open_failure.dart';

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
  String? sha;
  try {
    return await runWithSteps(context, 'Importing PDF', subject: picked.name, cancellable: true, (
      progress,
    ) async {
      progress.stageStarted('Copying file…');
      sha = await importer.store(picked, cancel: progress.token);
      progress.stageStarted('Reading pages…');
      return importer.createNotebook(
        sha!,
        title: PdfImporter.titleFor(picked.name),
        cover: Palette.covers[3],
        onPages: (n) => progress.stageStarted('Creating pages…', note: _pages(n)),
      );
    });
  } on Cancelled {
    if (sha != null) await importer.discard(sha!);
    return null;
  } on Object catch (e, stack) {
    // A file that can't be read is not kept either.
    if (sha != null) await importer.discard(sha!);
    // Errors too (a malformed file can trip a parser): never fail silently.
    if (context.mounted) _showFailure(context, picked.name, e, stack, stored: sha != null);
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
  String? sha;
  try {
    return await runWithSteps(context, 'Inserting pages', subject: picked.name, cancellable: true, (
      progress,
    ) async {
      progress.stageStarted('Copying file…');
      sha = await importer.store(picked, cancel: progress.token);
      progress.stageStarted('Reading pages…');
      return importer.insertPages(
        sha!,
        notebookId: notebookId,
        after: after,
        onPages: (n) => progress.stageStarted('Inserting pages…', note: _pages(n)),
      );
    });
  } on Cancelled {
    if (sha != null) await importer.discard(sha!);
    return null;
  } on Object catch (e, stack) {
    // A file that can't be read is not kept either.
    if (sha != null) await importer.discard(sha!);
    // Errors too (a malformed file can trip a parser): never fail silently.
    if (context.mounted) _showFailure(context, picked.name, e, stack, stored: sha != null);
    return null;
  } finally {
    await importer.dispose();
  }
}

/// Tells the user why PDF [name] wasn't imported. Before it was [stored]
/// the file itself was fine as far as Len knows: copying failed (no space,
/// access lost), so it isn't blamed. Details has the raw error.
void _showFailure(
  BuildContext context,
  String name,
  Object e,
  StackTrace stack, {
  required bool stored,
}) {
  debugPrint('PDF import of $name failed: $e\n$stack');
  showMessage(
    context,
    stored ? pdfOpenFailure(name, e) : 'Couldn’t copy “$name” into Len',
    action: SnackBarAction(
      label: 'Details',
      onPressed: () => unawaited(showErrorDetails(context, title: 'Import failed', details: '$e')),
    ),
  );
}

String _pages(int n) => n == 1 ? '1 page' : '$n pages';
