import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

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

  /// Shown under the URL field until it is edited.
  String? _urlError;
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
        _urlError = urlError;
        _testMessage = null;
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
      description:
          'Keep your notebooks in sync across devices through your own Len server '
          '(self-hosted; it runs with Docker in a couple of minutes).',
      children: [
        Padding(
          padding: const EdgeInsets.all(Gaps.lg),
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
                onChanged: (_) {
                  if (_urlError != null) setState(() => _urlError = null);
                },
                decoration: InputDecoration(
                  labelText: 'Server URL',
                  hintText: 'https://len.example.com',
                  prefixIcon: const Icon(Symbols.dns_rounded),
                  errorText: _urlError,
                  errorMaxLines: 3,
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
                  prefixIcon: const Icon(Symbols.key_rounded),
                  suffixIcon: IconButton(
                    tooltip: _obscureToken ? 'Show' : 'Hide',
                    onPressed: () => setState(() => _obscureToken = !_obscureToken),
                    icon: Icon(
                      _obscureToken ? Symbols.visibility_rounded : Symbols.visibility_off_rounded,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: Gaps.lg),
              Wrap(
                spacing: Gaps.lg,
                runSpacing: Gaps.sm,
                crossAxisAlignment: WrapCrossAlignment.center,
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
                  ListenableBuilder(
                    listenable: _services.sync,
                    builder: (context, _) => _services.sync.isConfigured
                        ? OutlinedButton.icon(
                            onPressed: _services.sync.state == SyncState.syncing
                                ? null
                                : () => unawaited(_services.sync.syncNow()),
                            icon: const Icon(Symbols.sync_rounded, size: Glyphs.menu),
                            label: const Text('Sync now'),
                          )
                        : const SizedBox.shrink(),
                  ),
                  AnimatedSwitcher(
                    duration: Motion.medium,
                    child: _testMessage == null
                        ? const SizedBox()
                        : Text(
                            _testMessage!,
                            key: ValueKey(_testMessage),
                            style: TextStyle(color: _testOk ? scheme.primary : scheme.error),
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
          SyncState.disabled => (Symbols.cloud_off_rounded, scheme.onSurfaceVariant, 'Sync is off'),
          SyncState.syncing => (Symbols.cloud_sync_rounded, scheme.primary, 'Syncing…'),
          SyncState.error => (
            Symbols.error_rounded,
            scheme.error,
            'Last sync failed: ${sync.lastError}',
          ),
          SyncState.idle => (
            Symbols.cloud_done_rounded,
            scheme.primary,
            last == null ? 'Ready' : 'Last synced ${formatEdited(last.millisecondsSinceEpoch)}',
          ),
        };
        final status = Container(
          padding: const EdgeInsets.symmetric(horizontal: Gaps.md, vertical: Gaps.sm + 2),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            // A status chip, not a field.
            borderRadius: BorderRadius.circular(Radii.pill),
          ),
          child: Row(
            children: [
              Icon(icon, size: Glyphs.menu, color: color),
              const SizedBox(width: Gaps.sm),
              Expanded(child: Text(text, style: Theme.of(context).textTheme.bodyMedium)),
            ],
          ),
        );
        if (sync.state == SyncState.disabled || sync.tooLargeFiles.isEmpty) return status;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            status,
            const SizedBox(height: Gaps.sm),
            _TooLargeNotice(sync: sync),
          ],
        );
      },
    );
  }
}

/// Explains files the server refuses as too large, with a retry.
class _TooLargeNotice extends StatelessWidget {
  const _TooLargeNotice({required this.sync});

  final SyncController sync;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final files = sync.tooLargeFiles;
    final largest = files.map((f) => f.size).reduce((a, b) => a > b ? a : b);
    final limit = sync.serverMaxBlobBytes;
    return Container(
      padding: const EdgeInsets.fromLTRB(Gaps.md, Gaps.sm + 2, Gaps.sm, Gaps.sm),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(Radii.sm),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(Symbols.cloud_upload_rounded, size: Glyphs.menu, color: scheme.primary),
          ),
          const SizedBox(width: Gaps.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${sync.tooLargeSummary}.', style: theme.textTheme.bodyMedium),
                const SizedBox(height: 2),
                Text(
                  '${files.length == 1 ? 'It is' : 'The largest is'} ${formatBytes(largest)}; '
                  'the server accepts ${limit == null ? 'less' : 'up to ${formatBytes(limit)}'}. '
                  'It stays on this device and other devices show it as missing. '
                  'Raise LEN_BLOB_MAX_BYTES on the server (and the upload limit of any proxy), '
                  'then retry.',
                  style: theme.textTheme.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
          TextButton(
            onPressed: () => unawaited(sync.retryTooLargeFiles()),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }
}
