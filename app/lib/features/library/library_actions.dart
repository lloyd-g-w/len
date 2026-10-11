import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../domain/folder.dart';
import '../../domain/notebook.dart';
import '../../ui/messages.dart';
import '../../ui/text_prompt.dart';
import '../documents/pdf/pdf_import_flow.dart';
import '../editor/tabs/editor_workspace.dart' as editor;
import '../tags/tag_manager.dart';
import '../tags/tag_picker.dart';
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
    controller.createFolder(details.name, color: details.color, icon: details.icon);
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
        final choice = await showCoverSheet(context, notebook);
        final current = controller.services.notebooks.get(notebook.id);
        if (choice == null || current == null) return;
        controller.updateNotebook(
          current.copyWith(coverColor: choice.color, coverStyle: choice.style),
        );
      case NotebookAction.tags:
        await editTags(context, [notebook.id]);
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
          initialIcon: folder.icon,
        );
        final current = controller.folderById(folder.id);
        if (details == null || current == null) return;
        controller.updateFolder(
          current.copyWith(name: details.name, color: details.color, icon: details.icon),
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
      case FolderAction.delete:
        final ok = await confirmAction(
          context,
          title: 'Delete “${folder.name}”?',
          message: 'Its subfolders are deleted too; notebooks inside move to the trash.',
          confirmLabel: 'Delete',
          destructive: true,
        );
        if (ok) controller.deleteFolder(folder.id);
    }
  }

  /// Lets the user choose the tags of notebooks [ids].
  Future<void> editTags(BuildContext context, List<String> ids) async {
    final c = controller;
    final changes = await showTagPicker(
      context,
      tags: c.services.tags,
      title: ids.length == 1 ? 'Tags' : 'Tag ${ids.length} notebooks',
      current: [for (final id in ids) c.tagsOf(id).map((t) => t.id).toSet()],
    );
    // The picker may have created tags even when cancelled.
    if (changes == null) return c.reload();
    c.applyTagChanges(ids, changes);
  }

  /// Opens the tag manager.
  Future<void> manageTags(BuildContext context) => showTagManager(
    context,
    tags: controller.services.tags,
    countOf: controller.notebookCountOf,
    onChanged: controller.reload,
  );

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

  void _toast(BuildContext context, String message) {
    showMessage(context, message);
  }
}
