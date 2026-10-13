import 'package:flutter/foundation.dart';

import '../../../data/page_repository.dart';
import '../../../domain/notebook_page.dart';
import '../../../domain/paper.dart';
import 'page_actions.dart';
import 'page_models.dart';

/// Page-level changes made as steps of the notebook's undo history
/// ([PageModels]): templates, page order, bookmarks, pages added and
/// deleted. Ctrl+Z and the undo button take them back like ink.
///
/// Each method makes the change and returns its [PageEdit] (e.g. for a
/// snack bar's Undo, see [PageModels.undoEdit]). [shown] runs after the
/// change and after each undo and redo, with a page to keep in view.
class PageEdits {
  PageEdits({required this.actions, required this.models, required this.shown});

  final PageActions actions;
  final PageModels models;
  final void Function({String? keep}) shown;

  /// Records a change just made; [keep] is the page to show after it (and
  /// its redo), [keepOnUndo] the one after its undo.
  PageEdit _record(void Function() undo, void Function() redo, {String? keep, String? keepOnUndo}) {
    final edit = PageEdit(
      undo: () {
        undo();
        shown(keep: keepOnUndo);
      },
      redo: () {
        redo();
        shown(keep: keep);
      },
    );
    models.record(edit);
    shown(keep: keep);
    return edit;
  }

  /// Adds [specs] after [after] (at the end if null); undo deletes them.
  List<NotebookPage> add(List<PageSpec> specs, {NotebookPage? after}) {
    final pages = actions.addAll(specs, after: after);
    added(pages);
    return pages;
  }

  /// Inserts a copy of [page] after it; undo deletes the copy.
  PageEdit duplicate(NotebookPage page) => duplicateAll([page]);

  /// Inserts a copy of each of [pages] (not empty) right after it, as one
  /// step; undo deletes the copies.
  PageEdit duplicateAll(List<NotebookPage> pages) {
    // Last first, so each copy lands after its page.
    final copies = [for (final p in pages.reversed) actions.duplicate(p)].reversed.toList();
    return added(copies);
  }

  /// Makes adding [pages] (already added elsewhere, e.g. from a PDF)
  /// undoable and shows the first.
  PageEdit added(List<NotebookPage> pages) {
    var deleted = <DeletedPage>[];
    return _record(
      () => deleted = actions.deleteAll(pages),
      () => actions.restoreAll(deleted),
      keep: pages.first.id,
    );
  }

  /// Deletes [pages] and their content; undo restores them.
  PageEdit delete(List<NotebookPage> pages) {
    var deleted = actions.deleteAll(pages);
    return _record(
      () => actions.restoreAll(deleted),
      () => deleted = actions.deleteAll(pages),
      keepOnUndo: pages.first.id,
    );
  }

  /// Copies [pages] to the end of notebook [to] and, unless [copy], deletes
  /// them here (a move), as one step (UX_AUDIT R7-9); undo takes the copies
  /// back and restores the pages. [changed] runs after each change to [to]
  /// (its open views reload).
  PageEdit sendTo(
    List<NotebookPage> pages,
    String to, {
    required bool copy,
    required VoidCallback changed,
  }) {
    final notebooks = actions.services.notebooks;
    final ids = [for (final p in pages) p.id];
    var copied = notebooks.copyPages(actions.notebookId, ids, to);
    var deleted = copy ? const <DeletedPage>[] : actions.deleteAll(pages);
    notebooks.touch(to);
    changed();
    return _record(
      () {
        notebooks.removeCopies(copied);
        if (!copy) actions.restoreAll(deleted);
        changed();
      },
      () {
        copied = notebooks.copyPages(actions.notebookId, ids, to);
        if (!copy) deleted = actions.deleteAll(pages);
        changed();
      },
      keepOnUndo: copy ? null : pages.first.id,
    );
  }

  /// Gives [targets] [template] (page i gets `papers[i]` if given).
  PageEdit setTemplate(List<NotebookPage> targets, PageTemplate template, {List<Paper>? papers}) {
    final before = [for (final p in targets) (id: p.id, paper: p.paper, color: p.paperColor)];
    void apply() => actions.setTemplate(targets, template, papers: papers);
    apply();
    return _record(() => actions.setPapers(before), apply);
  }

  /// Moves [page] to index [toIndex].
  void move(NotebookPage page, int toIndex) {
    final from = actions.pages.indexWhere((p) => p.id == page.id);
    if (from == -1 || from == toIndex) return;
    actions.move(page, toIndex);
    _record(() => actions.move(page, from), () => actions.move(page, toIndex));
  }

  /// Bookmarks [pages] ([on]) or removes their bookmarks, as one step.
  /// Goes by what is stored ([pages] may be stale copies, e.g. changed in
  /// another view meanwhile).
  void setBookmarks(List<NotebookPage> pages, {required bool on}) {
    final changing = [
      for (final p in pages)
        if (actions.services.pages.get(p.id) case final stored? when stored.bookmarked != on) p,
    ];
    if (changing.isEmpty) return;
    void apply(bool value) => actions.setBookmarks(changing, value);
    apply(on);
    _record(() => apply(!on), () => apply(on));
  }
}
