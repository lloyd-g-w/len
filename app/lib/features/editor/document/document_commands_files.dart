part of 'document_commands.dart';

/// Pages in and out of a paged notebook: PDFs (inserting, relinking),
/// scans and exports.
mixin _DocumentFiles {
  Notebook Function() get notebook;
  DocumentController get doc;
  PageEdits get edits;
  TextFlowChains get flows;
  NotebookPage get _current;

  /// [PageEdits.replacePdf] with the text on pages changing shape flowed
  /// again (a part past a shorter page's bottom goes on to the next page),
  /// as one undo step.
  PageEdit _replacePdf({
    required String from,
    required String to,
    required List<Size> shapes,
    List<PageSpec> extra = const [],
    NotebookPage? after,
  }) {
    final sizes = {for (final p in doc.pages) p.id: p.size};
    late PageEdit edit;
    flows.pages.batch(() {
      edit = edits.replacePdf(from: from, to: to, shapes: shapes, extra: extra, after: after);
      flows.reflowOn([
        for (final p in doc.pages)
          if (sizes[p.id] case final size? when size != p.size) p.id,
      ]);
    });
    return edit;
  }

  /// Lets the user pick a file for PDF [blob], which pages of this notebook
  /// are drawn on but which can't be had (UX_AUDIT #24).
  Future<void> relinkPdf(
    BuildContext context,
    String blob,
    PdfBackgroundCache backgrounds, {
    XFile? file,
  }) async {
    final result = await relinkPdfFlow(
      context,
      notebookId: notebook().id,
      missing: blob,
      use: (to, shapes) => _replacePdf(from: blob, to: to, shapes: shapes),
      file: file,
    );
    switch (result) {
      case RelinkResult.restored:
        backgrounds.retryMissing();
        if (context.mounted) showMessage(context, 'PDF found');
      case RelinkResult.replaced:
        if (context.mounted) showMessage(context, 'PDF relinked');
      case RelinkResult.none:
    }
  }

  /// Lets the user pick a new version of the PDF [page] is drawn on (the
  /// lecturer's corrected slides) and shows it under the notes of every
  /// page drawn on the old one, as one undoable step (UX_AUDIT R18-1).
  Future<void> replacePdf(BuildContext context, NotebookPage page, {XFile? file}) async {
    if (page.pdf == null) return;
    final services = AppScope.read(context);
    final replacement = await replacePdfFlow(
      context,
      notebookId: notebook().id,
      pageId: page.id,
      file: file,
    );
    if (replacement == null) return;
    final edit = _replacePdf(
      from: replacement.from,
      to: replacement.blob,
      shapes: replacement.shapes,
      extra: replacement.extra,
      after: replacement.after,
    );
    unawaited(services.search.indexPdfs()); // Its text, for search.
    if (!context.mounted) return;
    showMessage(
      context,
      'PDF replaced',
      action: SnackBarAction(label: 'Undo', onPressed: () => edits.models.undoEdit(edit)),
    );
  }

  /// Inserts the pages of PDF [file] (picked by the user if null) after
  /// the current page; a Cancel there cancels [batch].
  Future<void> insertPdf(BuildContext context, {XFile? file, CancellationToken? batch}) async {
    final inserted = await insertPdfPagesFlow(
      context,
      notebookId: notebook().id,
      after: _current,
      file: file,
      batch: batch,
    );
    if (inserted == null || inserted.isEmpty) return;
    edits.added(inserted);
  }

  /// Scans pages (the scan screen, starting with [photos] if any) and
  /// inserts them after page [afterPageId] (the current page if null or
  /// gone).
  Future<void> insertScan(
    BuildContext context, {
    List<XFile> photos = const [],
    String? afterPageId,
  }) async {
    final after = doc.pages.where((p) => p.id == afterPageId).firstOrNull ?? _current;
    final inserted = await scanIntoNotebookFlow(
      context,
      notebookId: notebook().id,
      after: after,
      photos: photos,
    );
    if (inserted == null || inserted.isEmpty) return;
    edits.added(inserted);
  }

  /// Opens the export sheet with [pages] (the overview's selection) as
  /// its page range, then exports.
  Future<void> exportPages(BuildContext context, List<NotebookPage> pages) {
    final all = doc.pages;
    final ids = {for (final p in pages) p.id};
    return exportFlow(
      context,
      notebook: notebook(),
      pages: all,
      currentPage: doc.currentPage,
      initialPages: [
        for (var i = 0; i < all.length; i++)
          if (ids.contains(all[i].id)) i,
      ],
    );
  }

  /// Opens the export sheet with [range] (all pages or the current one)
  /// preselected, then exports.
  Future<void> export(BuildContext context, {ExportRange range = ExportRange.all}) => exportFlow(
    context,
    notebook: notebook(),
    pages: doc.pages,
    currentPage: doc.currentPage,
    initialRange: range,
  );
}
