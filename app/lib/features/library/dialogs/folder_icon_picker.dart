import 'package:flutter/material.dart';

import '../../../domain/folder.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/even_grid.dart';
import '../folder_icons.dart';

/// A grid of folder icons (the default folder first), tinted with the
/// folder's [color] when selected.
class FolderIconPicker extends StatelessWidget {
  const FolderIconPicker({
    super.key,
    required this.selected,
    required this.color,
    required this.onChanged,
  });

  /// The chosen icon key; null = the default folder icon.
  final String? selected;

  /// The folder colour, for the selected icon.
  final Color color;

  final ValueChanged<String?> onChanged;

  /// Side of one icon tile: two even rows of ten at the dialog width.
  static const double tileSize = 36;

  @override
  Widget build(BuildContext context) {
    return EvenGrid(
      itemExtent: 44,
      minItemExtent: tileSize,
      maxSpacing: Gaps.sm,
      children: [
        for (final key in <String?>[null, ...Folder.iconKeys])
          _IconTile(
            icon: folderIconData(key),
            label: key == null ? 'Folder' : folderIconNames[key] ?? key,
            selected: key == selected,
            color: color,
            onTap: () => onChanged(key),
          ),
      ],
    );
  }
}

class _IconTile extends StatelessWidget {
  const _IconTile({
    required this.icon,
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final tint = color.withValues(alpha: theme.brightness == Brightness.dark ? 0.22 : 0.14);
    return Tooltip(
      message: label,
      child: Semantics(
        button: true,
        selected: selected,
        label: '$label icon',
        excludeSemantics: true,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.sm),
            onTap: onTap,
            child: AnimatedContainer(
              duration: Motion.fast,
              width: FolderIconPicker.tileSize,
              height: FolderIconPicker.tileSize,
              decoration: BoxDecoration(
                color: selected ? tint : Colors.transparent,
                borderRadius: BorderRadius.circular(Radii.sm),
                border: Border.all(
                  color: selected ? color : scheme.outlineVariant.withValues(alpha: 0.6),
                  width: selected ? 1.6 : 1,
                ),
              ),
              child: Icon(icon, size: 20, color: selected ? color : scheme.onSurfaceVariant),
            ),
          ),
        ),
      ),
    );
  }
}
