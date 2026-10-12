import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/app_preferences.dart';
import '../../domain/preferences.dart';
import '../../ui/segment_label.dart';
import '../editor/pen/eraser_icon.dart';
import 'settings_section.dart';

/// Writing preferences: palm rejection, the side button, finger taps to
/// undo and redo, and where the editor's toolbar sits (also changeable
/// from the editor menu).
class WritingSettings extends StatelessWidget {
  const WritingSettings({super.key, required this.preferences});

  final AppPreferences preferences;

  @override
  Widget build(BuildContext context) {
    // Phones keep the segment labels readable by dropping their icons.
    final icons = MediaQuery.sizeOf(context).width >= 480;
    return ListenableBuilder(
      listenable: preferences,
      builder: (context, _) => SettingsSection(
        title: 'Writing',
        icon: Symbols.edit_rounded,
        children: [
          SettingsTile(
            icon: Symbols.back_hand_rounded,
            title: 'Only the stylus draws',
            subtitle:
                'Fingers pan and zoom, so a resting palm leaves no marks. Turns on by '
                'itself the first time a stylus touches the screen.',
            onTap: () => preferences.stylusOnly = !(preferences.stylusOnly ?? false),
            trailing: Switch(
              value: preferences.stylusOnly ?? false,
              onChanged: (v) => preferences.stylusOnly = v,
            ),
          ),
          SettingsTile(
            icon: Symbols.ads_click_rounded,
            title: 'Side button',
            subtitle: 'While you hold the S Pen (or stylus) button, the pen…',
            below: ShrinkToFit(
              child: SegmentedButton<PenButtonAction>(
                showSelectedIcon: false,
                segments: [
                  ButtonSegment(
                    value: PenButtonAction.eraser,
                    icon: icons ? const EraserIcon() : null,
                    label: const SegmentLabel('Erases'),
                  ),
                  ButtonSegment(
                    value: PenButtonAction.lasso,
                    icon: icons ? const Icon(Symbols.gesture_rounded) : null,
                    label: const SegmentLabel('Selects'),
                  ),
                  ButtonSegment(
                    value: PenButtonAction.none,
                    icon: icons ? const Icon(Symbols.block_rounded) : null,
                    label: const SegmentLabel('Nothing'),
                  ),
                ],
                selected: {preferences.penButtonAction},
                onSelectionChanged: (s) => preferences.penButtonAction = s.single,
              ),
            ),
          ),
          SettingsTile(
            icon: Symbols.undo_rounded,
            title: 'Finger taps to undo and redo',
            subtitle: 'Tap the page with two fingers to undo, with three to redo.',
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
