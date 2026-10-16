part of 'library_actions.dart';

/// The library's notebook flows: the notebook menu's commands, favourites,
/// moving, the trash.
mixin _NotebookActions {
  LibraryController get controller;
  CoverLocator get covers;

  Future<void> openNotebook(
    BuildContext context,
    Notebook notebook, {
    editor.NotebookOpenOrigin? from,
  });
  void startSelection(BuildContext context, [String? id]);
  String _folderName(String? id);
  void _undoable(BuildContext context, String message, VoidCallback undo);

  Future<void> trash(BuildContext context, Notebook notebook) async {
    // Its recording is stopped and saved, and goes to the trash with it.
    final recording = controller.services.sharedNotebooks.recordsUnattended(notebook.id);
    final trashed = controller.trashNotebooks([notebook.id]);
    if (trashed.isEmpty) return; // Gone or trashed meanwhile (by sync).
    _undoable(
      context,
      recording
          ? 'Recording saved and “${notebook.title}” moved to the trash'
          : '“${notebook.title}” moved to the trash',
      () => controller.restoreNotebooks(trashed),
    );
  }

  Future<void> onNotebookAction(
    BuildContext context,
    Notebook notebook,
    NotebookAction action,
  ) async {
    switch (action) {
      case NotebookAction.rename:
        final title = await showTextPrompt(
          context,
          title: 'Rename notebook',
          label: 'Name',
          initialValue: notebook.title,
          confirmLabel: 'Rename',
        );
        if (title == null || title.isEmpty) return;
        // Re-read: it may have changed (or gone) while the dialog was open.
        final current = controller.services.notebooks.get(notebook.id);
        if (current == null || title == current.title || !context.mounted) return;
        controller.updateNotebook(current.copyWith(title: title));
        _undoable(
          context,
          'Renamed to “$title”',
          () => _editNotebook(notebook.id, (n) => n.copyWith(title: current.title)),
        );
      case NotebookAction.favorite:
        setFavorite(context, [notebook.id], !notebook.favorite);
      case NotebookAction.cover:
        // Applies on tap; "Cover changed" offers Undo once it closes.
        await changeCover(context, controller, notebook);
      case NotebookAction.duplicate:
        final copy = controller.duplicate(notebook.id);
        if (copy == null || !context.mounted) return;
        _undoable(
          context,
          'Duplicated as “${copy.title}”',
          // A fresh copy holds nothing of the user's: no trip to the trash.
          () => controller.deleteForever([copy.id]),
        );
      case NotebookAction.move:
        final target = await showMoveDialog(
          context,
          controller: controller,
          title: 'Move “${notebook.title}”',
          currentFolderId: notebook.folderId,
        );
        if (target != null && context.mounted) move(context, [notebook.id], target.folderId);
      case NotebookAction.export:
        await exportNotebooks(context, [notebook]);
      case NotebookAction.print:
        await printNotebook(context, notebook);
      case NotebookAction.select:
        startSelection(context, notebook.id);
      case NotebookAction.trash:
        await trash(context, notebook);
      case NotebookAction.restore:
        restore(context, [notebook.id]);
      case NotebookAction.deleteForever:
        final ok = await confirmAction(
          context,
          title: 'Delete “${notebook.title}” forever?',
          message: 'It will be removed from all synced devices. This can’t be undone.',
          confirmLabel: 'Delete forever',
          destructive: true,
        );
        if (ok) controller.deleteForever([notebook.id]);
    }
  }

  /// Stars notebooks [ids] ([value]) or unstars them, says so and offers
  /// Undo (each goes back to how it was).
  void setFavorite(BuildContext context, List<String> ids, bool value) {
    final changed = controller.setFavorites(ids, value);
    if (changed.isEmpty) return;
    final notebook = changed.length == 1 ? controller.services.notebooks.get(changed.single) : null;
    final what = notebook != null
        ? '“${notebook.title}”'
        : LibraryActions.countLabel(changed.length, 'notebook');
    _undoable(
      context,
      value ? 'Added $what to favourites' : 'Removed $what from favourites',
      () => controller.setFavorites(changed, !value),
    );
  }

  /// Applies [edit] to notebook [id] as it is now (for Undo: other fields
  /// may have changed since).
  void _editNotebook(String id, Notebook Function(Notebook n) edit) {
    final now = controller.services.notebooks.get(id);
    if (now != null) controller.updateNotebook(edit(now));
  }

  /// Takes notebooks [ids] out of the trash and says where they went.
  void restore(BuildContext context, List<String> ids) {
    final restored = controller.restoreNotebooks(ids);
    if (restored.isEmpty) return;
    final folders = {for (final n in restored) n.folderId};
    final where = folders.length == 1 ? '“${_folderName(folders.single)}”' : 'their folders';
    final what = restored.length == 1
        ? '“${restored.single.title}”'
        : LibraryActions.countLabel(restored.length, 'notebook');
    showMessage(context, 'Restored $what to $where');
  }

  /// Moves notebooks [ids] into [folderId] (null = the library root), says
  /// so and offers Undo.
  void move(BuildContext context, List<String> ids, String? folderId) {
    final from = controller.moveNotebooks(ids, folderId);
    if (from.isEmpty) return;
    final notebook = from.length == 1 ? controller.services.notebooks.get(from.keys.single) : null;
    final what = notebook != null
        ? '“${notebook.title}”'
        : LibraryActions.countLabel(from.length, 'notebook');
    _undoable(context, 'Moved $what to “${_folderName(folderId)}”', () {
      // Each back where it was: one batch per folder.
      final byFolder = <String?, List<String>>{};
      for (final MapEntry(key: id, value: folder) in from.entries) {
        (byFolder[folder] ??= []).add(id);
      }
      for (final MapEntry(key: folder, value: ids) in byFolder.entries) {
        controller.moveNotebooks(ids, folder);
      }
    });
  }

  Future<void> emptyTrash(BuildContext context) async {
    final count = controller.trash.length;
    if (count == 0) return;
    final ok = await confirmAction(
      context,
      title: 'Empty trash?',
      message:
          '$count ${count == 1 ? 'notebook' : 'notebooks'} will be deleted forever '
          'on all synced devices.',
      confirmLabel: 'Empty trash',
      destructive: true,
    );
    if (ok) controller.emptyTrash();
  }
}
