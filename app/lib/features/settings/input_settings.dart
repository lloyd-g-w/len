import 'package:flutter/material.dart';

import '../../data/app_preferences.dart';
import '../../domain/preferences.dart';
import '../../ui/segment_label.dart';
import '../editor/pen/eraser_icon.dart';
import 'settings_section.dart';

/// Stylus preferences: palm rejection and the side button.
class StylusSettings extends StatelessWidget {
  const StylusSettings({super.key, required this.preferences});

  final AppPreferences preferences;

  @override
  Widget build(BuildContext context) {
    // Phones keep the segment labels readable by dropping their icons.
    final icons = MediaQuery.sizeOf(context).width >= 480;
    return ListenableBuilder(
      listenable: preferences,
      builder: (context, _) => SettingsSection(
        title: 'Stylus',
        icon: Icons.edit_outlined,
        children: [
          SettingsTile(
            icon: Icons.back_hand_outlined,
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
            icon: Icons.ads_click_outlined,
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
                    icon: icons ? const Icon(Icons.gesture_rounded) : null,
                    label: const SegmentLabel('Selects'),
                  ),
                  ButtonSegment(
                    value: PenButtonAction.none,
                    icon: icons ? const Icon(Icons.block_rounded) : null,
                    label: const SegmentLabel('Nothing'),
                  ),
                ],
                selected: {preferences.penButtonAction},
                onSelectionChanged: (s) => preferences.penButtonAction = s.single,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Touch gesture preferences (undo/redo taps).
class GestureSettings extends StatelessWidget {
  const GestureSettings({super.key, required this.preferences});

  final AppPreferences preferences;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: preferences,
      builder: (context, _) => SettingsSection(
        title: 'Gestures',
        icon: Icons.touch_app_outlined,
        children: [
          SettingsTile(
            icon: Icons.undo_rounded,
            title: 'Two-finger tap to undo',
            subtitle: 'Tap the page with two fingers to undo the last change.',
            onTap: () => preferences.twoFingerTapUndo = !preferences.twoFingerTapUndo,
            trailing: Switch(
              value: preferences.twoFingerTapUndo,
              onChanged: (v) => preferences.twoFingerTapUndo = v,
            ),
          ),
          SettingsTile(
            icon: Icons.redo_rounded,
            title: 'Three-finger tap to redo',
            subtitle: 'Tap with three fingers to bring it back.',
            onTap: () => preferences.threeFingerTapRedo = !preferences.threeFingerTapRedo,
            trailing: Switch(
              value: preferences.threeFingerTapRedo,
              onChanged: (v) => preferences.threeFingerTapRedo = v,
            ),
          ),
        ],
      ),
    );
  }
}
