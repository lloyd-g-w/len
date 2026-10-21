import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../sync/device_name.dart';
import '../../ui/app_theme.dart';
import '../../ui/text_prompt.dart';
import 'settings_section.dart';

/// Device name: what this device is called on the user's other devices
/// (presence plates, name tags) and in version history; tapped, renamed
/// (an empty name goes back to the suggested one).
class DeviceNameTile extends StatelessWidget {
  const DeviceNameTile({super.key, required this.name});

  final DeviceName name;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: name,
    builder: (context, _) => SettingsTile(
      icon: Symbols.devices_sharp,
      title: 'Device name',
      subtitle: name.value,
      onTap: () => unawaited(_rename(context)),
      trailing: Icon(
        Symbols.edit_sharp,
        size: Glyphs.menu,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    ),
  );

  Future<void> _rename(BuildContext context) async {
    final value = await showTextPrompt(
      context,
      title: 'Name this device',
      initialValue: name.value,
      label: 'Name',
      helper:
          'Shown on your other devices and in version history; '
          'leave it empty for “${name.suggested}”',
      maxLength: DeviceName.maxLength,
      confirmLabel: 'Rename',
      allowEmpty: true,
    );
    if (value != null) name.rename(value);
  }
}
