import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';

import '../../../app_services.dart';
import '../../../data/blob_references.dart';
import '../../../data/page_repository.dart';
import '../../../domain/cancellation.dart';
import '../../../domain/notebook.dart';
import '../../../domain/notebook_page.dart';
import '../../../domain/paper.dart';
import '../notebook_gone.dart';
import 'pdf_renderer.dart';

/// World units (96 per inch) per PDF point (72 per inch).
const double worldPerPoint = 96 / 72;

/// Turns PDF files into notebook pages whose backgrounds are the PDF's
/// pages. The PDF itself is stored once, as a content-addressed blob.
class PdfImporter {
  PdfImporter(this.services, {PdfRenderer? renderer})
    : _renderer = renderer ?? PdfRenderer(services.blobs);

  final AppServices services;
  final PdfRenderer _renderer;

  /// Stores [file] as a blob and returns its id. Desktop pickers give
  /// paths (streamed); Android and browsers give the picked bytes.
  Future<String> store(XFile file, {CancellationToken? cancel}) =>
      services.blobs.putFile(file, mime: 'application/pdf', cancel: cancel);

  /// Deletes blob [sha] again if nothing uses it (an import was cancelled
  /// or failed after [store]). Closes the file first (Windows can't delete
  /// open files); a blob that can't be deleted is left to the garbage
  /// collector.
  Future<void> discard(String sha) async {
    await _renderer.dispose();
    try {
      final references = BlobReferences(services.database);
      await services.blobs.discardIfUnreferenced(
        sha,
        () => references.kept(services.blobs.clock.nowMs()),
      );
    } on Object catch (e) {
      debugPrint('Could not discard PDF blob $sha: $e');
    }
  }

  /// Page specs (one per PDF page) for blob [sha]. A [cancel]led token
  /// stops the wait at once (PDFium measures a huge PDF in one call).
  Future<List<PageSpec>> specsFor(String sha, {CancellationToken? cancel}) async {
    final measuring = _renderer.pageSizes(sha);
    final sizes = await (cancel?.race(measuring) ?? measuring);
    if (sizes.isEmpty) throw const FormatException('The PDF has no pages');
    return [
      for (var i = 0; i < sizes.length; i++)
        (
          size: sizes[i] * worldPerPoint,
          paper: Paper.blank,
          color: PaperColor.white,
          background: PageBackground.pdf(blob: sha, pageIndex: i),
        ),
    ];
  }

  /// Creates a notebook titled [title] with one page per PDF page;
  /// [onPages] hears the page count before the pages are created (and may
  /// throw to stop before anything is created, e.g. [Cancelled]). [cancel]
  /// stops it while the pages are measured.
  Future<Notebook> createNotebook(
    String sha, {
    required String title,
    required int cover,
    void Function(int pages)? onPages,
    CancellationToken? cancel,
  }) async {
    final specs = await specsFor(sha, cancel: cancel);
    onPages?.call(specs.length);
    final notebook = services.database.transaction(() {
      final notebook = services.notebooks.create(
        title: title,
        kind: NotebookKind.paged,
        paper: PaperStyle.blank,
        coverColor: cover,
      );
      final blank = services.pages.pagesOf(notebook.id);
      services.pages.insertPages(notebook.id, specs);
      for (final page in blank) {
        services.pages.delete(page.id);
      }
      return notebook;
    });
    unawaited(services.search.indexPdfs()); // Make its text searchable.
    return notebook;
  }

  /// Inserts the PDF's pages into [notebookId] after [after] (at the end
  /// if null); returns the new pages. [onPages] hears the page count (and
  /// may throw to stop before anything is inserted); [cancel] stops it
  /// while the pages are measured.
  Future<List<NotebookPage>> insertPages(
    String sha, {
    required String notebookId,
    NotebookPage? after,
    void Function(int pages)? onPages,
    CancellationToken? cancel,
  }) async {
    final specs = await specsFor(sha, cancel: cancel);
    onPages?.call(specs.length);
    NotebookGone.check(services, notebookId); // Deleted while it was read.
    final pages = services.pages.insertPages(notebookId, specs, after: after);
    unawaited(services.search.indexPdfs());
    return pages;
  }

  Future<void> dispose() => _renderer.dispose();

  /// A notebook title from a file name: `Lecture_3-notes.pdf` → `Lecture 3-notes`.
  static String titleFor(String fileName) {
    final dot = fileName.toLowerCase().endsWith('.pdf') ? fileName.length - 4 : fileName.length;
    final title = fileName.substring(0, dot).replaceAll('_', ' ').trim();
    return title.isEmpty ? 'Imported PDF' : title;
  }
}
