import 'package:flutter/material.dart';

import '../../data/app_preferences.dart';
import '../../domain/preferences.dart';
import 'settings_section.dart';

/// Stylus and touch gesture preferences.
class InputSettings extends StatelessWidget {
  const InputSettings({super.key, required this.preferences});

  final AppPreferences preferences;

  static String _label(PenButtonAction a) => switch (a) {
    PenButtonAction.eraser => 'Eraser',
    PenButtonAction.lasso => 'Lasso',
    PenButtonAction.none => 'Nothing',
  };

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: preferences,
      builder: (context, _) => SettingsSection(
        title: 'Input',
        icon: Icons.edit_outlined,
        children: [
          SettingsTile(
            title: 'Stylus only',
            subtitle:
                'Only the stylus draws; fingers pan and zoom. Turns on automatically '
                'the first time a stylus is used.',
            onTap: () => preferences.stylusOnly = !(preferences.stylusOnly ?? false),
            trailing: Switch(
              value: preferences.stylusOnly ?? false,
              onChanged: (v) => preferences.stylusOnly = v,
            ),
          ),
          SettingsTile(
            title: 'Two-finger tap to undo',
            onTap: () => preferences.twoFingerTapUndo = !preferences.twoFingerTapUndo,
            trailing: Switch(
              value: preferences.twoFingerTapUndo,
              onChanged: (v) => preferences.twoFingerTapUndo = v,
            ),
          ),
          SettingsTile(
            title: 'Three-finger tap to redo',
            onTap: () => preferences.threeFingerTapRedo = !preferences.threeFingerTapRedo,
            trailing: Switch(
              value: preferences.threeFingerTapRedo,
              onChanged: (v) => preferences.threeFingerTapRedo = v,
            ),
          ),
          SettingsTile(
            title: 'Stylus button',
            subtitle: 'What holding the S Pen (or stylus) side button does.',
            trailing: DropdownButton<PenButtonAction>(
              value: preferences.penButtonAction,
              underline: const SizedBox(),
              borderRadius: BorderRadius.circular(12),
              items: [
                for (final a in PenButtonAction.values)
                  DropdownMenuItem(value: a, child: Text(_label(a))),
              ],
              onChanged: (a) {
                if (a != null) preferences.penButtonAction = a;
              },
            ),
          ),
        ],
      ),
    );
  }
}
