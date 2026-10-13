import 'package:flutter/material.dart';

import '../../../domain/notebook.dart';
import '../../../domain/notebook_page.dart';
import '../../../domain/surface_element.dart';
import '../../../ink/surface_model.dart';
import '../../../ui/messages.dart';
import '../../documents/overview/notebook_picker.dart';
import '../../library/library_query.dart';
import 'document_commands.dart';

/// Moving and copying pages to another notebook (UX_AUDIT R7-9).
extension PageTransferFlow on DocumentCommands {
  /// Asks which notebook [pages] go to and whether they are moved or
  /// copied there (after its last page), does it as one step of this
  /// notebook's history and says so with Undo.
  Future<void> sendPages(BuildContext context, List<NotebookPage> pages) async {
    if (pages.isEmpty) return;
    final here = notebook();
    final what = pages.length == 1 ? '1 page' : '${pages.length} pages';
    final destination = await pickPageDestination(
      context,
      title: 'Move or copy $what',
      // Every page: a notebook keeps at least one, so only Copy (R8-3).
      noMove: pages.length < actions.pages.length
          ? null
          : 'A notebook keeps at least one page, so '
                '${pages.length == 1 ? 'this one' : 'these'} can only be copied',
      notebooks: _destinations(here),
      caption: _locations(),
      cover: Color(here.coverColor),
    );
    if (destination == null || !context.mounted) return;
    // As stored: a sync may have changed the pages meanwhile.
    final live = {for (final p in actions.pages) p.id};
    final sent = [
      for (final p in pages)
        if (live.contains(p.id)) p,
    ];
    if (sent.isEmpty) return;
    final copy = destination.copy;
    if (!copy && sent.length == live.length) {
      showMessage(context, 'A notebook keeps at least one page'); // Changed meanwhile.
      return;
    }
    final to = destination.notebook;
    SurfaceModel.flushAll(); // Ink drawn a moment ago goes too.
    final edit = edits.sendTo(
      sent,
      open: () => to?.id ?? _create(here, destination.title).id,
      discard: to == null ? services.notebooks.delete : null,
      copy: copy,
      changed: _changed,
    );
    if (!context.mounted) return;
    final count = sent.length == 1 ? '1 page' : '${sent.length} pages';
    showMessage(
      context,
      '${copy ? 'Copied' : 'Moved'} $count to “${destination.title}”',
      action: SnackBarAction(label: 'Undo', onPressed: () => edits.models.undoEdit(edit)),
    );
  }

  /// A new notebook named [title] beside [source], with its paper and
  /// cover, for pages about to be sent there.
  Notebook _create(Notebook source, String title) => services.notebooks.create(
    title: title,
    kind: NotebookKind.paged,
    paper: source.paper.style,
    look: source.paper.look,
    paperColor: source.paperColor,
    coverColor: source.coverColor,
    folderId: source.folderId,
    empty: true,
  );

  /// Pages were sent to (or taken back from) [notebookId] and [links]
  /// changed: their open views reload.
  void _changed(String notebookId, List<SurfaceElement> links) {
    final shared = services.sharedNotebooks;
    shared.peek(notebookId)?.reloadViews();
    for (final surface in {for (final l in links) l.surfaceId}) {
      final owner = services.pages.get(surface)?.notebookId ?? surface; // A canvas is its own.
      shared.peek(owner)?.reloadSurface(surface);
    }
  }

  /// The other paged notebooks, those opened lately first, then the most
  /// recently edited.
  List<Notebook> _destinations(Notebook here) {
    final recent = services.workspace.recent;
    int rank(Notebook n) {
      final i = recent.indexOf(n.id);
      return i == -1 ? recent.length : i;
    }

    return [
      for (final n in services.notebooks.list())
        if (n.kind == NotebookKind.paged && n.id != here.id && !n.isTrashed) n,
    ]..sort((a, b) {
      final byRank = rank(a).compareTo(rank(b));
      return byRank != 0 ? byRank : b.editedAt.compareTo(a.editedAt);
    });
  }

  /// Where a notebook lives, as the library says it: "School › Maths",
  /// or "Library".
  String Function(Notebook) _locations() {
    final folders = {for (final f in services.folders.list()) f.id: f};
    return (n) => LibraryQuery.pathOf(n, folders) ?? 'Library';
  }
}
