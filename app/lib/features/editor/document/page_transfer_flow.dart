import 'package:flutter/material.dart';

import '../../../domain/notebook.dart';
import '../../../domain/notebook_page.dart';
import '../../../ink/surface_model.dart';
import '../../../ui/messages.dart';
import '../../documents/overview/notebook_picker.dart';
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
      notebooks: _destinations(here),
      caption: _locations(),
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
      showMessage(context, 'A notebook needs at least one page: copy them instead');
      return;
    }
    final to = destination.notebook;
    SurfaceModel.flushAll(); // Ink drawn a moment ago goes too.
    final edit = edits.sendTo(
      sent,
      to.id,
      copy: copy,
      changed: () => services.sharedNotebooks.peek(to.id)?.reloadViews(),
    );
    if (!context.mounted) return;
    final count = sent.length == 1 ? '1 page' : '${sent.length} pages';
    showMessage(
      context,
      '${copy ? 'Copied' : 'Moved'} $count to “${to.title}”',
      action: SnackBarAction(label: 'Undo', onPressed: () => edits.models.undoEdit(edit)),
    );
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

  /// Where a notebook lives: its folder's name, or "Library".
  String Function(Notebook) _locations() {
    final names = {for (final f in services.folders.list()) f.id: f.name};
    return (n) => names[n.folderId] ?? 'Library';
  }
}
