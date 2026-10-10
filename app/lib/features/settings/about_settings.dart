import 'package:flutter/material.dart';

import '../../ui/app_theme.dart';
import 'settings_section.dart';

/// App name, version and licences.
class AboutSettings extends StatelessWidget {
  const AboutSettings({super.key});

  /// Keep in sync with `version` in pubspec.yaml.
  static const String version = '0.1.0';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    return SettingsSection(
      title: 'About',
      icon: Icons.info_outline_rounded,
      children: [
        Padding(
          padding: const EdgeInsets.all(Gaps.lg + 2),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Radii.control),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color.lerp(scheme.primary, Colors.white, 0.15)!, scheme.primary],
                  ),
                ),
                child: Icon(Icons.gesture_rounded, color: scheme.onPrimary, size: 28),
              ),
              const SizedBox(width: Gaps.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Len $version', style: theme.textTheme.titleMedium),
                    Text(
                      'Handwriting-first notes with an infinite canvas and self-hosted sync.',
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        SettingsTile(
          title: 'Open-source licences',
          trailing: Icon(Icons.chevron_right_rounded, color: scheme.onSurfaceVariant),
          onTap: () => showLicensePage(
            context: context,
            applicationName: 'Len',
            applicationVersion: version,
          ),
        ),
      ],
    );
  }
}
