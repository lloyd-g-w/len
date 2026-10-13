import '../../../app_services.dart';
import '../../../data/page_repository.dart';
import '../../../data/surface_copier.dart';
import '../../../domain/notebook_page.dart';
import '../../../domain/paper.dart';
import '../../../domain/stroke.dart';
import '../../../domain/surface_element.dart';
import '../../../ink/surface_model.dart';

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

  /// Adds a page after [after] (at the end if null).
  NotebookPage add(PageSpec spec, {NotebookPage? after}) =>
      services.pages.insertPages(notebookId, [spec], after: after).single;

  /// Adds pages in order after [after] (at the end if null).
  List<NotebookPage> addAll(List<PageSpec> specs, {NotebookPage? after}) =>
      services.pages.insertPages(notebookId, specs, after: after);

  /// A blank page to add after [page]: its paper and exact size (also for
  /// PDF pages); a planner page is for the following period.
  static PageSpec blankAfter(NotebookPage page) =>
      (size: page.size, paper: page.paper.next, color: page.paperColor, background: null);

  /// Inserts a copy of [page] (paper, background, ink and text) right after it.
  NotebookPage duplicate(NotebookPage page) {
    SurfaceModel.flushAll();
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
    SurfaceModel.flushAll();
    return services.database.transaction(() {
      final strokes = _copier.loadAll(page.id);
      final elements = _copier.loadAllElements(page.id);
      services.notebooks.deletePage(page.id);
      return DeletedPage(page, strokes, elements);
    });
  }

  /// Deletes [targets] and their content in one transaction. Keep the
  /// result to [restoreAll] them.
  List<DeletedPage> deleteAll(List<NotebookPage> targets) =>
      services.database.transaction(() => [for (final page in targets) delete(page)]);

  /// Undoes [delete].
  void restore(DeletedPage deleted) => restoreAll([deleted]);

  /// Undoes [deleteAll] (or several [delete]s) in one transaction; not
  /// once the notebook itself is deleted (its snack bar may outlive it).
  void restoreAll(List<DeletedPage> deleted) {
    if (services.notebooks.get(notebookId) == null) return;
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

  /// Changes the template of [targets] (paper and colour; size stays):
  /// page i gets `papers[i]` (default: [template]'s paper for all).
  void setTemplate(List<NotebookPage> targets, PageTemplate template, {List<Paper>? papers}) =>
      services.database.transaction(() {
        for (var i = 0; i < targets.length; i++) {
          services.pages.setPaper(
            [targets[i].id],
            paper: papers?[i] ?? template.paper,
            color: template.color,
          );
        }
      });

  /// Gives each page back its paper and colour (undoing [setTemplate]);
  /// pages deleted meanwhile stay deleted.
  void setPapers(List<({String id, Paper paper, PaperColor color})> papers) {
    services.database.transaction(() {
      for (final p in papers) {
        if (services.pages.get(p.id) == null) continue;
        services.pages.setPaper([p.id], paper: p.paper, color: p.color);
      }
    });
  }

  /// Bookmarks [targets] or removes their bookmarks.
  void setBookmarks(List<NotebookPage> targets, bool bookmarked) {
    services.database.transaction(() {
      for (final page in targets) {
        services.pages.setBookmarked(page.id, bookmarked);
      }
    });
  }
}
