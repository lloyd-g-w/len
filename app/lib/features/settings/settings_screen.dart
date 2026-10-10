import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../ui/app_theme.dart';
import 'about_settings.dart';
import 'appearance_settings.dart';
import 'editor_settings.dart';
import 'input_settings.dart';
import 'sync_settings.dart';

/// Settings: appearance, stylus, gestures, editor, sync and about, as grouped cards in a
/// readable column.
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final preferences = AppScope.of(context).preferences;
    final compact = MediaQuery.sizeOf(context).width < Breakpoints.medium;
    final gutter = compact ? Gaps.lg : Gaps.xl;
    return Scaffold(
      appBar: AppBar(scrolledUnderElevation: 0.5),
      body: ListView(
        padding: EdgeInsets.fromLTRB(0, 0, 0, Gaps.xxl + MediaQuery.paddingOf(context).bottom),
        children: [
          Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              // Readable line length on wide desktop windows.
              constraints: const BoxConstraints(maxWidth: 680),
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: gutter),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.fromLTRB(Gaps.xs, 0, 0, Gaps.xl),
                      child: Text(
                        'Settings',
                        style: compact
                            ? Theme.of(context).textTheme.headlineMedium
                            : Theme.of(context).textTheme.headlineLarge,
                      ),
                    ),
                    AppearanceSettings(preferences: preferences),
                    InputSettings(preferences: preferences),
                    EditorSettings(preferences: preferences),
                    const SyncSettings(),
                    const AboutSettings(),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
