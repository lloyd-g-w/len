import 'package:flutter/material.dart';

import '../../../domain/text/text_data.dart';
import '../../../ink/tool_settings.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/color_picker/color_choices.dart';
import '../pen/option_controls.dart';
import 'text/text_style_menus.dart';

/// Default formatting for new text boxes: size, font and colour.
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
            OptionHeader(
              'Text',
              trailing: ResetButton<TextData>(
                value: style,
                defaults: const TextData(),
                onChanged: (s) => tools.textStyle = s,
              ),
            ),
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
                Expanded(child: Text('Font', style: Theme.of(context).textTheme.labelLarge)),
                FontMenuButton(
                  font: style.font,
                  onSelected: (f) => tools.textStyle = style.copyWith(font: f),
                ),
              ],
            ),
            const SizedBox(height: Gaps.md),
            ColorChoices(
              color: style.color,
              recent: tools.recentColors,
              onChanged: (c) => tools.textStyle = style.copyWith(color: c),
            ),
            const SizedBox(height: Gaps.sm),
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
