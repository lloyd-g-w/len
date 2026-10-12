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
    final scheme = Theme.of(context).colorScheme;
    return SettingsSection(
      title: 'About',
      children: [
        const _VersionTile(),
        SettingsTile(
          icon: Symbols.license_rounded,
          title: 'Open-source licences',
          trailing: Icon(
            Symbols.chevron_right_rounded,
            size: Glyphs.bar,
            color: scheme.onSurfaceVariant,
          ),
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

/// "Len `version`"; tapping it seven times opens the hidden Ink Lab (kept
/// in release builds: the user records real stylus input with it).
class _VersionTile extends StatefulWidget {
  const _VersionTile();

  static const int taps = 7;

  @override
  State<_VersionTile> createState() => _VersionTileState();
}

class _VersionTileState extends State<_VersionTile> {
  int _taps = 0;

  void _onTap() {
    if (++_taps < _VersionTile.taps) return;
    _taps = 0;
    showMessage(context, 'Ink Lab', duration: const Duration(seconds: 1));
    final prefs = context.getInheritedWidgetOfExactType<AppScope>()?.services.preferences;
    Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => InkLabScreen(stylusOnly: prefs?.stylusOnly ?? false)),
    );
  }

  @override
  Widget build(BuildContext context) => SettingsTile(
    icon: Symbols.info_rounded,
    title: 'Len ${AboutSettings.version}',
    subtitle: 'Handwriting-first notes with an infinite canvas and self-hosted sync',
    onTap: _onTap,
  );
}
