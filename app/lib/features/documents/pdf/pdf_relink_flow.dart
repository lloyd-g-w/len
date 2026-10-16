import 'dart:async';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../ui/app_dialogs.dart';
import '../progress_dialog.dart';
import 'pdf_import.dart';
import 'pdf_open_failure.dart';
import 'pdf_renderer.dart';
import 'pdf_reshape_note.dart';

const _pdfTypes = [
  XTypeGroup(label: 'PDF', extensions: ['pdf'], mimeTypes: ['application/pdf']),
];

/// How a relink ended.
enum RelinkResult {
  /// The file picked is the missing PDF itself: it is on this device again.
  restored,

  /// A different PDF now backs the pages that used the missing one.
  replaced,

  /// Cancelled, refused or failed (the user has been told why).
  none,
}

/// Lets the user pick a file for PDF [missing] that the pages of
/// [notebookId] are drawn on (UX_AUDIT #24). The same file restores it; a
/// different one (e.g. the same handout downloaded again) is used for
/// those pages once the user agrees, page for page, keeping their notes:
/// [use] makes that change (undoably) with the new PDF's blob and the
/// sizes of its pages, whose shape the pages take.
Future<RelinkResult> relinkPdfFlow(
  BuildContext context, {
  required String notebookId,
  required String missing,
  required void Function(String blob, List<Size> shapes) use,
  XFile? file,
}) async {
  final services = AppScope.read(context);
  final picked = file ?? await openFile(acceptedTypeGroups: _pdfTypes);
  if (picked == null || !context.mounted) return RelinkResult.none;
  final importer = PdfImporter(services);
  final renderer = PdfRenderer(services.blobs);
  String? sha;
  try {
    final sizes = await runWithSteps(
      context,
      'Relinking PDF',
      subject: picked.name,
      cancellable: true,
      (progress) async {
        progress.stageStarted('Copying file…');
        sha = await importer.store(picked, cancel: progress.token);
        if (sha == missing) return null;
        progress.stageStarted('Reading pages…');
        return renderer.pageSizes(sha!);
      },
    );
    if (sha == missing) return RelinkResult.restored;
    if (!context.mounted || sizes == null) return await _discard(importer, renderer, sha);

    // The pages that used the missing PDF, and the furthest page they use.
    final used = [
      for (final page in services.pages.pagesOf(notebookId))
        if (page.pdf case final bg? when bg.blob == missing) (page: page, index: bg.pageIndex),
    ];
    if (used.isEmpty) return await _discard(importer, renderer, sha);
    final needed = used.map((u) => u.index).reduce((a, b) => a > b ? a : b) + 1;
    final pageCount = sizes.length;
    if (pageCount < needed) {
      showMessage(
        context,
        '“${picked.name}” has ${_pages(pageCount)}; these notes use page $needed of the '
        'missing PDF',
      );
      return await _discard(importer, renderer, sha);
    }
    final agreed = await confirmAction(
      context,
      title: 'Use a different PDF?',
      message:
          '“${picked.name}” isn’t the file these pages were made from. Its pages will show '
          'under the notes on ${_pages(used.length)}, page for page; the notes stay where '
          'they are.${pdfReshapeNote(services, used, sizes)}',
      confirmLabel: 'Use this PDF',
    );
    if (!agreed) return await _discard(importer, renderer, sha);
    use(sha!, sizes);
    unawaited(services.search.indexPdfs()); // Its text, for search.
    return RelinkResult.replaced;
  } on Cancelled {
    return await _discard(importer, renderer, sha);
  } on Object catch (e, stack) {
    debugPrint('Relinking ${picked.name} failed: $e\n$stack');
    if (context.mounted) {
      showMessage(context, pdfOpenFailure(picked.name, e));
    }
    return await _discard(importer, renderer, sha);
  } finally {
    await renderer.dispose();
    await importer.dispose();
  }
}

/// Deletes the copied file again unless it is the missing one or used
/// (closed first: Windows can't delete open files).
Future<RelinkResult> _discard(PdfImporter importer, PdfRenderer renderer, String? sha) async {
  await renderer.dispose();
  if (sha != null) await importer.discard(sha);
  return RelinkResult.none;
}

String _pages(int n) => n == 1 ? '1 page' : '$n pages';
