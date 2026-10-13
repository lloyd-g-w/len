import 'package:flutter/material.dart';

import 'app_theme.dart';

/// One row of a sidebar (library, settings): icon, label and optional trailing
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
    this.filled = false,
    this.indent = 0,
    this.leading,
    this.onSecondaryTapUp,
    this.onLongPress,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool selected;

  /// A dragged item hovers above this row.
  final bool dropActive;
  final int? count;
  final Color? iconColor;

  /// Draws the icon filled even when not [selected] (folder glyphs).
  final bool filled;
  final double indent;

  /// Optional widget before the icon (e.g. an expand chevron).
  final Widget? leading;
  final GestureTapUpCallback? onSecondaryTapUp;

  /// Touch alternative to the secondary tap (context menu).
  final VoidCallback? onLongPress;

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
    // The selected row carries the accent (REDESIGN §1.3).
    final background = widget.dropActive
        ? scheme.primary.withValues(alpha: 0.12)
        : selected
        ? scheme.primary.withValues(alpha: theme.brightness == Brightness.dark ? 0.18 : 0.10)
        : _hovered
        ? Surfaces.hovered(scheme)
        : Colors.transparent;
    final foreground = selected ? scheme.primary : scheme.onSurface;
    // Screen readers announce the current section.
    return Semantics(
      selected: selected,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 1),
        child: AnimatedContainer(
          duration: Motion.fast,
          // With the 1-dp gaps, a row is 48 dp on touch, 44 with a pointer.
          height: Targets.menuRowHeight(context) - 2,
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
              onLongPress: widget.onLongPress,
              child: Padding(
                padding: EdgeInsets.only(left: Gaps.md - 2 + widget.indent, right: Gaps.md),
                child: Row(
                  children: [
                    ?widget.leading,
                    Icon(
                      widget.icon,
                      size: 20,
                      fill: selected || widget.filled ? 1 : 0,
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
                        style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                      ),
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
