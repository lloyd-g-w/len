import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../app_services.dart';
import '../../ui/app_theme.dart';
import '../../ui/messages.dart';
import '../inklab/inklab_screen.dart';
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
      icon: Symbols.info_rounded,
      children: [
        Padding(
          padding: const EdgeInsets.all(Gaps.lg + 2),
          child: Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(Radii.sm),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color.lerp(scheme.primary, Colors.white, 0.15)!, scheme.primary],
                  ),
                ),
                child: Icon(Symbols.gesture_rounded, color: scheme.onPrimary, size: 28),
              ),
              const SizedBox(width: Gaps.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const _VersionText(),
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
          trailing: Icon(Symbols.chevron_right_rounded, color: scheme.onSurfaceVariant),
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

/// "Len `version`"; tapping it seven times opens the hidden Ink Lab.
class _VersionText extends StatefulWidget {
  const _VersionText();

  static const int taps = 7;

  @override
  State<_VersionText> createState() => _VersionTextState();
}

class _VersionTextState extends State<_VersionText> {
  int _taps = 0;

  void _onTap() {
    if (++_taps < _VersionText.taps) return;
    _taps = 0;
    showMessage(context, 'Ink Lab', duration: const Duration(seconds: 1));
    final prefs = context.getInheritedWidgetOfExactType<AppScope>()?.services.preferences;
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => InkLabScreen(stylusOnly: prefs?.stylusOnly ?? false)),
    );
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: _onTap,
    child: Text('Len ${AboutSettings.version}', style: Theme.of(context).textTheme.titleMedium),
  );
}
