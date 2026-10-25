import 'package:flutter/material.dart';

import '../../../ui/app_theme.dart';
import '../../../ui/roving_focus.dart';
import '../toolbar/toolbar_metrics.dart';

/// One quick slot in the toolbar (a colour, a width or an eraser size):
/// tap to select it; tap it again when selected, long-press or right-click
/// to edit it ([onEdit]).
///
/// A selected colour slot gets a 1.5-px `onSurface` ring (the weight of
/// the glyphs beside it) with a gap
/// around its swatch, so it reads on any colour (white and black included)
/// in light and dark themes. Size and mode slots ([rule]) get a short
/// accent rule under their glyph instead (the margin rule, DESIGN §0:
/// it marks where you are), so a selected size never looks like a
/// selected dark colour beside it.
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
    this.rule = false,
    this.tabStop,
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

  /// Shows the selection as an accent rule under the glyph (sizes, modes)
  /// rather than a ring (colours).
  final bool rule;

  /// Length of the selection rule under a size or mode.
  static const double ruleLength = Gaps.md;

  /// Whether Tab stops here in a toolbar ([RovingItem]); null: when
  /// [selected]. A row with nothing selected makes its first slot the stop.
  final bool? tabStop;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final edit = onEdit;
    void tap() => selected && edit != null ? edit(context) : onSelect();
    return RovingItem(
      stop: tabStop ?? selected,
      child: Tooltip(
        message: tooltip,
        waitDuration: const Duration(milliseconds: 500),
        child: Semantics(
          button: true,
          selected: selected,
          label: semanticLabel,
          hint: selected && edit != null ? editHint : null,
          // A keyboard stop: Enter or Space acts as a tap (so on the
          // selected slot it opens the editor).
          child: FocusableActionDetector(
            mouseCursor: SystemMouseCursors.click,
            actions: {ActivateIntent: CallbackAction<ActivateIntent>(onInvoke: (_) => tap())},
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: tap,
              onLongPress: edit == null ? null : () => edit(context),
              onSecondaryTap: edit == null ? null : () => edit(context),
              child: SizedBox.square(
                dimension: ToolbarMetrics.slotOf(context),
                child: Center(
                  child: rule
                      ? SizedBox.square(
                          dimension: ring,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              child,
                              Positioned(
                                bottom: 0,
                                child: AnimatedOpacity(
                                  opacity: selected ? 1 : 0,
                                  duration: Motion.fast,
                                  child: Container(
                                    width: ruleLength,
                                    height: Hairline.rule,
                                    color: scheme.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )
                      : AnimatedContainer(
                          duration: Motion.fast,
                          width: ring,
                          height: ring,
                          decoration: BoxDecoration(
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

/// A width slot's glyph: a short horizontal line as thick as the width
/// (scaled, [minThickness]–[maxThickness]), square-ended like a ruled
/// line, neutral so it never reads as a colour: `onSurface` when
/// [selected], else `onSurfaceVariant`.
class SlotLine extends StatelessWidget {
  const SlotLine({super.key, required this.thickness, required this.selected});

  final double thickness;
  final bool selected;

  /// The line's length: a colour dot's width, so the rows line up.
  static const double length = Glyphs.slotDot;

  /// The thinnest line drawn (a hairline would vanish).
  static const double minThickness = 1.5;

  /// The thickest line drawn, so a broad highlighter stays a line.
  static const double maxThickness = 9;

  /// How much of a width dot's growth the line keeps: steeper than half
  /// the dot, so three widths read as thin, medium and thick.
  static const double _growth = 0.65;

  /// The line for a width shown elsewhere as a dot [diameter] wide
  /// (`3 + width × dotScale`, [SlotDot]): 1 dp plus [_growth] of the
  /// dot's growth.
  static double thicknessFor(double diameter) => 1 + (diameter - 3) * _growth;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedContainer(
      duration: Motion.fast,
      width: length,
      height: thickness.clamp(minThickness, maxThickness),
      color: selected ? scheme.onSurface : scheme.onSurfaceVariant,
    );
  }
}
