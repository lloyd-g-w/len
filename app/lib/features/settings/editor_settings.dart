import 'package:flutter/material.dart';

import '../../data/app_preferences.dart';
import '../../domain/preferences.dart';
import '../../ui/segment_label.dart';
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
              ToolbarPlacement.docked =>
                'At the top on tablets and computers, at the bottom on phones.',
              ToolbarPlacement.floating => 'Floating; drag it anywhere by its grip.',
            },
            below: ShrinkToFit(
              child: SegmentedButton<ToolbarPlacement>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: ToolbarPlacement.docked, label: SegmentLabel('Docked')),
                  ButtonSegment(value: ToolbarPlacement.floating, label: SegmentLabel('Floating')),
                ],
                selected: {preferences.toolbarPlacement},
                onSelectionChanged: (s) => preferences.toolbarPlacement = s.single,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
