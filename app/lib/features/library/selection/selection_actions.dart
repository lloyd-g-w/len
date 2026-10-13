import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/app_dialogs.dart';
import '../../../ui/messages.dart';
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

  /// Stars every selected notebook, or unstars them if all are starred.
  void favoriteSelected(LibrarySelection selection) {
    final ids = _ids(selection);
    final notebooks = controller.visibleNotebooks.where((n) => ids.contains(n.id));
    final star = !notebooks.every((n) => n.favorite);
    for (final id in ids) {
      controller.setFavorite(id, star);
    }
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

  void trashSelected(BuildContext context, LibrarySelection selection) {
    final ids = _ids(selection);
    if (ids.isEmpty) return;
    for (final id in ids) {
      controller.trashNotebook(id);
    }
    selection.clear();
    showMessage(
      context,
      '${_count(ids.length)} moved to the trash',
      action: SnackBarAction(
        label: 'Undo',
        onPressed: () {
          for (final id in ids) {
            controller.restoreNotebook(id);
          }
        },
      ),
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
    for (final id in ids) {
      controller.deleteForever(id);
    }
    selection.clear();
  }
}
