import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../../../app_services.dart';
import '../../../domain/notebook.dart';
import '../../../domain/notebook_page.dart';
import '../../../ui/app_theme.dart';
import '../progress_dialog.dart';
import 'pdf_import.dart';

const _pdfTypes = [
  XTypeGroup(label: 'PDF', extensions: ['pdf'], mimeTypes: ['application/pdf']),
];

/// Lets the user pick a PDF and creates a notebook from it (one page per
/// PDF page, annotatable). Returns null if cancelled or failed (the user
/// has then been told why).
Future<Notebook?> importPdfFlow(BuildContext context) async {
  final services = AppScope.read(context);
  final file = await openFile(acceptedTypeGroups: _pdfTypes);
  if (file == null || !context.mounted) return null;
  final importer = PdfImporter(services);
  try {
    return await runWithProgress(context, 'Importing “${file.name}”…', () async {
      final sha = await _store(importer, file);
      return importer.createNotebook(
        sha,
        title: PdfImporter.titleFor(file.name),
        cover: Palette.covers[3],
      );
    });
  } on Exception catch (e) {
    if (context.mounted) showMessage(context, _failure(file.name, e));
    return null;
  } finally {
    await importer.dispose();
  }
}

/// Lets the user pick a PDF and inserts its pages after [after] (at the end
/// if null). Returns the inserted pages, or null.
Future<List<NotebookPage>?> insertPdfPagesFlow(
  BuildContext context, {
  required String notebookId,
  NotebookPage? after,
}) async {
  final services = AppScope.read(context);
  final file = await openFile(acceptedTypeGroups: _pdfTypes);
  if (file == null || !context.mounted) return null;
  final importer = PdfImporter(services);
  try {
    return await runWithProgress(context, 'Inserting “${file.name}”…', () async {
      final sha = await _store(importer, file);
      return importer.insertPages(sha, notebookId: notebookId, after: after);
    });
  } on Exception catch (e) {
    if (context.mounted) showMessage(context, _failure(file.name, e));
    return null;
  } finally {
    await importer.dispose();
  }
}

/// Copies the picked file into the blob store. Desktop pickers return real
/// paths; Android may hand out content that is only readable as bytes.
Future<String> _store(PdfImporter importer, XFile file) async {
  final path = file.path;
  if (path.isNotEmpty && File(path).existsSync()) return importer.store(File(path));
  final temp = File(p.join(Directory.systemTemp.path, 'len_import_${file.name}'));
  await temp.writeAsBytes(await file.readAsBytes(), flush: true);
  try {
    return await importer.store(temp);
  } finally {
    await temp.delete();
  }
}

String _failure(String name, Exception e) {
  debugPrint('PDF import of $name failed: $e');
  return 'Couldn’t open “$name”. Is it a valid, unencrypted PDF?';
}
