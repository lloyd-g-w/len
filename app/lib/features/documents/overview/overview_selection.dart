import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../ui/app_dialogs.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/labelled_action.dart';

/// What can be done to the pages selected in the overview.
enum SelectionAction { bookmark, duplicate, send, template, export, delete }

/// The app bar in selection mode: count, select all, done.
class SelectionAppBar extends StatelessWidget implements PreferredSizeWidget {
  const SelectionAppBar({
    super.key,
    required this.count,
    required this.total,
    required this.onClose,
    required this.onSelectAll,
  });

  final int count;
  final int total;
  final VoidCallback onClose;
  final VoidCallback onSelectAll;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 8);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      toolbarHeight: kToolbarHeight + 8,
      leading: IconButton(
        tooltip: 'Done',
        icon: const Icon(Symbols.close_sharp),
        onPressed: onClose,
      ),
      title: Text(count == 0 ? 'Select pages' : '$count selected'),
      actions: [
        TextButton(
          onPressed: onSelectAll,
          child: Text(count == total ? 'Select none' : 'Select all'),
        ),
        const SizedBox(width: Gaps.sm),
      ],
    );
  }
}

/// Actions for the selected pages, along the bottom (thumb reach).
class SelectionBar extends StatelessWidget {
  const SelectionBar({
    super.key,
    required this.count,
    required this.onAction,
    this.allBookmarked = false,
    this.offered = const {
      SelectionAction.bookmark,
      SelectionAction.duplicate,
      SelectionAction.delete,
    },
  });

  final int count;

  /// The actions shown (the notebook's handlers decide).
  final Set<SelectionAction> offered;

  /// Whether every selected page is bookmarked: the action removes them.
  final bool allBookmarked;
  final ValueChanged<SelectionAction> onAction;

  Future<void> _delete(BuildContext context) async {
    final ok =
        count == 1 ||
        await confirmAction(
          context,
          title: 'Delete $count pages?',
          message: 'Their ink, text and images are deleted with them.',
          confirmLabel: 'Delete',
          destructive: true,
          icon: Symbols.delete_sharp,
        );
    if (ok) onAction(SelectionAction.delete);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final enabled = count > 0;
    Widget action(IconData icon, String label, VoidCallback onTap, {Color? color}) => Expanded(
      child: LabelledAction(
        icon: icon,
        label: label,
        color: color,
        onPressed: enabled ? onTap : null,
      ),
    );
    return Material(
      color: Surfaces.chrome(scheme),
      child: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: BoxDecoration(border: Border(top: Surfaces.chromeEdge(scheme))),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: Gaps.md, vertical: Gaps.xs),
            child: Align(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: Row(
                  children: [
                    for (final a in SelectionAction.values)
                      if (offered.contains(a))
                        switch (a) {
                          SelectionAction.bookmark => action(
                            allBookmarked ? Symbols.bookmark_remove_sharp : Symbols.bookmark_sharp,
                            allBookmarked ? 'Remove bookmark' : 'Bookmark',
                            () => onAction(a),
                          ),
                          SelectionAction.duplicate => action(
                            Symbols.library_add_sharp,
                            'Duplicate',
                            () => onAction(a),
                          ),
                          SelectionAction.send => action(
                            Symbols.drive_file_move_sharp,
                            'Move to…',
                            () => onAction(a),
                          ),
                          SelectionAction.template => action(
                            Symbols.grid_on_sharp,
                            'Template…',
                            () => onAction(a),
                          ),
                          SelectionAction.export => action(
                            Symbols.ios_share_sharp,
                            'Export…',
                            () => onAction(a),
                          ),
                          SelectionAction.delete => action(
                            Symbols.delete_sharp,
                            'Delete',
                            () => _delete(context),
                            color: scheme.error,
                          ),
                        },
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
