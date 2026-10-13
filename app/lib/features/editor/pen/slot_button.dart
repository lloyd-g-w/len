import 'package:flutter/material.dart';

import '../../../ui/app_theme.dart';
import '../toolbar/toolbar_metrics.dart';

/// One quick slot in the toolbar (a colour, a width or an eraser size):
/// tap to select it; tap it again when selected, long-press or right-click
/// to edit it ([onEdit]).
///
/// A selected colour slot gets a 1.5-px `onSurface` ring (the weight of
/// the glyphs beside it) with a gap
/// around its swatch, so it reads on any colour (white and black included)
/// in light and dark themes. Size slots ([plate]) get the neutral pressed
/// plate instead, so a selected size never looks like a selected dark
/// colour beside it.
class SlotButton extends StatelessWidget {
  const SlotButton({
    super.key,
    required this.selected,
    required this.tooltip,
    required this.semanticLabel,
    required this.onSelect,
    required this.child,
    this.onEdit,
    this.editHint = 'Double tap for options',
    this.plate = false,
  });

  /// Outer diameter of the selection ring.
  static const double ring = 30;

  /// The selection ring's stroke.
  static const double ringWidth = 1.5;

  final bool selected;
  final String tooltip;
  final String semanticLabel;
  final VoidCallback onSelect;

  /// Edits the slot, anchored to the given context; null: a tap on the
  /// selected slot does nothing more (slots inside the popover).
  final void Function(BuildContext anchor)? onEdit;

  /// What a screen reader says a double tap on the selected slot does.
  final String editHint;

  final Widget child;

  /// Shows the selection as a [Surfaces.pressed] plate (sizes) rather
  /// than a ring (colours).
  final bool plate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final edit = onEdit;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: Semantics(
        button: true,
        selected: selected,
        label: semanticLabel,
        hint: selected && edit != null ? editHint : null,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => selected && edit != null ? edit(context) : onSelect(),
            onLongPress: edit == null ? null : () => edit(context),
            onSecondaryTap: edit == null ? null : () => edit(context),
            child: SizedBox.square(
              dimension: ToolbarMetrics.slotOf(context),
              child: Center(
                child: AnimatedContainer(
                  duration: Motion.fast,
                  width: ring,
                  height: ring,
                  decoration: plate
                      ? BoxDecoration(
                          color: selected
                              ? Surfaces.pressed(scheme)
                              : Surfaces.pressed(scheme).withValues(alpha: 0),
                          borderRadius: BorderRadius.circular(Radii.xs),
                        )
                      : BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: selected
                                ? scheme.onSurface
                                : scheme.onSurface.withValues(alpha: 0),
                            width: ringWidth,
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

/// A colour slot's swatch: a 22-dp dot with a hairline, so white reads on
/// light chrome and black on dark.
class SlotSwatch extends StatelessWidget {
  const SlotSwatch({super.key, required this.color});

  /// Opaque ARGB.
  final int color;

  static const double size = 22;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final nearSurface =
        (Color(color).computeLuminance() - scheme.surface.computeLuminance()).abs() < 0.1;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: Color(color),
        shape: BoxShape.circle,
        border: Border.all(
          color: nearSurface ? scheme.onSurfaceVariant : scheme.outline.withValues(alpha: 0.5),
          width: nearSurface ? 1 : 0.5,
        ),
      ),
    );
  }
}

/// A width slot's dot, at (scaled) real size, neutral so it never reads as
/// a colour: `onSurface` when [selected], else `onSurfaceVariant`.
class SlotDot extends StatelessWidget {
  const SlotDot({super.key, required this.diameter, required this.selected, this.hollow = false});

  final double diameter;
  final bool selected;

  /// Drawn as a ring (eraser sizes).
  final bool hollow;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = selected ? scheme.onSurface : scheme.onSurfaceVariant;
    return AnimatedContainer(
      duration: Motion.fast,
      width: diameter,
      height: diameter,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: hollow ? null : color,
        border: hollow ? Border.all(color: color, width: 1.5) : null,
      ),
    );
  }
}
