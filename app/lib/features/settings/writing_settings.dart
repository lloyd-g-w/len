import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/app_preferences.dart';
import '../../domain/preferences.dart';
import '../../ui/app_switch.dart';
import '../../ui/app_theme.dart';
import '../../ui/fit_segments.dart';
import '../../ui/segment_label.dart';
import 'settings_section.dart';

/// Writing: whether a finger draws, the side button, finger taps
/// to undo and redo, and where the editor's toolbar sits (also changeable
/// from the editor menu).
class WritingSettings extends StatelessWidget {
  const WritingSettings({super.key, required this.preferences});

  final AppPreferences preferences;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: preferences,
      builder: (context, _) => SettingsSection(
        title: 'Writing',
        children: [
          // The editor menu's switch, in the same shape. Off until set, a
          // finger draws only until a stylus is first seen (then fingers
          // pan and zoom); with a mouse it shows once a stylus was.
          if (preferences.stylusOnly != null || Targets.touchFirst)
            SettingsTile(
              icon: Symbols.draw_sharp,
              title: 'Draw with finger',
              subtitle: switch (preferences.stylusOnly) {
                null => 'Until a stylus touches the screen; then fingers pan and zoom',
                true => 'Off: fingers pan and zoom, so a resting palm leaves no marks',
                false => 'One finger draws; two fingers pan and zoom',
              },
              onTap: () => preferences.stylusOnly = !(preferences.stylusOnly ?? false),
              trailing: ExcludeFocus(
                // The row is the target and the focus stop.
                child: AppSwitch(
                  padded: false,
                  value: !(preferences.stylusOnly ?? false),
                  onChanged: (v) => preferences.stylusOnly = !v,
                ),
              ),
            ),
          // Only where a stylus with a button is likely: Android (S Pen), or
          // where one was seen (or the user chose how fingers behave).
          if (defaultTargetPlatform == TargetPlatform.android || preferences.stylusOnly != null)
            SettingsTile(
              icon: Symbols.ads_click_sharp,
              title: 'Side button',
              subtitle: 'While you hold the S Pen (or stylus) button',
              control: FitSegments(
                builder: (direction) => SegmentedButton<PenButtonAction>(
                  direction: direction,
                  showSelectedIcon: false,
                  segments: const [
                    ButtonSegment(value: PenButtonAction.eraser, label: SegmentLabel('Erases')),
                    ButtonSegment(value: PenButtonAction.lasso, label: SegmentLabel('Selects')),
                    ButtonSegment(value: PenButtonAction.none, label: SegmentLabel('Nothing')),
                  ],
                  selected: {preferences.penButtonAction},
                  onSelectionChanged: (s) => preferences.penButtonAction = s.single,
                ),
              ),
            ),
          SettingsTile(
            icon: Symbols.undo_sharp,
            title: 'Tap to undo and redo',
            subtitle: 'Two fingers undo, three redo',
            onTap: () => preferences.fingerTapUndo = !preferences.fingerTapUndo,
            trailing: ExcludeFocus(
              // The row is the target and the focus stop.
              child: AppSwitch(
                padded: false,
                value: preferences.fingerTapUndo,
                onChanged: (v) => preferences.fingerTapUndo = v,
              ),
            ),
          ),
          SettingsTile(
            icon: Symbols.view_day_sharp,
            title: 'Toolbar',
            subtitle: switch (preferences.toolbarPlacement) {
              ToolbarPlacement.docked => 'Along the top; at the bottom on phones',
              ToolbarPlacement.floating => 'Floating; drag it anywhere by its grip',
            },
            control: FitSegments(
              builder: (direction) => SegmentedButton<ToolbarPlacement>(
                direction: direction,
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
