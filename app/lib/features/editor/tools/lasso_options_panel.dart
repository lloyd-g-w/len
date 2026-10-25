import 'package:flutter/material.dart';

import '../../../ink/tool_settings.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/group_header.dart';
import '../../../ui/roving_focus.dart';
import '../../documents/templates/even_choices.dart';
import '../pen/option_controls.dart';
import 'tool_icons.dart';

/// The lasso's options: its shape (freehand loop or rectangle; unlabelled,
/// as the laser's Dot / Trail), how much of an item it must cover
/// (touching, mostly, whole) and which kinds of item it selects (at least
/// one stays on).
class LassoOptionsPanel extends StatelessWidget {
  const LassoOptionsPanel({super.key, required this.tools});

  final ToolSettings tools;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: tools,
      builder: (context, _) {
        final lasso = tools.lasso;
        void update(LassoConfig config) => tools.lasso = config;
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            OptionHeader(
              'Lasso',
              trailing: ResetButton<LassoConfig>(
                value: lasso,
                defaults: const LassoConfig(),
                onChanged: update,
              ),
            ),
            const SizedBox(height: Gaps.sm),
            // No heading, as the laser's Dot / Trail: the glyphs say it,
            // and "Shape" would read as the Shapes tool (R12-4).
            RovingSegments(
              SegmentedButton<LassoShape>(
                showSelectedIcon: false,
                segments: [
                  for (final shape in LassoShape.values)
                    ButtonSegment(
                      value: shape,
                      icon: ToolIcon(switch (shape) {
                        LassoShape.freehand => ToolIconKind.lasso,
                        LassoShape.rectangle => ToolIconKind.lassoRectangle,
                      }),
                      label: Text(shape.label),
                    ),
                ],
                selected: {lasso.shape},
                onSelectionChanged: (s) => update(tools.lasso.copyWith(shape: s.single)),
              ),
            ),
            const SizedBox(height: Gaps.md),
            const GroupHeader('Select'),
            const SizedBox(height: Gaps.xs),
            RovingSegments(
              SegmentedButton<LassoCover>(
                showSelectedIcon: false,
                segments: [
                  for (final cover in LassoCover.values)
                    ButtonSegment(value: cover, label: Text(cover.label)),
                ],
                selected: {lasso.cover},
                onSelectionChanged: (s) => update(tools.lasso.copyWith(cover: s.single)),
              ),
            ),
            const SizedBox(height: Gaps.xs),
            Text(lasso.cover.caption, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: Gaps.md),
            const GroupHeader('Items'),
            const SizedBox(height: Gaps.xs),
            // Toggles: each chip on or off (the last one stays on: a lasso
            // selecting nothing is no use).
            EvenChoices(
              choices: [
                for (final kind in LassoKind.values)
                  EvenChoice(
                    key: ValueKey('lasso-${kind.name}'),
                    label: kind.label,
                    selected: lasso.takes(kind),
                    onTap: () => update(tools.lasso.toggled(kind, !tools.lasso.takes(kind))),
                  ),
              ],
            ),
          ],
        );
      },
    );
  }
}
