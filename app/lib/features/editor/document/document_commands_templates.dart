part of 'document_commands.dart';

/// Templates of a paged notebook's pages: adding pages with one, changing
/// it, saving a page as one.
mixin _DocumentTemplates {
  AppServices get services;
  Notebook Function() get notebook;
  DocumentController get doc;
  PageEdits get edits;
  NotebookPage get _current;

  /// Lets the user choose a template, then adds pages with it after
  /// [after] (default: the current page).
  Future<void> addPageWithTemplate(BuildContext context, {NotebookPage? after}) async {
    final page = after ?? _current;
    final choice = await showTemplatePicker(
      context,
      initial: page.template,
      mode: TemplatePickerMode.addPage,
    );
    if (choice == null) return;
    edits.add([
      for (final paper in choice.papers) specOf(choice.template.copyWith(paper: paper)),
    ], after: page);
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
}
