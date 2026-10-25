import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/app_preferences.dart';
import '../../domain/preferences.dart';
import '../../ui/app_theme.dart';
import '../../ui/count_stepper.dart';
import 'settings_section.dart';

/// Toolbar: how many quick colours and sizes the pen, highlighter and
/// laser pointer show beside the tools ([AppPreferences.slotCounts]; this
/// is their one home, the tools' options stay about how they write). Open
/// editors follow at once.
class ToolbarSettings extends StatelessWidget {
  const ToolbarSettings({super.key, required this.preferences});

  final AppPreferences preferences;

  static IconData _icon(SlotTool tool) => switch (tool) {
    SlotTool.pen => Symbols.edit_sharp,
    SlotTool.highlighter => Symbols.border_color_sharp,
    SlotTool.laser => Symbols.ads_click_sharp,
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: preferences,
      builder: (context, _) => SettingsSection(
        title: 'Toolbar',
        description: 'Quick colours and sizes beside the selected tool',
        children: [
          for (final tool in SlotTool.values)
            _SlotCountsTile(
              key: ValueKey('slot-counts-${tool.name}'),
              icon: _icon(tool),
              tool: tool,
              counts: preferences.slotCounts(tool),
              onChanged: (counts) => preferences.setSlotCounts(tool, counts),
            ),
        ],
      ),
    );
  }
}

/// One tool's row: "Pen, 3 colours, 3 sizes" with a stepper for each.
class _SlotCountsTile extends StatelessWidget {
  const _SlotCountsTile({
    super.key,
    required this.icon,
    required this.tool,
    required this.counts,
    required this.onChanged,
  });

  final IconData icon;
  final SlotTool tool;
  final SlotCounts counts;
  final ValueChanged<SlotCounts> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final name = tool.label.toLowerCase();
    Widget stepper(String label, int count, ValueChanged<int> set) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: text.labelLarge),
        const SizedBox(width: Gaps.xs),
        CountStepper(
          compact: false,
          noun: '$name ${label.toLowerCase()}',
          count: count,
          min: SlotCounts.min,
          max: SlotCounts.max,
          onAdd: () => set(count + 1),
          onRemove: () => set(count - 1),
        ),
      ],
    );
    return SettingsTile(
      icon: icon,
      title: tool.label,
      control: Wrap(
        spacing: Gaps.lg,
        runSpacing: Gaps.xs,
        children: [
          stepper('Colours', counts.colors, (n) => onChanged(counts.copyWith(colors: n))),
          stepper('Sizes', counts.sizes, (n) => onChanged(counts.copyWith(sizes: n))),
        ],
      ),
    );
  }
}
