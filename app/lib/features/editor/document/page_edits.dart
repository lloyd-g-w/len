import '../../../data/page_repository.dart';
import '../../../domain/notebook_page.dart';
import '../../../domain/paper.dart';
import '../../../domain/surface_element.dart';
import 'page_actions.dart';
import 'page_models.dart';
import 'page_transfer.dart';

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
  /// undoable and shows the first (unless not to [show]: pages a text box
  /// flowed onto).
  PageEdit added(List<NotebookPage> pages, {bool show = true}) {
    var deleted = <DeletedPage>[];
    return _record(
      () => deleted = actions.deleteAll(pages),
      () => actions.restoreAll(deleted),
      keep: show ? pages.first.id : null,
    );
  }

  /// Shows PDF [to] instead of [from] on the pages drawn on it (page for
  /// page, their notes kept) and adds [extra] pages after [after], as one
  /// step (UX_AUDIT R18-1); undo puts the old PDF back on just those pages.
  PageEdit replacePdf({
    required String from,
    required String to,
    List<PageSpec> extra = const [],
    NotebookPage? after,
  }) {
    final repo = actions.services.pages;
    final id = actions.notebookId;
    final changed = repo.relinkBackground(id, from: from, to: to).toSet();
    final added = extra.isEmpty ? const <NotebookPage>[] : actions.addAll(extra, after: after);
    var deleted = <DeletedPage>[];
    return _record(
      () {
        deleted = actions.deleteAll(added);
        repo.relinkBackground(id, from: to, to: from, only: changed);
      },
      () {
        repo.relinkBackground(id, from: from, to: to, only: changed);
        actions.restoreAll(deleted);
      },
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

  /// Moves or copies [pages] to the notebook [open] returns (one [made]
  /// for them, if so), as one step: see [PageTransfer] (UX_AUDIT R7-9,
  /// R8-1). [changed] runs after each change with the notebook and the
  /// surfaces whose links changed (their open views reload); [kept] after
  /// an undo that kept work done there since.
  PageEdit sendTo(
    List<NotebookPage> pages, {
    required String Function() open,
    bool made = false,
    required bool copy,
    required void Function(String notebookId, List<SurfaceElement> links) changed,
    void Function(String notebookId, TransferKept kept)? kept,
  }) {
    final transfer = PageTransfer(
      actions: actions,
      pages: pages,
      open: open,
      made: made,
      copy: copy,
    );
    void send() {
      transfer.send();
      changed(transfer.to, transfer.links);
    }

    send();
    return _record(
      () {
        final what = transfer.undo();
        changed(transfer.to, transfer.links);
        if (what != null) kept?.call(transfer.to, what);
      },
      send,
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
