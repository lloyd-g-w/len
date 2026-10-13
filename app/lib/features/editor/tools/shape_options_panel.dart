import 'package:flutter/material.dart';

import '../../../ink/tool_settings.dart';
import '../../../ui/app_theme.dart';
import '../pen/option_controls.dart';
import 'tool_icons.dart';

/// Picks the shape the Shape tool draws: one row of kinds, the selected
/// one on the neutral pressed plate. Shapes use the pen's colour and size.
/// Under a rule, "Hold to snap shapes": the one home of that global
/// switch (it turns a held pen or highlighter stroke into a shape).
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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              for (final kind in ShapeKind.drawable)
                IconButton(
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.xs)),
                  ),
                  onPressed: () => tools.shape = kind,
                  icon: ShapeGlyph(kind, size: Glyphs.bar),
                  selectedIcon: IconTheme.merge(
                    data: IconThemeData(color: scheme.onSurface),
                    child: ShapeGlyph(kind, size: Glyphs.bar),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Gaps.sm),
          Text('Drag to draw, in the pen’s colour and size', style: text.bodySmall),
          // Only a keyboard has Shift.
          if (!Targets.touchFirst)
            Text('Hold Shift for squares, circles and 15° lines', style: text.bodySmall),
          const OptionRule(),
          OptionSwitch(
            label: 'Hold to snap shapes',
            subtitle: 'Hold the pen still at the end of a stroke for a clean line or shape',
            value: tools.holdToStraighten,
            onChanged: (v) => tools.holdToStraighten = v,
          ),
        ],
      ),
    );
  }
}
