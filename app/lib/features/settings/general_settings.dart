import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/app_preferences.dart';
import '../../domain/preferences.dart';
import '../../ui/app_theme.dart';
import '../../ui/fit_segments.dart';
import '../../ui/roving_focus.dart';
import '../../ui/segment_label.dart';
import 'keyboard_shortcuts.dart';
import 'settings_section.dart';

/// General: the theme (System, Light, Dark) and, where a keyboard is
/// likely (not a touch-first phone), the keyboard shortcuts.
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
            control: FitSegments(
              builder: (direction) => RovingSegments(
                SegmentedButton<ThemePreference>(
                  direction: direction,
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
          ),
          if (!Targets.touchFirst || MediaQuery.sizeOf(context).width >= Breakpoints.medium)
            SettingsTile(
              icon: Symbols.keyboard_rounded,
              title: 'Keyboard shortcuts',
              subtitle: 'Also ${modifierLabel()}+/ anywhere',
              trailing: Icon(
                Symbols.chevron_right_rounded,
                size: Glyphs.bar,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
              onTap: () => showKeyboardShortcuts(context),
            ),
        ],
      ),
    );
  }
}
