import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../data/app_preferences.dart';
import '../../domain/preferences.dart';
import '../../ui/app_switch.dart';
import '../../ui/app_theme.dart';
import '../../ui/fit_segments.dart';
import '../../ui/roving_focus.dart';
import '../../ui/segment_label.dart';
import 'settings_section.dart';

/// Writing: whether a finger draws, the side button, and the writing
/// gestures (finger taps to undo and redo, hold to snap, scribble to
/// erase): this is their one home. Where the toolbar sits is set in the
/// editor (⋯ → View), where its effect shows.
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
                builder: (direction) => RovingSegments(
                  SegmentedButton<PenButtonAction>(
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
            ),
          _GestureTile(
            icon: Symbols.undo_sharp,
            title: 'Tap to undo and redo',
            subtitle: 'Two fingers undo, three redo',
            value: preferences.fingerTapUndo,
            onChanged: (v) => preferences.fingerTapUndo = v,
          ),
          _GestureTile(
            icon: Symbols.shape_line_sharp,
            title: 'Hold to snap',
            subtitle: 'Hold the pen still at the end of a stroke for a clean line or shape',
            value: preferences.holdToSnap,
            onChanged: (v) => preferences.holdToSnap = v,
          ),
          _GestureTile(
            icon: Symbols.ink_eraser_sharp,
            title: 'Scribble to erase',
            subtitle: 'Scribble quickly back and forth over ink to erase it',
            value: preferences.scribbleToErase,
            onChanged: (v) => preferences.scribbleToErase = v,
          ),
        ],
      ),
    );
  }
}

/// A writing gesture's switch row.
class _GestureTile extends StatelessWidget {
  const _GestureTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => SettingsTile(
    icon: icon,
    title: title,
    subtitle: subtitle,
    onTap: () => onChanged(!value),
    trailing: ExcludeFocus(
      // The row is the target and the focus stop.
      child: AppSwitch(padded: false, value: value, onChanged: onChanged),
    ),
  );
}
