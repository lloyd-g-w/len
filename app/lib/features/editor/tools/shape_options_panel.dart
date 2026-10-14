import 'package:flutter/material.dart';

import '../../../domain/stroke.dart';
import '../../../ink/tool_settings.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/roving_focus.dart';
import '../pen/option_controls.dart';
import 'fill_choices.dart';
import 'tool_icons.dart';

/// Picks the shape the Shape tool draws: one row of kinds, the selected
/// one on the neutral pressed plate (one Tab stop; arrows move). Shapes use the pen's colour and
/// size; closed ones get the [FillChoices] fill.
/// A caption points to "Hold to snap" in Settings → Writing, the one home
/// of that writing gesture (it turns a held pen or highlighter stroke into
/// a shape), and says when it is off.
class ShapeOptionsPanel extends StatelessWidget {
  const ShapeOptionsPanel({super.key, required this.tools});

  final ToolSettings tools;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return ListenableBuilder(
      listenable: tools,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const OptionHeader('Shapes'),
          const SizedBox(height: Gaps.sm),
          // One Tab stop, at the chosen shape; the arrows move along.
          RovingGroup(
            axis: Axis.horizontal,
            single: true,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final kind in ShapeKind.drawable)
                  RovingItem(
                    stop: tools.shape == kind,
                    child: IconButton(
                      key: ValueKey('shape-${kind.name}'),
                      tooltip: kind.label,
                      isSelected: tools.shape == kind,
                      style: IconButton.styleFrom(
                        backgroundColor: tools.shape == kind ? Surfaces.pressed(scheme) : null,
                        foregroundColor: scheme.onSurfaceVariant,
                        // Seven fit one row of the 320-dp popover, on touch too.
                        fixedSize: const Size.square(Targets.bar),
                        minimumSize: const Size.square(Targets.bar),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                        padding: EdgeInsets.zero,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(Radii.xs),
                        ),
                      ),
                      onPressed: () => tools.shape = kind,
                      icon: ShapeGlyph(kind, size: Glyphs.bar),
                      selectedIcon: IconTheme.merge(
                        data: IconThemeData(color: scheme.onSurface),
                        child: ShapeGlyph(kind, size: Glyphs.bar),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: Gaps.md),
          // Lines and arrows have no inside: the row stays (no jump
          // between kinds) but is dimmed and inert.
          IgnorePointer(
            ignoring: !tools.shape.isClosed,
            child: ExcludeSemantics(
              excluding: !tools.shape.isClosed,
              child: AnimatedOpacity(
                duration: Motion.fast,
                opacity: tools.shape.isClosed ? 1 : 0.38,
                child: FillChoices(
                  fill: tools.shapeFill,
                  ink: tools.configOf(InkTool.ballpoint).color,
                  recent: tools.recentColors,
                  onChanged: (f, {required fromBlock}) => tools.shapeFill = f,
                ),
              ),
            ),
          ),
          const SizedBox(height: Gaps.md),
          Text('Drag to draw, in the pen’s colour and size', style: text.bodySmall),
          Text('Tap a shape to drag its points', style: text.bodySmall),
          // Only a keyboard has Shift.
          if (!Targets.touchFirst)
            Text('Hold Shift for regular shapes and 15° lines', style: text.bodySmall),
          // Hold to snap is a writing gesture: its switch is in Settings.
          Text(
            tools.holdToStraighten
                ? 'Hold the pen still to snap a shape (Settings → Writing)'
                : 'Hold to snap is off in Settings → Writing',
            style: text.bodySmall,
          ),
        ],
      ),
    );
  }
}
