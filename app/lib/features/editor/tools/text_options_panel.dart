import 'package:flutter/material.dart';

import '../../../ink/tool_settings.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/color_dot.dart';
import '../../../ui/color_picker/color_swatches.dart';
import '../pen/option_controls.dart';

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
            OptionSlider(
              label: 'Size',
              value: style.fontSize,
              min: 8,
              max: 96,
              display: (v) => v.round().toString(),
              onChanged: (v) => tools.textStyle = style.copyWith(fontSize: v.roundToDouble()),
            ),
            OptionSwitch(
              label: 'Bold',
              value: style.bold,
              onChanged: (v) => tools.textStyle = style.copyWith(bold: v),
            ),
            OptionSwitch(
              label: 'Italic',
              value: style.italic,
              onChanged: (v) => tools.textStyle = style.copyWith(italic: v),
            ),
            const SizedBox(height: Gaps.sm),
            Wrap(
              spacing: Gaps.xs,
              runSpacing: Gaps.xs,
              children: [
                for (final c in ColorSwatches.palette.take(15))
                  ColorDot(
                    color: c,
                    size: 28,
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
