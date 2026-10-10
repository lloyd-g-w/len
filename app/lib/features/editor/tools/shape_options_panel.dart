import 'package:flutter/material.dart';

import '../../../ink/tool_settings.dart';
import '../../../ui/app_theme.dart';
import '../pen/option_controls.dart';
import 'tool_icons.dart';

/// Picks the shape the Shape tool draws. Shapes use the current pen's
/// colour, width and opacity.
class ShapeOptionsPanel extends StatelessWidget {
  const ShapeOptionsPanel({super.key, required this.tools});

  final ToolSettings tools;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: tools,
      builder: (context, _) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const OptionHeader('Shapes'),
          const SizedBox(height: Gaps.sm),
          Wrap(
            spacing: Gaps.xs,
            runSpacing: Gaps.xs,
            children: [
              for (final kind in ShapeKind.drawable)
                Tooltip(
                  message: kind.label,
                  child: IconButton(
                    key: ValueKey('shape-${kind.name}'),
                    isSelected: tools.shape == kind,
                    style: IconButton.styleFrom(
                      backgroundColor: tools.shape == kind
                          ? scheme.secondaryContainer
                          : scheme.surfaceContainerHighest,
                      fixedSize: const Size.square(44),
                    ),
                    onPressed: () => tools.shape = kind,
                    icon: Icon(shapeIcon(kind)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: Gaps.md),
          Text(
            'Drag to draw. Hold Shift for squares, circles and 15° lines. '
            'Colour and width come from the pen. Tip: with the pen, pause at the end '
            'of a stroke to snap it into a clean shape.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    );
  }
}
