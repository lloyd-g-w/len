import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_services.dart';
import '../../domain/folder.dart';
import '../../domain/notebook.dart';
import '../../domain/paper.dart';
import '../../ui/messages.dart';
import '../../ui/text_prompt.dart';
import '../documents/pdf/pdf_import_flow.dart';
import '../editor/tabs/editor_workspace.dart' as editor;
import 'cover_locator.dart';
import 'library_controller.dart';
import 'library_dialogs.dart';
import 'library_drag.dart';
import 'library_menus.dart';
import 'new_notebook_sheet.dart';
import 'selection/library_selection.dart';
import 'thumbnails/thumbnail_cache.dart';

/// User-facing flows of the library (dialogs, confirmations, navigation)
/// on top of [LibraryController]. Widgets pass their own [BuildContext].
class LibraryActions {
  LibraryActions({required this.controller, required this.thumbnails, LibrarySelection? selection})
    : selection = selection ?? LibrarySelection();

  final LibraryController controller;
  final ThumbnailCache thumbnails;

  /// Notebooks picked in selection mode.
  final LibrarySelection selection;

  /// Covers on screen, which notebooks open out of.
  final CoverLocator covers = CoverLocator();

  /// Opens [notebook] in the editor (out of its cover with [from]), and
  /// refreshes the covers of everything visited when the editor closes.
  Future<void> openNotebook(
    BuildContext context,
    Notebook notebook, {
    editor.NotebookOpenOrigin? from,
  }) async {
    if (notebook.isTrashed) {
      from?.dispose?.call();
      final action = await showContextMenuAt(context, items: notebookMenuItems(notebook));
      if (action != null && context.mounted) await onNotebookAction(context, notebook, action);
      return;
    }
    final tabs = AppScope.read(context).openNotebooks;
    await editor.openNotebook(context, notebook, from: from);
    thumbnails.invalidate([...tabs.takeVisited(), notebook.id]);
    controller.reload();
  }

  /// A click on notebook [id] with Ctrl / ⌘ (toggles it in the selection)
  /// or Shift (selects the range from the last one toggled), as on a
  /// desktop; false without those keys.
  bool selectWithModifiers(String id) {
    final keys = HardwareKeyboard.instance;
    if (keys.isShiftPressed) {
      selection.extendTo(id, [for (final n in controller.visibleNotebooks) n.id]);
      return true;
    }
    if (keys.isControlPressed || keys.isMetaPressed) {
      selection.toggle(id);
      return true;
    }
    return false;
  }

  /// Enters selection mode (with [id] selected). A message still showing
  /// goes: the selection bar takes its place.
  void startSelection(BuildContext context, [String? id]) {
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    selection.start(id);
  }

  /// Opens the new-notebook sheet (starting as a [kind]) and then the new
  /// notebook.
  Future<void> createNotebook(
    BuildContext context, {
    NotebookKind kind = NotebookKind.paged,
  }) async {
    final request = await NewNotebookSheet.show(context, kind: kind);
    if (request == null || !context.mounted) return;
    final style = request.template.style;
    if (style != PaperStyle.image) controller.services.preferences.notePaperUsed(style.name);
    final notebook = controller.createNotebook(
      title: request.title,
      kind: request.kind,
      paper: request.paper,
      look: request.template.paper.look,
      paperColor: request.template.color,
      coverColor: request.coverColor,
      firstPage: request.template,
      papers: request.papers,
    );
    await openNotebook(context, notebook);
  }

  /// Creates a notebook from a PDF the user picks, files it like a new
  /// notebook and opens it.
  Future<void> importPdf(BuildContext context) async {
    final imported = await importPdfFlow(context);
    if (imported == null || !context.mounted) return;
    final notebook = controller.adoptNotebook(imported);
    await openNotebook(context, notebook);
  }

  Future<void> createFolder(BuildContext context) async {
    final details = await showFolderDialog(context, title: 'New folder', confirmLabel: 'Create');
    if (details == null) return;
    controller.createFolder(details.name, color: details.color);
  }

  /// Handles a dragged item dropped on folder [folderId] (null = root).
  void drop(BuildContext context, LibraryDragItem item, String? folderId) {
    if (!item.isFolder) {
      controller.moveNotebook(item.id, folderId);
      return;
    }
    if (!controller.moveFolder(item.id, folderId)) {
      _toast(context, 'A folder can’t be moved into itself.');
    }
  }

  /// Whether [item] may be dropped into [folderId].
  bool canDrop(LibraryDragItem item, String? folderId) =>
      !item.isFolder ||
      (item.id != folderId && controller.services.folders.canMove(item.id, folderId));

