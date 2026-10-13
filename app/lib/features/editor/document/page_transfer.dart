import '../../../data/change_mark.dart';
import '../../../data/notebook_duplicator.dart';
import '../../../domain/notebook_page.dart';
import '../../../domain/surface_element.dart';
import '../../../ink/surface_model.dart';
import 'page_actions.dart';

/// What undoing a [PageTransfer] kept rather than took back (UX_AUDIT
/// R8-1): the destination changed after the pages arrived.
enum TransferKept {
  /// The new notebook went to the Trash with the changes made in it.
  trashed,

  /// The copies stay in their notebook with the changes made to them.
  copies,
}

/// One move or copy of pages to another notebook (UX_AUDIT R7-9), done
/// with [send], taken back with [undo] and done again with [send].
///
/// Undo never deletes work done since (R8-1): a notebook made for the
/// pages goes to the Trash with everything in it; copies in an existing
/// notebook are removed only while unchanged, and kept otherwise. Redo
/// reuses copies still there (taking the trashed notebook out of the
/// Trash), so changes made to them stay.
class PageTransfer {
  PageTransfer({
    required this.actions,
    required this.pages,
    required this.open,
    required this.made,
    required this.copy,
  });

  final PageActions actions;
  final List<NotebookPage> pages;

  /// The destination's id; makes it when [made] and not there yet.
  final String Function() open;

  /// Whether [open] makes a new notebook for the pages.
  final bool made;

  /// A copy (the pages stay here) rather than a move.
  final bool copy;

  String? _to;
  CopiedPages? _copied;
  var _deleted = const <DeletedPage>[];
  var _links = const <SurfaceElement>[];

  /// The state of the destination right after the copies were made.
  String _mark = '';

  /// The destination (once sent).
  String get to => _to!;

  /// The links that changed in the last [send] or [undo].
  List<SurfaceElement> get links => _links;

  ChangeMark get _marks => ChangeMark(actions.services.database);

  String _markNow() => made ? _marks.notebook(to) : _marks.pages(_copied!.pages);

  /// Copies the pages there (or brings back the copies an [undo] kept)
  /// and, for a move, deletes them here and points links at the copies.
  /// One transaction.
  void send() {
    final services = actions.services;
    services.database.transaction(() {
      final fresh = !_copiesThere();
      if (fresh) {
        _to = open();
        _copied = services.notebooks.copyPages(actions.notebookId, [
          for (final p in pages) p.id,
        ], to);
      }
      if (!copy) {
        _deleted = actions.deleteAll(pages);
        _links = services.elements.retargetLinks(_copied!.copies, to);
      }
      services.notebooks.touch(to);
      if (fresh) _mark = _markNow();
    });
  }

  /// Whether the copies of a previous [send] are still there to reuse
  /// (taking their notebook out of the Trash if [undo] put it there).
  bool _copiesThere() {
    final copied = _copied, to = _to;
    if (copied == null || to == null) return false;
    final notebooks = actions.services.notebooks;
    final notebook = notebooks.get(to);
    if (notebook == null) return false;
    final pages = actions.services.pages;
    if (copied.pages.any((id) => pages.get(id) == null)) return false;
    if (notebook.isTrashed) notebooks.restore(to);
    return true;
  }

  /// Takes the transfer back: restores the pages here (for a move) and
  /// their links, and takes the copies away unless that would lose work.
  /// Returns what it kept, or null if it took everything back.
  TransferKept? undo() {
    SurfaceModel.flushAll(); // Ink written there a moment ago counts.
    final services = actions.services;
    final changed = _markNow() != _mark;
    return services.database.transaction(() {
      if (!copy) {
        actions.restoreAll(_deleted);
        services.elements.save(_links);
      }
      if (made) {
        final notebook = services.notebooks.get(to);
        if (notebook != null && !notebook.isTrashed) services.notebooks.trash(to);
        return changed ? TransferKept.trashed : null;
      }
      if (changed) return TransferKept.copies;
      services.notebooks.removeCopies(_copied!);
      _copied = null;
      return null;
    });
  }
}
