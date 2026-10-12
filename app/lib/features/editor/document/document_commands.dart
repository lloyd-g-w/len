import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../data/page_repository.dart';
import '../../../data/surface_copier.dart';
import '../../../domain/notebook.dart';
import '../../../domain/notebook_page.dart';
import '../../../domain/paper.dart';
import '../../../ui/text_prompt.dart';
import '../../documents/export/export_flow.dart';
import '../../documents/export/notebook_exporter.dart';
import '../../documents/pdf/pdf_import_flow.dart';
import '../../documents/progress_dialog.dart';
import '../../documents/template_picker.dart';
import '../../documents/templates/user_templates.dart';
import 'document_controller.dart';
import 'page_actions.dart';
import 'page_backgrounds.dart';
import 'page_overview.dart';

/// The editor's page-level commands for a paged notebook, with their UI
/// (pickers, confirmations, undo snack bars).
class DocumentCommands {
  DocumentCommands({required this.services, required this.notebook, required this.doc})
    : actions = PageActions(services, notebook().id);

  final AppServices services;

  /// The open notebook (it may be renamed while open).
  final Notebook Function() notebook;
  final DocumentController doc;
  final PageActions actions;

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

  void _changedAndShow(NotebookPage page) {
    changed = true;
    if (_disposed) return;
    reload(keep: page.id);
    doc.goToPage(doc.pages.indexWhere((p) => p.id == page.id));
  }

  /// Adds a page like the current one (same paper and size; a planner's
  /// next day, week or month) after it.
  void addPage() => _changedAndShow(actions.add(PageActions.blankAfter(_current), after: _current));

  /// Lets the user choose a template, then adds a page after the current.
  Future<void> addPageWithTemplate(BuildContext context) async {
    final choice = await showTemplatePicker(
      context,
      initial: _current.template,
      mode: TemplatePickerMode.addPage,
    );
    if (choice == null) return;
    final added = actions.addAll([
      for (final paper in choice.papers) specOf(choice.template.copyWith(paper: paper)),
    ], after: _current);
    _changedAndShow(added.first);
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
          _changedAndShow(actions.add(spec, after: current));
        },
      ),
    );
  }

  /// Runs [command] on [page] (from the menu or the overview).
  Future<void> run(BuildContext context, PageCommand command, NotebookPage page) async {
    switch (command) {
      case PageCommand.insertAfter:
        _changedAndShow(actions.add(PageActions.blankAfter(page), after: page));
      case PageCommand.duplicate:
        _changedAndShow(actions.duplicate(page));
      case PageCommand.template:
        await _changeTemplate(context, page);
      case PageCommand.saveAsTemplate:
        await _saveAsTemplate(context, page);
      case PageCommand.bookmark:
        actions.toggleBookmark(page);
        changed = true;
        reload();
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
    } finally {
      await exporter.dispose();
    }
  }

  Future<void> _changeTemplate(BuildContext context, NotebookPage page) async {
    final choice = await showTemplatePicker(
      context,
      initial: page.template,
      mode: TemplatePickerMode.change,
    );
    if (choice == null) return;
    final targets = choice.allPages ? doc.pages : [page];
    actions.setTemplate(targets, choice.template, papers: choice.papersForPages(targets.length));
    changed = true;
    reload();
  }

  Future<void> _delete(BuildContext context, NotebookPage page) async {
    if (doc.pages.length == 1) {
      showMessage(context, 'A notebook needs at least one page');
      return;
    }
    final number = doc.pages.indexWhere((p) => p.id == page.id) + 1;
    final deleted = actions.delete(page);
    changed = true;
    reload();
    showMessage(
      context,
      'Page $number deleted',
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () {
          actions.restore(deleted);
          reload(keep: page.id);
        },
      ),
    );
  }

  /// Deletes [pages] as one step with one Undo (the overview's selection).
  Future<void> deleteMany(BuildContext context, List<NotebookPage> pages) async {
    if (pages.isEmpty) return;
    if (pages.length >= doc.pages.length) {
      showMessage(context, 'A notebook needs at least one page');
      return;
    }
    if (pages.length == 1) return _delete(context, pages.single);
    final deleted = actions.deleteAll(pages);
    changed = true;
    reload();
    showMessage(
      context,
      '${pages.length} pages deleted',
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () {
          actions.restoreAll(deleted);
          reload();
        },
      ),
    );
  }

  /// Opens the page overview; shows the page picked there.
  Future<void> openOverview(BuildContext context, {PageBackgrounds? backgrounds}) async {
    final index = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => PageOverview(
          currentPage: doc.currentPage,
          copier: SurfaceCopier(services.strokes, elements: services.elements),
          backgrounds: backgrounds,
          images: services.images,
          changes: doc,
          handlers: OverviewHandlers(
            load: () => actions.pages,
            command: run,
            move: (page, to) {
              actions.move(page, to);
              changed = true;
            },
            deleteMany: deleteMany,
          ),
        ),
      ),
    );
    reload();
    if (index != null && !_disposed) doc.goToPage(index);
  }

  /// Asks for a page number and shows that page.
  Future<void> goToPagePrompt(BuildContext context) async {
    final text = await showTextPrompt(
      context,
      title: 'Go to page (1–${doc.pages.length})',
      initialValue: '${doc.currentPage + 1}',
      confirmLabel: 'Go',
    );
    final number = int.tryParse(text ?? '');
    if (number != null && !_disposed) doc.goToPage(number.clamp(1, doc.pages.length) - 1);
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
    _changedAndShow(inserted.first);
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
