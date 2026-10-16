import 'dart:async';

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
import '../../documents/pdf/pdf_replace_flow.dart';
import '../../documents/progress_dialog.dart';
import '../../documents/scan/scan_flow.dart';
import '../../documents/template_picker.dart';
import '../../documents/templates/user_templates.dart';
import 'document_controller.dart';
import 'go_to_page_dialog.dart';
import 'page_actions.dart';
import 'page_backgrounds.dart';
import 'page_edits.dart';
import 'page_overview.dart';
import 'page_transfer_flow.dart';

part 'document_commands_files.dart';
part 'document_commands_templates.dart';

/// The editor's page-level commands for a paged notebook, with their UI
/// (pickers, confirmations, undo snack bars).
class DocumentCommands with _DocumentFiles, _DocumentTemplates {
  DocumentCommands({
    required this.services,
    required this.notebook,
    required this.doc,
    this.reloadViews,
  }) : actions = PageActions(services, notebook().id) {
    edits = PageEdits(actions: actions, models: doc.surfaces.models, shown: _shown);
  }

  @override
  final AppServices services;

  /// The open notebook (it may be renamed while open).
  @override
  final Notebook Function() notebook;
  @override
  final DocumentController doc;
  final PageActions actions;

  /// Reloads every open view of the notebook; for undoing page changes
  /// made here (the history is shared) after this editor closed.
  final VoidCallback? reloadViews;

  /// Page changes as steps of the notebook's undo history.
  @override
  late final PageEdits edits;

  /// Fresh pages were added to write on (the editor starts writing).
  VoidCallback? onBlankPage;

  @override
  void _addPages(List<PageSpec> specs, {required NotebookPage after}) {
    edits.add(specs, after: after);
    onBlankPage?.call();
  }

  /// Whether the page structure changed (pages added, moved, …).
  bool changed = false;

  @override
  NotebookPage get _current => doc.pages[doc.currentPage];

  /// Reloads the page list, keeping [keep] (or the current page) in view.
  /// A no-op once the editor closed (e.g. a page-delete snack bar's Undo
  /// pressed later still restores the page, but there is nothing to show).
  void reload({String? keep}) {
    if (_disposed) return;
    var pages = actions.pages;
    // An undo or redo took the last page (the others were deleted
    // elsewhere): a notebook keeps one, as opening it does.
    if (pages.isEmpty) pages = [services.pages.addFreshPage(notebook())];
    doc.setPages(pages, keepPageId: keep);
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
  /// next day, week or month; after a slide, lined paper at its size:
  /// [PageActions.blankAfter]) after it.
  void addPage() => _addPages([actions.blankPageAfter(_current)], after: _current);

  /// Adds a page like page [index] after it (the zoom window writing on
  /// past the last page), and shows it.
  void addPageAfter(int index) {
    final page = doc.pages[index];
    _addPages([actions.blankPageAfter(page)], after: page);
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
          _addPages([spec], after: current);
        },
      ),
    );
  }

  /// Runs [command] on [page] (from the menu or the overview).
  Future<void> run(BuildContext context, PageCommand command, NotebookPage page) async {
    switch (command) {
      case PageCommand.insertAfter:
        _addPages([actions.blankPageAfter(page)], after: page);
      case PageCommand.insertWithTemplate:
        await addPageWithTemplate(context, after: page);
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
      case PageCommand.replacePdf:
        await replacePdf(context, page);
    }
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
}
