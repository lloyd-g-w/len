import 'package:flutter/material.dart';

import '../../ui/app_theme.dart';

/// One row of the library sidebar: icon, label and optional trailing
/// count, with selected, hover and drop-target states.
class SidebarItem extends StatefulWidget {
  const SidebarItem({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.selected = false,
    this.dropActive = false,
    this.count,
    this.iconColor,
    this.indent = 0,
    this.leading,
    this.onSecondaryTapUp,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  /// A dragged item hovers above this row.
  final bool dropActive;
  final int? count;
  final Color? iconColor;
  final double indent;

  /// Optional widget before the icon (e.g. an expand chevron).
  final Widget? leading;
  final GestureTapUpCallback? onSecondaryTapUp;

  @override
  State<SidebarItem> createState() => _SidebarItemState();
}

class _SidebarItemState extends State<SidebarItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final selected = widget.selected;
    final background = widget.dropActive
        ? scheme.primaryContainer
        : selected
        ? scheme.secondaryContainer
        : _hovered
        ? scheme.onSurface.withValues(alpha: 0.05)
        : Colors.transparent;
    final foreground = selected ? scheme.onSecondaryContainer : scheme.onSurface;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 1),
      child: AnimatedContainer(
        duration: Motion.fast,
        height: 40,
        decoration: BoxDecoration(
          color: background,
          borderRadius: BorderRadius.circular(Radii.sm),
          border: widget.dropActive ? Border.all(color: scheme.primary, width: 1.5) : null,
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.sm),
            onTap: widget.onTap,
            onHover: (h) => setState(() => _hovered = h),
            onSecondaryTapUp: widget.onSecondaryTapUp,
            child: Padding(
              padding: EdgeInsets.only(left: Gaps.md - 2 + widget.indent, right: Gaps.md),
              child: Row(
                children: [
                  ?widget.leading,
                  Icon(
                    widget.icon,
                    size: 20,
                    color: widget.iconColor ?? (selected ? foreground : scheme.onSurfaceVariant),
                  ),
                  const SizedBox(width: Gaps.md),
                  Expanded(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelLarge?.copyWith(
                        color: foreground,
                        fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (widget.count != null && widget.count! > 0)
                    Text(
                      '${widget.count}',
                      style: theme.textTheme.labelMedium?.copyWith(color: scheme.onSurfaceVariant),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
