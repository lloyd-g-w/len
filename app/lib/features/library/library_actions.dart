import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../domain/folder.dart';
import '../../domain/notebook.dart';
import '../../ui/text_prompt.dart';
import '../documents/pdf/pdf_import_flow.dart';
import '../editor/tabs/editor_workspace.dart' as editor;
import 'library_controller.dart';
import 'library_dialogs.dart';
import 'library_drag.dart';
import 'library_menus.dart';
import 'new_notebook_sheet.dart';
import 'thumbnails/thumbnail_cache.dart';

/// User-facing flows of the library (dialogs, confirmations, navigation)
/// on top of [LibraryController]. Widgets pass their own [BuildContext].
class LibraryActions {
  LibraryActions({required this.controller, required this.thumbnails});

  final LibraryController controller;
  final ThumbnailCache thumbnails;

  Future<void> openNotebook(BuildContext context, Notebook notebook) async {
    if (notebook.isTrashed) {
      final action = await showContextMenuAt(context, items: notebookMenuItems(notebook));
      if (action != null && context.mounted) await onNotebookAction(context, notebook, action);
      return;
    }
    final tabs = AppScope.read(context).openNotebooks;
    await editor.openNotebook(context, notebook);
    thumbnails.invalidate([...tabs.takeVisited(), notebook.id]);
    controller.reload();
  }

  Future<void> createNotebook(BuildContext context) async {
    final request = await NewNotebookSheet.show(context);
    if (request == null || !context.mounted) return;
    if (request.importPdf) return importPdf(context);
    final notebook = controller.createNotebook(
      title: request.title,
      kind: request.kind,
      paper: request.paper,
      paperColor: request.template.color,
      coverColor: request.coverColor,
      coverStyle: request.coverStyle,
      firstPage: request.template,
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
    final messenger = ScaffoldMessenger.of(context);
    messenger
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('“${notebook.title}” moved to Trash'),
          action: SnackBarAction(
            label: 'Undo',
            onPressed: () => controller.restoreNotebook(notebook.id),
          ),
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
        await openNotebook(context, notebook);
      case NotebookAction.rename:
        final title = await showTextPrompt(
          context,
          title: 'Rename',
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
        final choice = await showCoverSheet(context, notebook);
        final current = controller.services.notebooks.get(notebook.id);
        if (choice == null || current == null) return;
        controller.updateNotebook(
          current.copyWith(coverColor: choice.color, coverStyle: choice.style),
        );
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
        if (target != null) controller.moveNotebook(notebook.id, target.folderId);
      case NotebookAction.trash:
        await trash(context, notebook);
      case NotebookAction.restore:
        controller.restoreNotebook(notebook.id);
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
        final ok = await confirmAction(
          context,
          title: 'Delete “${folder.name}”?',
          message: 'Its subfolders are deleted too; notebooks inside move to the Trash.',
          confirmLabel: 'Delete',
          destructive: true,
        );
        if (ok) controller.deleteFolder(folder.id);
    }
  }

  Future<void> emptyTrash(BuildContext context) async {
    final count = controller.trash.length;
    if (count == 0) return;
    final ok = await confirmAction(
      context,
      title: 'Empty Trash?',
      message:
          '$count ${count == 1 ? 'notebook' : 'notebooks'} will be deleted forever '
          'on all synced devices.',
      confirmLabel: 'Empty Trash',
      destructive: true,
    );
    if (ok) controller.emptyTrash();
  }

  void _toast(BuildContext context, String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}
