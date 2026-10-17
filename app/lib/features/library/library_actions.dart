import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_services.dart';
import '../../data/archive/len_archives.dart';
import '../../domain/folder.dart';
import '../../domain/notebook.dart';
import '../../domain/notebook_style.dart';
import '../../domain/paper.dart';
import '../../ui/app_theme.dart';
import '../../ui/messages.dart';
import '../../ui/text_prompt.dart';
import '../backup/len_import_flow.dart';
import '../documents/export/notebooks_export.dart';
import '../documents/export/print_flow.dart';
import '../documents/pdf/pdf_import_flow.dart';
import '../documents/scan/scan_flow.dart';
import '../editor/tabs/editor_workspace.dart' as editor;
import '../history/version_history_sheet.dart';
import 'cover_locator.dart';
import 'library_controller.dart';
import 'library_dialogs.dart';
import 'library_drag.dart';
import 'library_menus.dart';
import 'new_notebook_sheet.dart';
import 'selection/library_selection.dart';
import 'thumbnails/thumbnail_cache.dart';

part 'library_folder_actions.dart';
part 'library_notebook_actions.dart';

/// User-facing flows of the library (dialogs, confirmations, navigation)
/// on top of [LibraryController]. Widgets pass their own [BuildContext].
class LibraryActions with _NotebookActions, _FolderActions {
  LibraryActions({required this.controller, required this.thumbnails, LibrarySelection? selection})
    : selection = selection ?? LibrarySelection();

  @override
  final LibraryController controller;
  final ThumbnailCache thumbnails;

  /// Notebooks picked in selection mode.
  final LibrarySelection selection;

  /// Covers on screen, which notebooks open out of.
  @override
  final CoverLocator covers = CoverLocator();

  /// Opens [notebook] in the editor (out of its cover with [from]), and
  /// refreshes the covers of everything visited when the editor closes.
  @override
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
  @override
  void startSelection(BuildContext context, [String? id]) {
    ScaffoldMessenger.maybeOf(context)?.hideCurrentSnackBar();
    selection.start(id);
  }

  /// Opens the new-notebook sheet and then the new notebook. Where the
  /// library has no ⊕▾ (phones), the sheet offers Scan document…, Import
  /// PDF… and Import Len file… too.
  Future<void> createNotebook(BuildContext context) async {
    SheetImport? import;
    final request = await NewNotebookSheet.show(
      context,
      onImport: Breakpoints.libraryCompact(MediaQuery.sizeOf(context))
          ? (kind) => import = kind
          : null,
    );
    if (!context.mounted) return;
    switch (import) {
      case SheetImport.scan:
        return scanDocument(context);
      case SheetImport.pdf:
        return importPdf(context);
      case SheetImport.len:
        return importLen(context);
      case null:
    }
    if (request == null) return;
    final style = request.template.style;
    if (style != PaperStyle.image) controller.services.preferences.notePaperUsed(style.name);
    // Where the sheet starts next time, unless a style is the default: a
    // notebook as this one ("New notebook" stays a notebook; a canvas
    // leaves it alone, and a default style can start as a canvas).
    final choice = NotebookChoice.of(
      kind: request.kind,
      template: request.template,
      coverColor: request.coverColor,
    );
    if (choice != null && request.kind == NotebookKind.paged) {
      controller.services.preferences.lastNotebookChoice = choice;
    }
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

  /// Scans pages (starting with [photos] if any) into a new notebook,
  /// files it like a new notebook and opens it.
  Future<void> scanDocument(BuildContext context, {List<XFile> photos = const []}) async {
    final scanned = await scanToNewNotebookFlow(context, photos: photos);
    if (scanned == null || !context.mounted) return;
    final notebook = controller.adoptNotebook(scanned);
    await openNotebook(context, notebook);
  }

  /// Imports a Len file the user picks (a notebook or folder into the
  /// open folder, a backup as [importLenFlow] says); a notebook opens.
  Future<void> importLen(BuildContext context) async {
    final result = await importLenFlow(context);
    if (result == null || !context.mounted) return;
    controller.reload();
    if (result.manifest.kind != LenArchiveKind.notebook) return;
    final notebook = result.notebooks.isEmpty
        ? null
        : controller.services.notebooks.get(result.notebooks.single);
    if (notebook != null) await openNotebook(context, notebook);
  }

  @override
  String _folderName(String? id) => controller.folderById(id)?.name ?? 'Library';

  /// `1 notebook`, `3 subfolders`.
  static String countLabel(int n, String one) => '$n ${n == 1 ? one : '${one}s'}';

  @override
  void _toast(BuildContext context, String message) {
    showMessage(context, message);
  }

  /// Says what was done and offers [undo].
  @override
  void _undoable(BuildContext context, String message, VoidCallback undo) {
    if (!context.mounted) return;
    showMessage(
      context,
      message,
      action: SnackBarAction(label: 'Undo', onPressed: undo),
    );
  }
}
