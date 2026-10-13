import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../app_services.dart';
import '../../sync/sync_api.dart';
import '../../sync/sync_controller.dart';
import '../../ui/app_dialogs.dart';
import '../../ui/app_theme.dart';
import 'settings_section.dart';
import 'sync_status_line.dart';

/// Sync: once connected the server, its status, Sync now, Change… and Turn
/// off sync…; otherwise (or while changing) the URL and token form, with a
/// connection test.
class SyncSettings extends StatefulWidget {
  const SyncSettings({super.key, this.reveal = false});

  /// Scrolls itself into view once shown (Settings opened from a failed
  /// sync status).
  final bool reveal;

  /// [url] as typed, completed: trimmed, and `https://` assumed when no
  /// scheme is given ("len.example" → "https://len.example").
  static String completeUrl(String url) {
    final trimmed = url.trim();
    if (trimmed.isEmpty || trimmed.contains('://')) return trimmed;
    return 'https://$trimmed';
  }

  /// Null if [url] is a usable http(s) URL; otherwise a message explaining
  /// what is wrong.
  static String? validateUrl(String url) {
    if (url.isEmpty) return 'Enter the address of your Len server';
    final uri = Uri.tryParse(url);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https')) || uri.host.isEmpty) {
      return 'Enter a web address, e.g. len.example.com or http://192.168.1.10:8080';
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

  /// The form is shown although sync is set up (Change…).
  bool _editing = false;

  /// The last connection test's failure, under the form.
  String? _testError;

  /// Shown under the URL field until it is edited.
  String? _urlError;

  SyncController get _sync => _services.sync;

  @override
  void initState() {
    super.initState();
    if (!widget.reveal) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(Scrollable.ensureVisible(context, duration: Motion.travel, curve: Motion.move));
    });
  }

  @override
  void dispose() {
    _url.dispose();
    _token.dispose();
    super.dispose();
  }

  Future<void> _testAndSave() async {
    final url = SyncSettings.completeUrl(_url.text);
    // Show what is used ("https://" added).
    if (url != _url.text) _url.text = url;
    final urlError = SyncSettings.validateUrl(url);
    if (urlError != null) {
      setState(() {
        _urlError = urlError;
        _testError = null;
      });
      return;
    }
    setState(() {
      _busy = true;
      _testError = null;
    });
    try {
      await _sync.test(url: url, token: _token.text);
      _sync.configure(url: url, token: _token.text);
      _editing = false;
      unawaited(_sync.syncNow());
    } on SyncException catch (e) {
      _testError = e.message;
    } on ArgumentError {
      // e.g. the http client rejecting a malformed URI.
      _urlError = 'This address isn\'t valid';
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _turnOff() async {
    final confirmed = await confirmAction(
      context,
      title: 'Turn off sync?',
      message:
          'Your notebooks stay on this device and on the server. This device stops '
          'syncing until you connect it again.',
      confirmLabel: 'Turn off',
    );
    if (!confirmed || !mounted) return;
    _sync.configure(url: '', token: '');
    setState(() {
      _url.clear();
      _token.clear();
      _editing = false;
      _testError = null;
    });
  }

  void _cancelEditing() => setState(() {
    _url.text = _services.settings.syncUrl;
    _token.text = _services.settings.syncToken;
    _editing = false;
    _testError = _urlError = null;
  });

  @override
  Widget build(BuildContext context) {
    return SettingsSection(
      title: 'Sync',
      description: 'Sync across your devices through your own Len server',
      children: [
        ListenableBuilder(
          listenable: _sync,
          builder: (context, _) => Padding(
            padding: const EdgeInsets.all(Gaps.lg),
            child: _sync.isConfigured && !_editing ? _connected(context) : _form(context),
          ),
        ),
      ],
    );
  }

  Widget _connected(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SyncStatusLine(sync: _sync),
        const SizedBox(height: Gaps.md),
        Row(
          children: [
            SizedBox(
              width: Targets.touch,
              child: Icon(
                Symbols.dns_rounded,
                size: Glyphs.bar,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            Expanded(
              child: Text(
                _services.settings.syncUrl,
                style: theme.textTheme.bodyMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
        const SizedBox(height: Gaps.md),
        Wrap(
          spacing: Gaps.sm,
          runSpacing: Gaps.sm,
          children: [
            FilledButton.tonalIcon(
              onPressed: _sync.state == SyncState.syncing ? null : () => unawaited(_sync.syncNow()),
              icon: const Icon(Symbols.sync_rounded, size: Glyphs.menu),
              label: const Text('Sync now'),
            ),
            TextButton(
              onPressed: () => setState(() => _editing = true),
              child: const Text('Change…'),
            ),
            TextButton(onPressed: () => unawaited(_turnOff()), child: const Text('Turn off sync…')),
          ],
        ),
      ],
    );
  }

  Widget _form(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_sync.isConfigured) ...[SyncStatusLine(sync: _sync), const SizedBox(height: Gaps.md)],
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
            hintText: 'len.example.com',
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
        if (_testError case final error?) ...[
          const SizedBox(height: Gaps.md),
          Text(error, style: TextStyle(color: scheme.error)),
        ],
        const SizedBox(height: Gaps.lg),
        Wrap(
          spacing: Gaps.sm,
          runSpacing: Gaps.sm,
          children: [
            FilledButton(
              onPressed: _busy ? null : _testAndSave,
              child: _busy
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Connect'),
            ),
            if (_editing) TextButton(onPressed: _cancelEditing, child: const Text('Cancel')),
          ],
        ),
      ],
    );
  }
}
