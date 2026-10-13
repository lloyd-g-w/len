import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../data/page_repository.dart';
import '../../../data/surface_copier.dart';
import '../../../domain/notebook.dart';
import '../../../domain/notebook_page.dart';
import '../../../domain/paper.dart';
import '../../documents/export/export_flow.dart';
import '../../documents/export/notebook_exporter.dart';
import '../../documents/pdf/pdf_background_cache.dart';
import '../../documents/pdf/pdf_import_flow.dart';
import '../../documents/pdf/pdf_relink_flow.dart';
import '../../documents/progress_dialog.dart';
import '../../documents/template_picker.dart';
import '../../documents/templates/user_templates.dart';
import 'document_controller.dart';
import 'go_to_page_dialog.dart';
import 'page_actions.dart';
import 'page_backgrounds.dart';
import 'page_edits.dart';
import 'page_overview.dart';
import 'page_transfer_flow.dart';

/// The editor's page-level commands for a paged notebook, with their UI
/// (pickers, confirmations, undo snack bars).
class DocumentCommands {
  DocumentCommands({
    required this.services,
    required this.notebook,
    required this.doc,
    this.reloadViews,
  }) : actions = PageActions(services, notebook().id) {
    edits = PageEdits(actions: actions, models: doc.surfaces.models, shown: _shown);
  }

  final AppServices services;

  /// The open notebook (it may be renamed while open).
  final Notebook Function() notebook;
  final DocumentController doc;
  final PageActions actions;

  /// Reloads every open view of the notebook; for undoing page changes
  /// made here (the history is shared) after this editor closed.
  final VoidCallback? reloadViews;

  /// Page changes as steps of the notebook's undo history.
  late final PageEdits edits;

  /// Whether the page structure changed (pages added, moved, …).
  bool changed = false;

  NotebookPage get _current => doc.pages[doc.currentPage];

  /// Reloads the page list, keeping [keep] (or the current page) in view.
  /// A no-op once the editor closed (e.g. a page-delete snack bar's Undo
  /// pressed later still restores the page, but there is nothing to show).
  void reload({String? keep}) {
    if (!_disposed) doc.setPages(actions.pages, keepPageId: keep);
  }

  bool _disposed = false;

  /// The editor closed: later callbacks (snack bars, dialogs still
  /// resolving) only change data, not the disposed document.
  void dispose() => _disposed = true;

  /// After a page change (or its undo or redo): reloads, showing [keep].
  void _shown({String? keep}) {
    changed = true;
    if (_disposed) return reloadViews?.call();
    reload(keep: keep);
    final index = doc.pages.indexWhere((p) => p.id == keep);
    if (index != -1) doc.goToPage(index);
  }

  /// Adds a page like the current one (same paper and size; a planner's
  /// next day, week or month) after it.
  void addPage() => edits.add([PageActions.blankAfter(_current)], after: _current);

  /// Lets the user choose a template, then adds a page after the current.
  Future<void> addPageWithTemplate(BuildContext context) async {
    final choice = await showTemplatePicker(
      context,
      initial: _current.template,
      mode: TemplatePickerMode.addPage,
    );
    if (choice == null) return;
    edits.add([
      for (final paper in choice.papers) specOf(choice.template.copyWith(paper: paper)),
    ], after: _current);
  }

  /// Follows a planner link: shows the page with template [target], or
  /// offers to add one after the current page when the notebook has none.
  void followLink(BuildContext context, Paper target) {
    final index = doc.indexOfPaper(target);
    if (index != -1) {
      doc.goToPage(index);
      return;
    }
    final name = target.period;
    showMessage(
      context,
      'This notebook has no page for $name',
      action: SnackBarAction(
        label: 'Add page',
        onPressed: () {
          final current = _current;
          final spec = (
            size: current.size,
            paper: target,
            color: current.paperColor,
            background: null,
          );
          edits.add([spec], after: current);
        },
      ),
    );
  }

  /// Runs [command] on [page] (from the menu or the overview).
  Future<void> run(BuildContext context, PageCommand command, NotebookPage page) async {
    switch (command) {
      case PageCommand.insertAfter:
        edits.add([PageActions.blankAfter(page)], after: page);
      case PageCommand.duplicate:
        edits.duplicate(page);
      case PageCommand.template:
        await _changeTemplate(context, page);
      case PageCommand.saveAsTemplate:
        await _saveAsTemplate(context, page);
      case PageCommand.bookmark:
        edits.setBookmarks([page], on: !page.bookmarked);
      case PageCommand.moveTo:
        await sendPages(context, [page]);
      case PageCommand.delete:
        await _delete(context, page);
    }
  }

  /// Adds [page] as it looks now (paper, background, ink and content) to
  /// My templates.
  Future<void> _saveAsTemplate(BuildContext context, NotebookPage page) async {
    final exporter = NotebookExporter(services);
    try {
      final png = await runWithProgress(
        context,
        'Rendering page',
        () => exporter.png(page, scale: UserTemplates.renderScaleFor(page.size)),
      );
      if (!context.mounted) return;
      final number = doc.pages.indexWhere((p) => p.id == page.id) + 1;
      await UserTemplates.savePng(
        context,
        png,
        size: page.size,
        name: '${notebook().title}, page $number',
      );
    } on Cancelled {
      return;
    } finally {
      await exporter.dispose();
    }
  }