  Future<void> trash(BuildContext context, Notebook notebook) async {
    controller.trashNotebook(notebook.id);
    showMessage(
      context,
      '“${notebook.title}” moved to the trash',
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () => controller.restoreNotebook(notebook.id),
      ),
    );
  }

  Future<void> onNotebookAction(
    BuildContext context,
    Notebook notebook,
    NotebookAction action,
  ) async {
    switch (action) {
      case NotebookAction.open:
        await openNotebook(context, notebook, from: covers.originOf(context, notebook));
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
        if (current != null) controller.updateNotebook(current.copyWith(title: title));
      case NotebookAction.favorite:
        controller.setFavorite(notebook.id, !notebook.favorite);
      case NotebookAction.cover:
        await changeCover(context, controller, notebook);
      case NotebookAction.duplicate:
        final copy = controller.duplicate(notebook.id);
        if (copy != null && context.mounted) _toast(context, 'Duplicated as “${copy.title}”');
      case NotebookAction.move:
        final target = await showMoveDialog(
          context,
          controller: controller,
          title: 'Move “${notebook.title}”',
          currentFolderId: notebook.folderId,
        );
        if (target != null && context.mounted) move(context, [notebook.id], target.folderId);
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
        if (ok) controller.deleteForever(notebook.id);
    }
  }

  Future<void> onFolderAction(BuildContext context, Folder folder, FolderAction action) async {
    switch (action) {
      case FolderAction.open:
        controller.openFolder(folder.id);
      case FolderAction.edit:
        final details = await showFolderDialog(
          context,
          title: 'Edit folder',
          confirmLabel: 'Save',
          initialName: folder.name,
          initialColor: folder.color,
        );
        final current = controller.folderById(folder.id);
        if (details == null || current == null) return;
        controller.updateFolder(current.copyWith(name: details.name, color: details.color));
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
      case FolderAction.delete:
        await deleteFolder(context, folder);
    }
  }

  /// Confirms with what goes ("2 subfolders and 14 notebooks go to the
  /// trash"), deletes, and offers Undo.
  Future<void> deleteFolder(BuildContext context, Folder folder) async {
    final (:folders, :notebooks) = controller.contentsOf(folder.id);
    final parts = [
      if (folders > 0) countLabel(folders, 'subfolder'),
      if (notebooks > 0) countLabel(notebooks, 'notebook'),
    ];
    final ok = await confirmAction(
      context,
      title: 'Delete “${folder.name}”?',
      message: switch ((folders, notebooks)) {
        (0, 0) => 'The folder is empty.',
        (_, 0) => '${parts.join()} ${folders == 1 ? 'goes' : 'go'} too.',
        (0, _) => '${parts.join()} ${notebooks == 1 ? 'goes' : 'go'} to the trash.',
        _ => '${parts.join(' and ')} go to the trash.',
      },
      confirmLabel: 'Delete',
      destructive: true,
    );
    if (!ok || !context.mounted) return;
    final deletion = controller.deleteFolder(folder.id);
    showMessage(
      context,
      '“${folder.name}” deleted',
      action: SnackBarAction(label: 'Undo', onPressed: () => controller.undoDeleteFolder(deletion)),
    );
  }

  /// Takes notebooks [ids] out of the trash and says where they went.
  void restore(BuildContext context, List<String> ids) {
    for (final id in ids) {
      controller.restoreNotebook(id);
    }
    final restored = [for (final id in ids) ?controller.services.notebooks.get(id)];
    if (restored.isEmpty) return;
    final folders = {for (final n in restored) n.folderId};
    final where = folders.length == 1 ? '“${_folderName(folders.single)}”' : 'their folders';
    final what = restored.length == 1
        ? '“${restored.single.title}”'
        : countLabel(ids.length, 'notebook');
    showMessage(context, 'Restored $what to $where');
  }

  /// Moves notebooks [ids] into [folderId] (null = the library root), says
  /// so and offers Undo.
  void move(BuildContext context, List<String> ids, String? folderId) {
    final from = {for (final id in ids) id: controller.services.notebooks.get(id)?.folderId};
    for (final id in ids) {
      controller.moveNotebook(id, folderId);
    }
    final notebook = ids.length == 1 ? controller.services.notebooks.get(ids.single) : null;
    final what = notebook != null ? '“${notebook.title}”' : countLabel(ids.length, 'notebook');
    showMessage(
      context,
      'Moved $what to “${_folderName(folderId)}”',
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () {
          for (final MapEntry(key: id, value: folder) in from.entries) {
            controller.moveNotebook(id, folder);
          }
        },
      ),
    );
  }

  String _folderName(String? id) => controller.folderById(id)?.name ?? 'Library';

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

  /// `1 notebook`, `3 subfolders`.
  static String countLabel(int n, String one) => '$n ${n == 1 ? one : '${one}s'}';

  void _toast(BuildContext context, String message) {
    showMessage(context, message);
  }
}
