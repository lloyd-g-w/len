import 'package:flutter/material.dart';

import '../../data/app_preferences.dart';
import '../../domain/preferences.dart';
import 'settings_section.dart';

/// Where the editor's toolbar sits (also changeable from the editor menu).
class EditorSettings extends StatelessWidget {
  const EditorSettings({super.key, required this.preferences});

  final AppPreferences preferences;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: preferences,
      builder: (context, _) => SettingsSection(
        title: 'Editor',
        icon: Icons.space_dashboard_outlined,
        children: [
          SettingsTile(
            icon: Icons.view_day_outlined,
            title: 'Toolbar position',
            subtitle: switch (preferences.toolbarPlacement) {
              ToolbarPlacement.auto =>
                'At the top on tablets and computers, at the bottom on phones.',
              ToolbarPlacement.top => 'Always at the top.',
              ToolbarPlacement.bottom => 'Always at the bottom, within thumb reach.',
              ToolbarPlacement.floating => 'Floating; drag it anywhere by its grip.',
            },
            below: SegmentedButton<ToolbarPlacement>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: ToolbarPlacement.auto, label: Text('Auto')),
                ButtonSegment(value: ToolbarPlacement.top, label: Text('Top')),
                ButtonSegment(value: ToolbarPlacement.bottom, label: Text('Bottom')),
                ButtonSegment(value: ToolbarPlacement.floating, label: Text('Float')),
              ],
              selected: {preferences.toolbarPlacement},
              onSelectionChanged: (s) => preferences.toolbarPlacement = s.single,
            ),
          ),
        ],
      ),
    );
  }
}
