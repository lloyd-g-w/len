part of 'library_actions.dart';

/// The library's folder flows: create, edit, move (also by dragging),
/// delete.
mixin _FolderActions {
  LibraryController get controller;

  void move(BuildContext context, List<String> ids, String? folderId);
  String _folderName(String? id);
  void _toast(BuildContext context, String message);
  void _undoable(BuildContext context, String message, VoidCallback undo);

  Future<void> createFolder(BuildContext context) async {
    final details = await showFolderDialog(context, title: 'New folder', confirmLabel: 'Create');
    if (details == null) return;
    // A search or another section hides it: say where it went.
    final hidden = controller.isSearching || controller.section != LibrarySection.library;
    final folder = controller.createFolder(details.name, color: details.color);
    if (hidden && context.mounted) {
      _toast(context, 'Created “${folder.name}” in “${_folderName(folder.parentId)}”');
    }
  }

  /// Handles a dragged item dropped on folder [folderId] (null = root):
  /// moves it, says where and offers Undo, as the Move dialog does.
  void drop(BuildContext context, LibraryDragItem item, String? folderId) {
    if (!item.isFolder) {
      final from = controller.services.notebooks.get(item.id)?.folderId;
      if (from != folderId) move(context, [item.id], folderId);
      return;
    }
    final folder = controller.folderById(item.id);
    if (folder == null) return;
    final from = controller.parentOf(folder);
    if (from == folderId) return;
    if (!controller.moveFolder(item.id, folderId)) {
      _toast(context, 'A folder can’t be moved into itself');
      return;
    }
    _undoable(
      context,
      'Moved “${folder.name}” to “${_folderName(folderId)}”',
      () => controller.moveFolder(item.id, from),
    );
  }

  /// Whether [item] may be dropped into [folderId].
  bool canDrop(LibraryDragItem item, String? folderId) =>
      !item.isFolder ||
      (item.id != folderId && controller.services.folders.canMove(item.id, folderId));

  Future<void> onFolderAction(BuildContext context, Folder folder, FolderAction action) async {
    switch (action) {
      case FolderAction.rename:
        final details = await showFolderDialog(
          context,
          title: 'Rename folder',
          confirmLabel: 'Save',
          initialName: folder.name,
          initialColor: folder.color,
        );
        final current = controller.folderById(folder.id);
        if (details == null || current == null || !context.mounted) return;
        if (details.name == current.name && details.color == current.color) return;
        controller.updateFolder(current.copyWith(name: details.name, color: details.color));
        _undoable(
          context,
          details.name == current.name ? 'Folder changed' : 'Renamed to “${details.name}”',
          () {
            final now = controller.folderById(folder.id);
            if (now != null) {
              controller.updateFolder(now.copyWith(name: current.name, color: current.color));
            }
          },
        );
      case FolderAction.move:
        final target = await showMoveDialog(
          context,
          controller: controller,
          title: 'Move “${folder.name}”',
          currentFolderId: controller.parentOf(folder),
          movingFolderId: folder.id,
        );
        if (target != null && context.mounted) {
          drop(context, LibraryDragItem.folder(folder.id), target.folderId);
        }
      case FolderAction.export:
        await exportNotebooks(context, controller.notebooksIn(folder.id), folder: folder);
      case FolderAction.delete:
        deleteFolder(context, folder);
    }
  }

  /// Deletes [folder] with its subfolders (their notebooks go to the
  /// trash) without asking, says what went and offers Undo, as trashing a
  /// notebook does.
  void deleteFolder(BuildContext context, Folder folder) {
    final deletion = controller.deleteFolder(folder.id);
    final folders = max(0, deletion.folders.length - 1); // Its subfolders.
    final notebooks = deletion.notebookIds.length;
    final parts = [
      if (folders > 0) LibraryActions.countLabel(folders, 'subfolder'),
      if (notebooks > 0) LibraryActions.countLabel(notebooks, 'notebook'),
    ];
    final what = switch ((folders, notebooks)) {
      (0, 0) => '',
      (_, 0) => ' with ${parts.single}',
      (0, _) => ', ${parts.single} to the trash',
      _ => ', ${parts.join(' and ')} to the trash',
    };
    _undoable(
      context,
      '“${folder.name}” deleted$what',
      () => controller.undoDeleteFolder(deletion),
    );
  }
}
