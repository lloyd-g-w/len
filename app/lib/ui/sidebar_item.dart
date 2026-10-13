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
    // The current row carries the margin rule (DESIGN §6): a short accent
    // rule at its left edge and the label in 600; no plate.
    final background = widget.dropActive
        ? scheme.primary.withValues(alpha: 0.12)
        : _hovered
        ? Surfaces.hovered(scheme)
        : Colors.transparent;
    final foreground = scheme.onSurface;
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
            borderRadius: BorderRadius.circular(Radii.xs),
            border: widget.dropActive ? Border.all(color: scheme.primary, width: 1.5) : null,
          ),
          child: Material(
            type: MaterialType.transparency,
            child: CustomPaint(
              foregroundPainter: selected ? MarginRulePainter(scheme.primary) : null,
              child: InkWell(
                borderRadius: BorderRadius.circular(Radii.xs),
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
                        size: Glyphs.bar,
                        fill: selected || widget.filled ? 1 : 0,
                        color:
                            widget.iconColor ?? (selected ? foreground : scheme.onSurfaceVariant),
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
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The margin rule (DESIGN §0): a [Hairline.rule]-wide accent rule, like an
/// exercise book's margin line, at the left edge of the current row (or
/// tab), vertically centred and [length] long.
class MarginRulePainter extends CustomPainter {
  const MarginRulePainter(this.color, {this.length = 20});

  final Color color;
  final double length;

  @override
  void paint(Canvas canvas, Size size) {
    final top = (size.height - length) / 2;
    canvas.drawRect(Rect.fromLTWH(0, top, Hairline.rule, length), Paint()..color = color);
  }

  @override
  bool shouldRepaint(MarginRulePainter old) => old.color != color || old.length != length;
}
