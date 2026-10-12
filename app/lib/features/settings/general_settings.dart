import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/app_preferences.dart';
import '../../domain/preferences.dart';
import '../../ui/segment_label.dart';
import 'settings_section.dart';

/// General: the theme (System · Light · Dark).
class GeneralSettings extends StatelessWidget {
  const GeneralSettings({super.key, required this.preferences});

  final AppPreferences preferences;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: preferences,
      builder: (context, _) => SettingsSection(
        title: 'General',
        children: [
          SettingsTile(
            icon: Symbols.contrast_rounded,
            title: 'Theme',
            subtitle: 'Paper keeps its colour in both themes',
            control: ShrinkToFit(
              child: SegmentedButton<ThemePreference>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: ThemePreference.system, label: SegmentLabel('System')),
                  ButtonSegment(value: ThemePreference.light, label: SegmentLabel('Light')),
                  ButtonSegment(value: ThemePreference.dark, label: SegmentLabel('Dark')),
                ],
                selected: {preferences.themeMode},
                onSelectionChanged: (s) => preferences.themeMode = s.single,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
