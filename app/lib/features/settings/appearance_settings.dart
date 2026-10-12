import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/app_preferences.dart';
import 'settings_section.dart';
import 'theme_choice.dart';

/// The theme mode.
class AppearanceSettings extends StatelessWidget {
  const AppearanceSettings({super.key, required this.preferences});

  final AppPreferences preferences;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: preferences,
      builder: (context, _) {
        return SettingsSection(
          title: 'Appearance',
          icon: Symbols.palette_rounded,
          children: [
            SettingsTile(
              title: 'Theme',
              below: ThemeChoice(
                value: preferences.themeMode,
                onChanged: (m) => preferences.themeMode = m,
              ),
            ),
          ],
        );
      },
    );
  }
}
