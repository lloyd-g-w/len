import '../../../app_services.dart';
import '../../../data/page_repository.dart';
import '../../../data/surface_copier.dart';
import '../../../domain/notebook_page.dart';
import '../../../domain/paper.dart';
import '../../../domain/stroke.dart';
import '../../../domain/surface_element.dart';

/// A deleted page and its content, kept so the deletion can be undone.
class DeletedPage {
  const DeletedPage(this.page, this.strokes, [this.elements = const []]);

  final NotebookPage page;
  final List<Stroke> strokes;
  final List<SurfaceElement> elements;
}

/// Page management for one notebook: insert, duplicate, delete (with
/// undo), reorder, templates and bookmarks. All changes are synced edits.
class PageActions {
  PageActions(this.services, this.notebookId)
    : _copier = SurfaceCopier(services.strokes, elements: services.elements);

  final AppServices services;
  final String notebookId;
  final SurfaceCopier _copier;

  /// Pages in order.
  List<NotebookPage> get pages => services.pages.pagesOf(notebookId);

  /// Adds a page after [after] (or before [before]; at the end if both are
  /// null).
  NotebookPage add(PageSpec spec, {NotebookPage? after, NotebookPage? before}) =>
      services.pages.insertPages(notebookId, [spec], after: after, before: before).single;

  /// A blank page with [page]'s paper and exact size (also for PDF pages).
  static PageSpec blankLike(NotebookPage page) =>
      (size: page.size, paper: page.paper, color: page.paperColor, background: null);

  /// Inserts a copy of [page] (paper, background, ink and text) right after it.
  NotebookPage duplicate(NotebookPage page) {
    return services.database.transaction(() {
      final copy = services.pages.insertPages(notebookId, [
        (size: page.size, paper: page.paper, color: page.paperColor, background: page.background),
      ], after: page).single;
      _copier.copy(from: page.id, to: copy.id);
      return copy;
    });
  }

  /// Deletes [page] and its content. Keep the result to [restore] it.
  DeletedPage delete(NotebookPage page) {
    return services.database.transaction(() {
      final strokes = _copier.loadAll(page.id);
      final elements = _copier.loadAllElements(page.id);
      services.strokes.deleteSurfaces([page.id]);
      services.elements.deleteSurfaces([page.id]);
      services.pages.delete(page.id);
      return DeletedPage(page, strokes, elements);
    });
  }

  /// Deletes [targets] and their content in one transaction. Keep the
  /// result to [restoreAll] them.
  List<DeletedPage> deleteAll(List<NotebookPage> targets) =>
      services.database.transaction(() => [for (final page in targets) delete(page)]);

  /// Undoes [delete].
  void restore(DeletedPage deleted) => restoreAll([deleted]);

  /// Undoes [deleteAll] (or several [delete]s) in one transaction.
  void restoreAll(List<DeletedPage> deleted) {
    services.database.transaction(() {
      for (final d in deleted) {
        services.pages.restore(d.page.id);
        services.strokes.save(d.strokes);
        if (d.elements.isNotEmpty) services.elements.save(d.elements);
      }
    });
  }

  /// Moves [page] to position [toIndex].
  void move(NotebookPage page, int toIndex) => services.pages.move(page, toIndex);

  /// Changes the template of [targets] (style and colour; size stays).
  void setTemplate(Iterable<NotebookPage> targets, PageTemplate template) => services.pages
      .setPaper([for (final p in targets) p.id], style: template.style, color: template.color);

  void toggleBookmark(NotebookPage page) => services.pages.setBookmarked(page.id, !page.bookmarked);
}
