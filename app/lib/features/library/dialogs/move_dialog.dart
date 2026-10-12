import 'package:flutter/material.dart';

import '../../../domain/folder.dart';
import '../../../ui/app_dialogs.dart';
import '../../../ui/app_theme.dart';
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
  return showDialog<MoveTarget>(
    context: context,
    builder: (context) => AppDialog(
      title: title,
      contentPadding: const EdgeInsets.fromLTRB(Gaps.md, Gaps.lg, Gaps.md, 0),
      content: SizedBox(
        width: 420,
        height: (rows.length * 52.0).clamp(120.0, 380.0),
        child: ListView(
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
      actions: [TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel'))],
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
    final color = folder == null ? scheme.primary : Color(folder.color);
    return ListTile(
      minTileHeight: 52,
      contentPadding: EdgeInsets.only(left: Gaps.md + depth * 24.0, right: Gaps.md),
      leading: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          color: color.withValues(alpha: theme.brightness == Brightness.dark ? 0.22 : 0.14),
          borderRadius: BorderRadius.circular(Radii.sm),
        ),
        child: Icon(
          folder == null ? Icons.auto_stories_rounded : Icons.folder_rounded,
          color: color,
          size: 20,
        ),
      ),
      title: Text(folder?.name ?? 'Library', maxLines: 1, overflow: TextOverflow.ellipsis),
      enabled: !current,
      trailing: current
          ? Container(
              padding: const EdgeInsets.symmetric(horizontal: Gaps.sm, vertical: Gaps.xxs),
              decoration: BoxDecoration(
                color: scheme.secondaryContainer,
                borderRadius: BorderRadius.circular(Radii.pill),
              ),
              child: Text(
                'Current',
                style: theme.textTheme.labelSmall?.copyWith(color: scheme.onSecondaryContainer),
              ),
            )
          : null,
      onTap: onTap,
    );
  }
}
