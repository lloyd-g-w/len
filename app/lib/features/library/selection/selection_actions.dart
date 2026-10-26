import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/app_dialogs.dart';
import '../../../ui/messages.dart';
import '../../documents/export/notebooks_export.dart';
import '../dialogs/move_dialog.dart';
import '../library_actions.dart';
import '../library_controller.dart';
import 'library_selection.dart';

/// Batch operations on the notebooks of a [LibrarySelection].
extension SelectionActions on LibraryActions {
  List<String> _ids(LibrarySelection selection) => [
    for (final n in controller.visibleNotebooks)
      if (selection.contains(n.id)) n.id,
  ];

  String _count(int n) => n == 1 ? '1 notebook' : '$n notebooks';

  /// Stars every selected notebook, or unstars them if all are starred,
  /// and ends the selection (as move and trash do): the message with its
  /// Undo takes the bar's place.
  void favoriteSelected(BuildContext context, LibrarySelection selection) {
    final ids = _ids(selection);
    final notebooks = controller.visibleNotebooks.where((n) => ids.contains(n.id));
    setFavorite(context, ids, !notebooks.every((n) => n.favorite));
    selection.clear();
  }

  Future<void> moveSelected(BuildContext context, LibrarySelection selection) async {
    final ids = _ids(selection);
    if (ids.isEmpty) return;
    final target = await showMoveDialog(
      context,
      controller: controller,
      title: 'Move ${_count(ids.length)}',
      currentFolderId: controller.section == LibrarySection.library ? controller.folderId : null,
    );
    if (target == null || !context.mounted) return;
    move(context, ids, target.folderId);
    selection.clear();
  }

  /// Exports the selected notebooks (one file each), then ends the
  /// selection.
  Future<void> exportSelected(BuildContext context, LibrarySelection selection) async {
    final ids = _ids(selection).toSet();
    final notebooks = [
      for (final n in controller.visibleNotebooks)
        if (ids.contains(n.id)) n,
    ];
    if (notebooks.isEmpty) return;
    // The bar's context exports, so it ends afterwards.
    await exportNotebooks(context, notebooks);
    selection.clear();
  }

  void trashSelected(BuildContext context, LibrarySelection selection) {
    final ids = _ids(selection);
    if (ids.isEmpty) return;
    final trashed = controller.trashNotebooks(ids);
    selection.clear();
    if (trashed.isEmpty) return;
    showMessage(
      context,
      '${_count(trashed.length)} moved to the trash',
      action: SnackBarAction(label: 'Undo', onPressed: () => controller.restoreNotebooks(trashed)),
    );
  }

  void restoreSelected(BuildContext context, LibrarySelection selection) {
    restore(context, _ids(selection));
    selection.clear();
  }

  Future<void> deleteSelectedForever(BuildContext context, LibrarySelection selection) async {
    final ids = _ids(selection);
    if (ids.isEmpty) return;
    final ok = await confirmAction(
      context,
      title: 'Delete ${_count(ids.length)} forever?',
      message: 'They will be removed from all synced devices. This can’t be undone.',
      confirmLabel: 'Delete forever',
      destructive: true,
      icon: Symbols.delete_forever_rounded,
    );
    if (!ok) return;
    controller.deleteForever(ids);
    selection.clear();
  }
}
