import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/app_preferences.dart';
import '../../ui/app_switch.dart';
import 'settings_section.dart';

/// Name tags: whether other devices' pointers carry the plate with their
/// device's initial (the editor's ⋯ → View → Name tags, in the same shape).
class NameTagsTile extends StatelessWidget {
  const NameTagsTile({super.key, required this.preferences});

  final AppPreferences preferences;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: preferences,
    builder: (context, _) => SettingsTile(
      icon: Symbols.badge_rounded,
      title: 'Name tags',
      subtitle: 'Show each device’s initial by its pen or laser while you write together',
      onTap: () => preferences.pointerTags = !preferences.pointerTags,
      trailing: ExcludeFocus(
        // The row is the target and the focus stop.
        child: AppSwitch(
          padded: false,
          value: preferences.pointerTags,
          onChanged: (v) => preferences.pointerTags = v,
        ),
      ),
    ),
  );
}
