import 'package:flutter/material.dart';

import '../../core/format.dart';
import '../../platform/browser_storage_api.dart';
import '../../ui/messages.dart';
import 'settings_section.dart';

/// Web only: whether the browser keeps Len's data (persistent storage) and
/// how much of the site's quota it uses.
class StorageSettings extends StatefulWidget {
  const StorageSettings({super.key, required this.storage});

  final BrowserStorage storage;

  @override
  State<StorageSettings> createState() => _StorageSettingsState();
}

class _StorageSettingsState extends State<StorageSettings> {
  bool? _persisted;
  StorageUsage? _usage;
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final persisted = await widget.storage.isPersisted().catchError((Object _) => false);
    final usage = await widget.storage.usage();
    if (!mounted) return;
    setState(() {
      _persisted = persisted;
      _usage = usage;
    });
  }

  Future<void> _request() async {
    setState(() => _asking = true);
    final granted = await widget.storage.requestPersistence().catchError((Object _) => false);
    if (!mounted) return;
    setState(() => _asking = false);
    await _refresh();
    if (!mounted || granted) return;
    showMessage(
      context,
      'The browser declined. Installing Len as an app, or using it more often, usually helps',
    );
  }

  @override
  Widget build(BuildContext context) {
    final persisted = _persisted;
    return SettingsSection(
      title: 'Storage',
      icon: Icons.storage_outlined,
      description:
          'Your notebooks are stored in this browser. Browsers may clear site data when the '
          'device runs low on space, unless the site may keep its data. Clearing site data '
          'yourself still deletes it, so use sync for a backup.',
      children: [
        SettingsTile(
          icon: Icons.verified_user_outlined,
          title: 'Keep data on this device',
          subtitle: switch (persisted) {
            null => 'Checking…',
            true => 'On: the browser keeps Len\'s data until you clear it.',
            false => 'Off: the browser may clear Len\'s data when storage runs low.',
          },
          trailing: persisted == false
              ? FilledButton.tonal(
                  onPressed: _asking ? null : _request,
                  child: const Text('Turn on'),
                )
              : persisted == true
              ? Icon(Icons.check_circle_rounded, color: Theme.of(context).colorScheme.primary)
              : null,
        ),
        if (_usage case final usage?) _UsageTile(usage: usage),
      ],
    );
  }
}

class _UsageTile extends StatelessWidget {
  const _UsageTile({required this.usage});

  final StorageUsage usage;

  @override
  Widget build(BuildContext context) {
    final fraction = usage.quota <= 0 ? 0.0 : (usage.usage / usage.quota).clamp(0.0, 1.0);
    return SettingsTile(
      icon: Icons.pie_chart_outline_rounded,
      title: 'Space used',
      subtitle: '${formatBytes(usage.usage)} of ${formatBytes(usage.quota)} available to Len',
      below: LinearProgressIndicator(value: fraction),
    );
  }
}
