import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../domain/folder.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/dialog_or_sheet.dart';
import '../../../ui/sheet_parts.dart';
import '../library_controller.dart';

/// The destination chosen in [showMoveDialog]; `folderId` null = root.
typedef MoveTarget = ({String? folderId});

/// Lets the user pick a destination folder. [movingFolderId] excludes that
/// folder's subtree; [currentFolderId] is shown as the current location.
Future<MoveTarget?> showMoveDialog(
  BuildContext context, {
  required LibraryController controller,
  required String title,
  String? currentFolderId,
  String? movingFolderId,
}) {
  final excluded = <String>{};
  if (movingFolderId != null) {
    void exclude(String id) {
      excluded.add(id);
      for (final c in controller.childrenOf(id)) {
        exclude(c.id);
      }
    }

    exclude(movingFolderId);
  }
  final rows = <({Folder? folder, int depth})>[(folder: null, depth: 0)];
  void addChildren(String? parent, int depth) {
    for (final f in controller.childrenOf(parent)) {
      if (excluded.contains(f.id)) continue;
      rows.add((folder: f, depth: depth));
      addChildren(f.id, depth + 1);
    }
  }

  addChildren(null, 1);
  return showDialogOrSheet<MoveTarget>(
    context: context,
    maxWidth: 480,
    maxHeight: 560,
    minHeight: 420,
    builder: (context, wide) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(Gaps.xl, wide ? Gaps.lg : 0, Gaps.md, Gaps.sm),
          child: SheetHeader(title: title, onClose: () => Navigator.pop(context)),
        ),
        // Choosing a folder moves there at once: no footer.
        Flexible(
          child: ListView(
            shrinkWrap: true,
            padding: EdgeInsets.fromLTRB(
              Gaps.sm,
              0,
              Gaps.sm,
              Gaps.md + (wide ? 0 : MediaQuery.paddingOf(context).bottom),
            ),
            children: [
              for (final row in rows)
                _FolderRow(
                  folder: row.folder,
                  depth: row.depth,
                  current: row.folder?.id == currentFolderId,
                  onTap: () => Navigator.pop<MoveTarget>(context, (folderId: row.folder?.id)),
                ),
            ],
          ),
        ),
      ],
    ),
  );
}

/// One destination: indented under its parent, with the current location
/// marked and not selectable.
class _FolderRow extends StatelessWidget {
  const _FolderRow({
    required this.folder,
    required this.depth,
    required this.current,
    required this.onTap,
  });

  final Folder? folder;
  final int depth;
  final bool current;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final folder = this.folder;

    return ListTile(
      minTileHeight: 52,
      contentPadding: EdgeInsets.only(left: Gaps.md + depth * 24.0, right: Gaps.md),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.sm)),
      leading: Icon(
        folder == null ? Symbols.auto_stories_rounded : Symbols.folder_rounded,
        fill: folder == null ? 0 : 1,
        color: folder == null ? scheme.onSurfaceVariant : Color(folder.color),
        size: 28,
      ),
      title: Text(folder?.name ?? 'Library', maxLines: 1, overflow: TextOverflow.ellipsis),
      enabled: !current,
      trailing: current
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: Gaps.sm, vertical: Gaps.xxs),
              decoration: BoxDecoration(
                color: scheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(Radii.xs),
              ),
              child: Text(
                'Current',
                style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            )
          : null,
      onTap: onTap,
    );
  }
}
