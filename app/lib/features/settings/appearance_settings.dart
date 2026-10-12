import 'package:flutter/material.dart';

import '../../data/app_preferences.dart';
import '../../ui/app_theme.dart';
import '../../ui/color_dot.dart';
import '../../ui/even_grid.dart';
import 'settings_section.dart';
import 'theme_choice.dart';

/// Theme mode and accent colour.
class AppearanceSettings extends StatelessWidget {
  const AppearanceSettings({super.key, required this.preferences});

  final AppPreferences preferences;

  static const _accentNames = {
    0xFF3B5BDB: 'Ink blue',
    0xFF0B7285: 'Lagoon',
    0xFF2B8A3E: 'Forest',
    0xFFE8590C: 'Orange',
    0xFFC2255C: 'Raspberry',
    0xFF7048E8: 'Violet',
    0xFF495057: 'Graphite',
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: preferences,
      builder: (context, _) {
        final accent = preferences.accentColor ?? AppTheme.seed.toARGB32();
        return SettingsSection(
          title: 'Appearance',
          icon: Icons.palette_outlined,
          children: [
            SettingsTile(
              title: 'Theme',
              below: ThemeChoice(
                value: preferences.themeMode,
                onChanged: (m) => preferences.themeMode = m,
              ),
            ),
            SettingsTile(
              title: 'Accent colour',
              subtitle: _accentNames[accent] ?? 'Custom',
              below: EvenGrid(
                itemExtent: 44,
                minItemExtent: 36,
                maxSpacing: Gaps.md,
                touchTargets: true,
                children: [
                  for (final c in Accents.all)
                    ColorDot(
                      color: c,
                      size: 40,
                      tooltip: _accentNames[c],
                      selected: c == accent,
                      onTap: () =>
                          preferences.accentColor = c == AppTheme.seed.toARGB32() ? null : c,
                    ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }
}
