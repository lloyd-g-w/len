part of 'sync_settings.dart';

/// The section's two views: connected (status and actions) and the form.
extension _SyncSettingsViews on _SyncSettingsState {
  Widget _connected(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SyncStatusLine(sync: _sync),
        Padding(
          padding: const EdgeInsetsDirectional.only(start: SyncStatusLine.iconColumn),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: Gaps.xxs),
              Text(
                _services.settings.syncUrl,
                style: theme.textTheme.bodySmall,
                overflow: TextOverflow.ellipsis,
              ),
              if (_tokenNote) ...[
                const SizedBox(height: Gaps.sm),
                Text(
                  'This device’s secure storage isn’t available right now, so the access '
                  'token is kept with Len’s data. Len moves it there once it can.',
                  style: theme.textTheme.bodySmall,
                ),
              ],
              const SizedBox(height: Gaps.md),
              _actions(context),
            ],
          ),
        ),
      ],
    );
  }

  Widget _actions(BuildContext context) => Wrap(
    spacing: Gaps.sm,
    runSpacing: Gaps.sm,
    // The server turned the token away: syncing again or sharing the token
    // can't help, changing it can.
    children: _sync.waitsForSettings
        ? [
            OutlinedButton(onPressed: _startEditing, child: const Text('Change…')),
            TextButton(onPressed: () => unawaited(_turnOff()), child: const Text('Turn off sync…')),
          ]
        : [
            OutlinedButton.icon(
              onPressed: _sync.state == SyncState.syncing ? null : () => unawaited(_sync.syncNow()),
              icon: const Icon(Symbols.sync_sharp, size: Glyphs.menu),
              label: const Text('Sync now'),
            ),
            TextButton(onPressed: _startEditing, child: const Text('Change…')),
            TextButton(
              onPressed: () => unawaited(
                showSyncSetupDialog(
                  context,
                  SyncSetupLink(url: _services.settings.syncUrl, token: _sync.tokens.token),
                ),
              ),
              child: const Text('Set up another device…'),
            ),
            TextButton(onPressed: () => unawaited(_turnOff()), child: const Text('Turn off sync…')),
          ],
  );

  Widget _form(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!_sync.isConfigured) ...[SyncStatusLine(sync: _sync), const SizedBox(height: Gaps.sm)],
        Padding(
          // Fields and buttons under the status's text, like a row's.
          padding: const EdgeInsetsDirectional.only(start: SyncStatusLine.iconColumn),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _fields(context)),
        ),
      ],
    );
  }

  List<Widget> _fields(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return [
      TextField(
        controller: _url,
        keyboardType: TextInputType.url,
        textInputAction: TextInputAction.next,
        autocorrect: false,
        onChanged: _onUrlChanged,
        decoration: InputDecoration(
          labelText: 'Server URL',
          hintText: 'len.example.com',
          helperText: _fromLink
              ? 'Filled from a setup link; next time, open Settings → Sync → '
                    'Set up another device… on a connected device'
              : 'Or paste a setup link from a connected device',
          helperMaxLines: 3,
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
        onChanged: _onTokenChanged,
        onSubmitted: (_) {
          if (!_busy) unawaited(_testAndSave());
        },
        decoration: InputDecoration(
          labelText: 'Access token',
          errorText: _tokenError,
          errorMaxLines: 3,
          suffixIcon: IconButton(
            tooltip: _obscureToken ? 'Show' : 'Hide',
            onPressed: _toggleObscureToken,
            icon: Icon(_obscureToken ? Symbols.visibility_sharp : Symbols.visibility_off_sharp),
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
          // What "your own Len server" is, and how to run one (R14-9).
          if (!_sync.isConfigured)
            TextButton(
              onPressed: () => unawaited(
                launchUrl(SyncSettings.serverGuide, mode: LaunchMode.externalApplication),
              ),
              child: const Text('How to run a server'),
            ),
        ],
      ),
    ];
  }
}
