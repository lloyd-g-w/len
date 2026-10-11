import 'package:flutter/material.dart';

import '../../../ui/design_tokens.dart';

/// One quick-pick slot in the toolbar (a colour or a width): tap to select;
/// tap again when selected, long-press or right-click to edit.
///
/// The selection ring is drawn in the theme's primary colour with a gap of
/// toolbar surface between it and the content, so it reads on any swatch
/// colour (white and black included) in light and dark themes.
class SlotButton extends StatelessWidget {
  const SlotButton({
    super.key,
    required this.selected,
    required this.tooltip,
    required this.semanticLabel,
    required this.onSelect,
    required this.onEdit,
    required this.child,
    this.tonal = false,
  });

  /// Square hit target (logical pixels).
  static const double size = 40;

  final bool selected;
  final String tooltip;
  final String semanticLabel;
  final VoidCallback onSelect;

  /// Opens the slot's editor anchored to the given context.
  final void Function(BuildContext anchor) onEdit;

  final Widget child;

  /// Shows the selection as a filled tonal disc instead of a ring (width
  /// slots, so they never read as colours).
  final bool tonal;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: Semantics(
        button: true,
        selected: selected,
        label: semanticLabel,
        hint: selected ? 'Double tap to edit' : null,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => selected ? onEdit(context) : onSelect(),
            onLongPress: () => onEdit(context),
            onSecondaryTap: () => onEdit(context),
            child: SizedBox.square(
              dimension: size,
              child: Center(
                child: AnimatedContainer(
                  duration: Motion.fast,
                  width: 34,
                  height: 34,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: tonal && selected ? scheme.secondaryContainer : null,
                    border: Border.all(
                      color: selected && !tonal ? scheme.primary : Colors.transparent,
                      width: 2,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: child,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The subtle "+" that adds a slot to a row.
class AddSlotButton extends StatelessWidget {
  const AddSlotButton({super.key, required this.tooltip, required this.onAdd});

  final String tooltip;
  final void Function(BuildContext anchor) onAdd;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Builder(
      builder: (context) => SizedBox.square(
        dimension: SlotButton.size,
        child: IconButton(
          tooltip: tooltip,
          padding: EdgeInsets.zero,
          style: IconButton.styleFrom(tapTargetSize: MaterialTapTargetSize.shrinkWrap),
          onPressed: () => onAdd(context),
          icon: Icon(Icons.add_rounded, size: 18, color: scheme.onSurfaceVariant),
        ),
      ),
    );
  }
}
