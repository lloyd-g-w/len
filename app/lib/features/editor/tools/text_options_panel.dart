import 'package:flutter/material.dart';

import '../../../ink/tool_settings.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/color_dot.dart';
import '../../../ui/color_picker/color_swatches.dart';
import '../../../ui/even_grid.dart';
import '../pen/option_controls.dart';
import 'text/text_style_menus.dart';

/// Default formatting for new text boxes.
class TextOptionsPanel extends StatelessWidget {
  const TextOptionsPanel({super.key, required this.tools});

  final ToolSettings tools;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: tools,
      builder: (context, _) {
        final style = tools.textStyle;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const OptionHeader('Text'),
            const SizedBox(height: Gaps.sm),
            OptionSlider(
              label: 'Size',
              value: style.fontSize,
              min: 8,
              max: 96,
              display: (v) => v.round().toString(),
              onChanged: (v) => tools.textStyle = style.copyWith(fontSize: v.roundToDouble()),
            ),
            Row(
              children: [
                Expanded(child: Text('Font', style: Theme.of(context).textTheme.bodyMedium)),
                FontMenuButton(
                  font: style.font,
                  onSelected: (f) => tools.textStyle = style.copyWith(font: f),
                ),
              ],
            ),
            const SizedBox(height: Gaps.sm),
            // The whole palette in two even rows, like the pen's.
            EvenGrid(
              itemExtent: 28,
              minItemExtent: 22,
              children: [
                for (final c in ColorSwatches.palette)
                  ColorDot(
                    color: c,
                    selected: style.color == c,
                    onTap: () => tools.textStyle = style.copyWith(color: c),
                  ),
              ],
            ),
            const SizedBox(height: Gaps.md),
            Text(
              'Tap the page to add a text box; tap a text box to edit it.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
        );
      },
    );
  }
}
