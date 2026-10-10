import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../core/format.dart';
import '../../data/settings_repository.dart';
import '../../sync/sync_api.dart';
import '../../sync/sync_controller.dart';

/// Sync server configuration and input preferences.
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  late final AppServices _services = AppScope.read(context);
  late final _url = TextEditingController(text: _services.settings.syncUrl);
  late final _token = TextEditingController(text: _services.settings.syncToken);
  bool _obscureToken = true;
  bool _busy = false;
  String? _testMessage;
  bool _testOk = false;

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  /// Null if [url] is empty (sync off) or a usable http(s) URL; otherwise
  /// a message explaining what is wrong.
  static String? _validateUrl(String url) {
    if (url.isEmpty) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https')) || uri.host.isEmpty) {
      return 'Enter a full URL, e.g. https://len.example.com or http://192.168.1.10:8080';
    }
    return null;
  }

  Future<void> _testAndSave() async {
    final urlError = _validateUrl(_url.text.trim());
    if (urlError != null) {
      setState(() {
        _testOk = false;
        _testMessage = urlError;
      });
      return;
    }
    setState(() {
      _busy = true;
      _testMessage = null;
    });
    final sync = _services.sync;
    try {
      if (_url.text.trim().isNotEmpty) {
        await sync.test(url: _url.text, token: _token.text);
      }
      sync.configure(url: _url.text, token: _token.text);
      _testOk = true;
      _testMessage = sync.isConfigured ? 'Connected. Syncing…' : 'Sync turned off.';
      unawaited(sync.syncNow());
    } on SyncException catch (e) {
      _testOk = false;
      _testMessage = e.message;
    } on ArgumentError catch (e) {
      // e.g. the http client rejecting a malformed URI.
      _testOk = false;
      _testMessage = 'Invalid server URL: ${e.message}';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final settings = _services.settings;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Align(
        alignment: Alignment.topCenter,
        // Readable line length on wide desktop windows.
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: _buildForm(theme, settings),
        ),
      ),
    );
  }

  Widget _buildForm(ThemeData theme, SettingsRepository settings) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
      children: [
        Text('Sync', style: theme.textTheme.titleMedium),
        const SizedBox(height: 4),
        Text(
          'Sync with your own Len server. See server/README.md to run one '
          'with Docker in a couple of minutes.',
          style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _url,
          keyboardType: TextInputType.url,
          textInputAction: TextInputAction.next,
          autocorrect: false,
          decoration: const InputDecoration(
            labelText: 'Server URL',
            hintText: 'https://len.example.com',
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _token,
          obscureText: _obscureToken,
          autocorrect: false,
          enableSuggestions: false,
          onSubmitted: (_) {
            if (!_busy) unawaited(_testAndSave());
          },
          decoration: InputDecoration(
            labelText: 'Access token',
            suffixIcon: IconButton(
              tooltip: _obscureToken ? 'Show' : 'Hide',
              onPressed: () => setState(() => _obscureToken = !_obscureToken),
              icon: Icon(_obscureToken ? Icons.visibility_outlined : Icons.visibility_off_outlined),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            FilledButton(
              onPressed: _busy ? null : _testAndSave,
              child: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Connect & save'),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _testMessage == null
                  ? const SizedBox()
                  : Text(
                      _testMessage!,
                      style: TextStyle(
                        color: _testOk ? theme.colorScheme.primary : theme.colorScheme.error,
                      ),
                    ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        _SyncStatusLine(sync: _services.sync),
        const Divider(height: 48),
        Text('Input', style: theme.textTheme.titleMedium),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: const Text('Stylus only'),
          subtitle: const Text(
            'Only the stylus draws; fingers pan and zoom. Turns on '
            'automatically the first time a stylus is used.',
          ),
          value: settings.stylusOnly ?? false,
          onChanged: (v) => setState(() => settings.stylusOnly = v),
        ),
      ],
    );
  }
}

class _SyncStatusLine extends StatelessWidget {
  const _SyncStatusLine({required this.sync});

  final SyncController sync;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        final last = sync.lastSuccess;
        final text = switch (sync.state) {
          SyncState.disabled => 'Sync is off.',
          SyncState.syncing => 'Syncing…',
          SyncState.error => 'Last sync failed: ${sync.lastError}',
          SyncState.idle =>
            last == null ? 'Ready.' : 'Last synced ${formatEdited(last.millisecondsSinceEpoch)}.',
        };
        return Text(text, style: Theme.of(context).textTheme.bodySmall);
      },
    );
  }
}
