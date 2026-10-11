import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../data/app_preferences.dart';
import '../../domain/preferences.dart';
import 'settings_section.dart';

/// Stylus preferences: palm rejection, the side button and low-latency ink.
class StylusSettings extends StatelessWidget {
  const StylusSettings({super.key, required this.preferences});

  final AppPreferences preferences;

  /// Only Android has the front-buffered overlay.
  static bool get showLowLatencyInk => !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

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
            below: SegmentedButton<PenButtonAction>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                  value: PenButtonAction.eraser,
                  icon: icons ? const Icon(Icons.auto_fix_normal_outlined) : null,
                  label: const Text('Erases'),
                ),
                ButtonSegment(
                  value: PenButtonAction.lasso,
                  icon: icons ? const Icon(Icons.gesture_rounded) : null,
                  label: const Text('Selects'),
                ),
                ButtonSegment(
                  value: PenButtonAction.none,
                  icon: icons ? const Icon(Icons.block_rounded) : null,
                  label: const Text('Nothing'),
                ),
              ],
              selected: {preferences.penButtonAction},
              onSelectionChanged: (s) => preferences.penButtonAction = s.single,
            ),
          ),
          if (showLowLatencyInk)
            SettingsTile(
              icon: Icons.speed_rounded,
              title: 'Low-latency ink (experimental)',
              subtitle:
                  'Draws the tip of the pen stroke directly on the display, a frame or two '
                  'sooner. Turn off if you see flicker or doubled ink.',
              onTap: () => preferences.lowLatencyInk = !preferences.lowLatencyInk,
              trailing: Switch(
                value: preferences.lowLatencyInk,
                onChanged: (v) => preferences.lowLatencyInk = v,
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
