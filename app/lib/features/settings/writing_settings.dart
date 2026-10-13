import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/app_preferences.dart';
import '../../domain/preferences.dart';
import '../../ui/segment_label.dart';
import 'settings_section.dart';

/// Writing: what draws (stylus and fingers), the side button, finger taps
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
          SettingsTile(
            icon: Symbols.stylus_rounded,
            title: 'Draw with',
            subtitle: switch (preferences.stylusOnly) {
              null => 'Fingers draw until a stylus touches the screen; then they pan and zoom',
              true => 'Fingers pan and zoom, so a resting palm leaves no marks',
              false => 'Both draw; two fingers pan and zoom',
            },
            // "Draw with: Automatic / Stylus / Both", short enough to trail.
            control: ShrinkToFit(
              child: SegmentedButton<bool?>(
                showSelectedIcon: false,
                segments: const [
                  ButtonSegment(value: null, label: SegmentLabel('Automatic')),
                  ButtonSegment(value: true, label: SegmentLabel('Stylus')),
                  ButtonSegment(value: false, label: SegmentLabel('Both')),
                ],
                selected: {preferences.stylusOnly},
                onSelectionChanged: (s) => preferences.stylusOnly = s.single,
              ),
            ),
          ),
          SettingsTile(
            icon: Symbols.ads_click_rounded,
            title: 'Side button',
            subtitle: 'While you hold the S Pen (or stylus) button',
            control: ShrinkToFit(
              child: SegmentedButton<PenButtonAction>(
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
            icon: Symbols.undo_rounded,
            title: 'Tap to undo and redo',
            subtitle: 'Two fingers undo, three redo',
            onTap: () => preferences.fingerTapUndo = !preferences.fingerTapUndo,
            trailing: Switch(
              value: preferences.fingerTapUndo,
              onChanged: (v) => preferences.fingerTapUndo = v,
            ),
          ),
          SettingsTile(
            icon: Symbols.view_day_rounded,
            title: 'Toolbar',
            subtitle: switch (preferences.toolbarPlacement) {
              ToolbarPlacement.docked => 'Along the top; at the bottom on phones',
              ToolbarPlacement.floating => 'Floating; drag it anywhere by its grip',
            },
            control: ShrinkToFit(
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