  Future<void> _changeTemplate(BuildContext context, NotebookPage page) =>
      changeTemplateOf(context, [page]);

  /// Asks for a template and applies it to [pages] (or every page, if
  /// chosen) as one step; several get a message with Undo.
  Future<void> changeTemplateOf(BuildContext context, List<NotebookPage> pages) async {
    if (pages.isEmpty) return;
    final choice = await showTemplatePicker(
      context,
      initial: pages.first.template,
      mode: TemplatePickerMode.change,
    );
    if (choice == null) return;
    final targets = choice.allPages ? doc.pages : pages;
    final edit = edits.setTemplate(
      targets,
      choice.template,
      papers: choice.papersForPages(targets.length),
    );
    if (!context.mounted || targets.length < 2) return;
    showMessage(
      context,
      'Template changed on ${targets.length} pages',
      action: SnackBarAction(label: 'Undo', onPressed: () => edits.models.undoEdit(edit)),
    );
  }

  Future<void> _delete(BuildContext context, NotebookPage page) async {
    // As stored: a sync may have deleted pages the view still shows.
    if (actions.pages.length <= 1) {
      showMessage(context, 'A notebook needs at least one page');
      return;
    }
    final number = doc.pages.indexWhere((p) => p.id == page.id) + 1;
    final edit = edits.delete([page]);
    showMessage(
      context,
      'Page $number deleted',
      action: SnackBarAction(label: 'Undo', onPressed: () => edits.models.undoEdit(edit)),
    );
  }

  /// Deletes [pages] as one step with one Undo (the overview's selection).
  Future<void> deleteMany(BuildContext context, List<NotebookPage> pages) async {
    if (pages.isEmpty) return;
    final live = {for (final p in actions.pages) p.id};
    if (live.difference({for (final p in pages) p.id}).isEmpty) {
      showMessage(context, 'A notebook needs at least one page');
      return;
    }
    if (pages.length == 1) return _delete(context, pages.single);
    final edit = edits.delete(pages);
    showMessage(
      context,
      '${pages.length} pages deleted',
      action: SnackBarAction(label: 'Undo', onPressed: () => edits.models.undoEdit(edit)),
    );
  }

  /// Duplicates [pages] (each copy after its page) as one step; several
  /// get a message with Undo.
  Future<void> duplicateMany(BuildContext context, List<NotebookPage> pages) async {
    if (pages.isEmpty) return;
    final edit = edits.duplicateAll(pages);
    if (pages.length < 2) return;
    showMessage(
      context,
      '${pages.length} pages duplicated',
      action: SnackBarAction(label: 'Undo', onPressed: () => edits.models.undoEdit(edit)),
    );
  }

  /// Opens the page overview (on [filter]); shows the page picked there.
  /// [outline] builds its Outline filter.
  Future<void> openOverview(
    BuildContext context, {
    PageBackgrounds? backgrounds,
    Widget Function(BuildContext context, ValueChanged<int> goTo)? outline,
    OverviewFilter filter = OverviewFilter.all,
  }) async {
    final index = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => PageOverview(
          currentPage: doc.currentPage,
          copier: SurfaceCopier(services.strokes, elements: services.elements),
          backgrounds: backgrounds,
          images: services.images,
          changes: doc,
          outline: outline,
          initialFilter: filter,
          handlers: OverviewHandlers(
            load: () => actions.pages,
            command: run,
            move: edits.move,
            bookmarkMany: (pages, {required on}) => edits.setBookmarks(pages, on: on),
            deleteMany: deleteMany,
            duplicateMany: duplicateMany,
            exportMany: exportPages,
            templateMany: changeTemplateOf,
            sendMany: sendPages,
          ),
        ),
      ),
    );
    reload();
    if (index != null && !_disposed) doc.goToPage(index);
  }

  /// Asks which page to show (a number, or a pick from the thumbnail
  /// strip) and shows it.
  Future<void> goToPagePrompt(BuildContext context, {PageBackgrounds? backgrounds}) async {
    final pages = doc.pages;
    final index = await showGoToPage(
      context,
      pages: pages,
      current: doc.currentPage,
      copier: SurfaceCopier(services.strokes, elements: services.elements),
      images: services.images,
      backgrounds: backgrounds,
    );
    if (index == null || _disposed) return;
    // Pages may have changed meanwhile (a sync): go to the page picked.
    final now = doc.pages.indexWhere((p) => p.id == pages[index].id);
    doc.goToPage(now == -1 ? index.clamp(0, doc.pages.length - 1) : now);
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
      file: file,
    );
    switch (result) {
      case RelinkResult.restored:
        backgrounds.retryMissing();
        if (context.mounted) showMessage(context, 'PDF found');
      case RelinkResult.replaced:
        changed = true;
        reload();
        if (context.mounted) showMessage(context, 'PDF relinked');
      case RelinkResult.none:
    }
  }

  /// Inserts the pages of PDF [file] (picked by the user if null) after
  /// the current page.
  Future<void> insertPdf(BuildContext context, {XFile? file}) async {
    final inserted = await insertPdfPagesFlow(
      context,
      notebookId: notebook().id,
      after: _current,
      file: file,
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
