import 'package:flutter/material.dart';

import '../../../app_services.dart';
import '../../../data/page_repository.dart';
import '../../../data/surface_copier.dart';
import '../../../domain/notebook.dart';
import '../../../domain/notebook_page.dart';
import '../../../ui/text_prompt.dart';
import '../../documents/export/export_flow.dart';
import '../../documents/pdf/pdf_import_flow.dart';
import '../../documents/progress_dialog.dart';
import '../../documents/template_picker.dart';
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

  /// Adds a page like the current one (same paper and size) after it.
  void addPage() => _changedAndShow(actions.add(PageActions.blankLike(_current), after: _current));

  /// Lets the user choose a template, then adds a page after the current.
  Future<void> addPageWithTemplate(BuildContext context) async {
    final choice = await showTemplatePicker(
      context,
      initial: _current.template,
      mode: TemplatePickerMode.addPage,
    );
    if (choice == null) return;
    _changedAndShow(actions.add(specOf(choice.template), after: _current));
  }

  /// Runs [command] on [page] (from the menu or the overview).
  Future<void> run(BuildContext context, PageCommand command, NotebookPage page) async {
    switch (command) {
      case PageCommand.insertBefore:
        _changedAndShow(actions.add(PageActions.blankLike(page), before: page));
      case PageCommand.insertAfter:
        _changedAndShow(actions.add(PageActions.blankLike(page), after: page));
      case PageCommand.duplicate:
        _changedAndShow(actions.duplicate(page));
      case PageCommand.template:
        await _changeTemplate(context, page);
      case PageCommand.bookmark:
        actions.toggleBookmark(page);
        changed = true;
        reload();
      case PageCommand.delete:
        _delete(context, page);
    }
  }

  Future<void> _changeTemplate(BuildContext context, NotebookPage page) async {
    final choice = await showTemplatePicker(
      context,
      initial: page.template,
      mode: TemplatePickerMode.change,
    );
    if (choice == null) return;
    actions.setTemplate(choice.allPages ? doc.pages : [page], choice.template);
    changed = true;
    reload();
  }

  void _delete(BuildContext context, NotebookPage page) {
    if (doc.pages.length == 1) {
      showMessage(context, 'A notebook needs at least one page.');
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

  /// Opens the page overview; shows the page picked there.
  Future<void> openOverview(BuildContext context, {PageBackgrounds? backgrounds}) async {
    final index = await Navigator.of(context).push<int>(
      MaterialPageRoute(
        builder: (_) => PageOverview(
          currentPage: doc.currentPage,
          copier: SurfaceCopier(services.strokes, elements: services.elements),
          backgrounds: backgrounds,
          changes: doc,
          handlers: OverviewHandlers(
            load: () => actions.pages,
            command: run,
            move: (page, to) {
              actions.move(page, to);
              changed = true;
            },
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

  /// Inserts the pages of a PDF after the current page.
  Future<void> insertPdf(BuildContext context) async {
    final inserted = await insertPdfPagesFlow(context, notebookId: notebook().id, after: _current);
    if (inserted == null || inserted.isEmpty) return;
    _changedAndShow(inserted.first);
  }

  Future<void> export(BuildContext context, ExportKind kind) =>
      exportFlow(context, kind: kind, notebook: notebook(), pages: doc.pages, page: _current);
}
