import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../data/page_repository.dart';
import '../../../domain/notebook_page.dart';
import '../../../domain/paper.dart';
import '../../../ui/app_dialogs.dart';
import '../progress_dialog.dart';
import 'pdf_import.dart';
import 'pdf_open_failure.dart';
import 'pdf_renderer.dart';

const _pdfTypes = [
  XTypeGroup(label: 'PDF', extensions: ['pdf'], mimeTypes: ['application/pdf']),
];

/// A PDF chosen to replace another in a notebook ([replacePdfFlow]).
typedef PdfReplacement = ({
  /// The PDF it replaces.
  String from,

  /// The new PDF's blob.
  String blob,

  /// The sizes of its pages, by index (the pages drawn on them take their
  /// shape, see [NotebookPage.sizeFor]).
  List<Size> shapes,

  /// Pages for the new PDF's pages beyond the old one's end, to add after
  /// [after]; empty when it has none, or the notebook didn't show the old
  /// one's last page.
  List<PageSpec> extra,

  /// The last page showing the old PDF.
  NotebookPage after,
});

/// Lets the user pick a new version of the PDF page [pageId] of
/// [notebookId] is drawn on (the lecturer's corrected slides) for the
/// pages drawn on it, keeping their notes (UX_AUDIT R18-1). Checks the
/// file, asks, and returns what to change; null if cancelled, refused or
/// failed (the user has been told why). The caller makes the change
/// (undoably). The page is read again once the file is copied: a sync may
/// have changed its PDF meanwhile (that one is replaced) or deleted it.
Future<PdfReplacement?> replacePdfFlow(
  BuildContext context, {
  required String notebookId,
  required String pageId,
  XFile? file,
}) async {
  final services = AppScope.read(context);
  final picked = file ?? await openFile(acceptedTypeGroups: _pdfTypes);
  if (picked == null || !context.mounted) return null;
  final importer = PdfImporter(services);
  final renderer = PdfRenderer(services.blobs);
  String? sha;
  String? current; // The PDF the page shows now.
  Future<PdfReplacement?> discard() async {
    await renderer.dispose();
    if (sha != null && sha != current) await importer.discard(sha!);
    return null;
  }

  try {
    final read = await runWithSteps(
      context,
      'Replacing PDF',
      subject: picked.name,
      cancellable: true,
      (progress) async {
        progress.stageStarted('Copying file…');
        sha = await importer.store(picked, cancel: progress.token);
        final page = services.pages.get(pageId);
        current = page?.pdf?.blob;
        if (current == null) return (page: page, sizes: const <Size>[], oldCount: null);
        if (sha == current) return null;
        progress.stageStarted('Reading pages…');
        final sizes = await renderer.pageSizes(sha!);
        // The old one's length, if it is here (else: what the notes use).
        int? oldCount;
        try {
          oldCount = (await renderer.pageSizes(current!)).length;
        } on Object {
          oldCount = null;
        }
        return (page: page, sizes: sizes, oldCount: oldCount);
      },
    );
    if (!context.mounted) return await discard();
    if (sha == current) {
      showMessage(context, 'These pages already show “${picked.name}”');
      return null;
    }
    if (read == null) return await discard();
    if (current == null) {
      showMessage(
        context,
        read.page == null ? 'This page was deleted meanwhile' : 'This page no longer shows a PDF',
      );
      return await discard();
    }

    final using = [
      for (final page in services.pages.pagesOf(notebookId))
        if (page.pdf case final bg? when bg.blob == current) (page: page, index: bg.pageIndex),
    ];
    if (using.isEmpty) return await discard();
    final needed = using.map((u) => u.index).reduce((a, b) => a > b ? a : b) + 1;
    final count = read.sizes.length;
    if (count < needed) {
      showMessage(
        context,
        '“${picked.name}” has ${_pages(count)}; these notes use page $needed of the old PDF',
      );
      return await discard();
    }
    // New slides at the end come along when the notebook shows the old end.
    final oldCount = read.oldCount ?? needed;
    final extra = needed < oldCount
        ? const <PageSpec>[]
        : [
            for (var i = oldCount; i < count; i++)
              (
                size: read.sizes[i] * worldPerPoint,
                paper: Paper.blank,
                color: PaperColor.white,
                background: PageBackground.pdf(blob: sha!, pageIndex: i),
              ),
          ];
    final after = using.last.page;
    final reshaped = using.any((u) => u.page.sizeFor(read.sizes[u.index]) != u.page.size);
    final agreed = await confirmAction(
      context,
      title: 'Replace the PDF?',
      message:
          '“${picked.name}” will show under the notes on ${_pages(using.length)}, page for '
          'page; the notes stay where they are.'
          '${extra.isEmpty ? '' : ' Its ${_newPages(extra.length)} added at the end.'}'
          '${reshaped ? ' Pages change shape to match.' : ''}',
      confirmLabel: 'Replace',
    );
    if (!agreed) return await discard();
    return (from: current!, blob: sha!, shapes: read.sizes, extra: extra, after: after);
  } on Cancelled {
    return await discard();
  } on Object catch (e, stack) {
    debugPrint('Replacing with ${picked.name} failed: $e\n$stack');
    if (context.mounted) showMessage(context, pdfOpenFailure(picked.name, e));
    return await discard();
  } finally {
    await renderer.dispose();
    await importer.dispose();
  }
}

String _pages(int n) => n == 1 ? '1 page' : '$n pages';

String _newPages(int n) => n == 1 ? '1 new page is' : '$n new pages are';
