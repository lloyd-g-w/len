import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_services.dart';
import '../../core/format.dart';
import '../../sync/sync_api.dart';
import '../../sync/sync_controller.dart';
import '../../ui/app_theme.dart';
import 'settings_section.dart';

/// Sync server URL and token, with a connection test and live status.
class SyncSettings extends StatefulWidget {
  const SyncSettings({super.key});

  /// Null if [url] is empty (sync off) or a usable http(s) URL; otherwise
  /// a message explaining what is wrong.
  static String? validateUrl(String url) {
    if (url.isEmpty) return null;
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https')) || uri.host.isEmpty) {
      return 'Enter a full URL, e.g. https://len.example.com or http://192.168.1.10:8080';
    }
    return null;
  }

  @override
  State<SyncSettings> createState() => _SyncSettingsState();
}

class _SyncSettingsState extends State<SyncSettings> {
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

  Future<void> _testAndSave() async {
    final urlError = SyncSettings.validateUrl(_url.text.trim());
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
    final scheme = theme.colorScheme;
    return SettingsSection(
      title: 'Sync',
      icon: Icons.cloud_outlined,
      description:
          'Sync with your own Len server. See server/README.md to run one with Docker '
          'in a couple of minutes.',
      children: [
        Padding(
          padding: const EdgeInsets.all(Gaps.lg + 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SyncStatusLine(sync: _services.sync),
              const SizedBox(height: Gaps.lg),
              TextField(
                controller: _url,
                keyboardType: TextInputType.url,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                decoration: const InputDecoration(
                  labelText: 'Server URL',
                  hintText: 'https://len.example.com',
                  prefixIcon: Icon(Icons.dns_outlined),
                ),
              ),
              const SizedBox(height: Gaps.md),
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
                  prefixIcon: const Icon(Icons.key_outlined),
                  suffixIcon: IconButton(
                    tooltip: _obscureToken ? 'Show' : 'Hide',
                    onPressed: () => setState(() => _obscureToken = !_obscureToken),
                    icon: Icon(
                      _obscureToken ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Gaps.lg),
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
                  const SizedBox(width: Gaps.lg),
                  Expanded(
                    child: AnimatedSwitcher(
                      duration: Motion.medium,
                      child: _testMessage == null
                          ? const SizedBox()
                          : Text(
                              _testMessage!,
                              key: ValueKey(_testMessage),
                              style: TextStyle(color: _testOk ? scheme.primary : scheme.error),
                            ),
                    ),
                  ),
                ],
              ),
            ],
          ),
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
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: sync,
      builder: (context, _) {
        final last = sync.lastSuccess;
        final (icon, color, text) = switch (sync.state) {
          SyncState.disabled => (Icons.cloud_off_outlined, scheme.onSurfaceVariant, 'Sync is off.'),
          SyncState.syncing => (Icons.cloud_sync_outlined, scheme.primary, 'Syncing…'),
          SyncState.error => (
            Icons.error_outline_rounded,
            scheme.error,
            'Last sync failed: ${sync.lastError}',
          ),
          SyncState.idle => (
            Icons.cloud_done_outlined,
            scheme.primary,
            last == null ? 'Ready.' : 'Last synced ${formatEdited(last.millisecondsSinceEpoch)}.',
          ),
        };
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: Gaps.md, vertical: Gaps.sm + 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(Radii.sm),
          ),
          child: Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: Gaps.sm),
              Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
            ],
          ),
        );
      },
    );
  }
}
