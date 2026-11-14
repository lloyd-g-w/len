import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../sync/browser_signin.dart';
import '../../ui/app_dialogs.dart';
import '../../ui/app_theme.dart';

/// "Sign in with browser": waits while the user signs in to the server's
/// sign-in page of [signin], which [open] opens (at once, and on "Open
/// page again"), for its answer from [answers] (the
/// loopback listener's redirects, `len://signin` links) or pasted here
/// (the page shows its code; the only way in a browser). The answer, or
/// null if the user gave up.
Future<SigninAnswer?> showBrowserSigninDialog(
  BuildContext context, {
  required BrowserSignin signin,
  required List<Stream<String>> answers,
  required VoidCallback open,
}) => showDialog<SigninAnswer>(
  context: context,
  barrierDismissible: false,
  builder: (context) => _BrowserSigninDialog(signin: signin, answers: answers, open: open),
);

class _BrowserSigninDialog extends StatefulWidget {
  const _BrowserSigninDialog({required this.signin, required this.answers, required this.open});

  final BrowserSignin signin;
  final List<Stream<String>> answers;
  final VoidCallback open;

  @override
  State<_BrowserSigninDialog> createState() => _BrowserSigninDialogState();
}

class _BrowserSigninDialogState extends State<_BrowserSigninDialog> {
  final _code = TextEditingController();
  final _subscriptions = <StreamSubscription<String>>[];
  String? _error;

  @override
  void initState() {
    super.initState();
    for (final stream in widget.answers) {
      _subscriptions.add(stream.listen(_heard));
    }
    // Only now: an answer can't arrive before anyone listens.
    widget.open();
  }

  @override
  void dispose() {
    for (final s in _subscriptions) {
      unawaited(s.cancel());
    }
    _code.dispose();
    super.dispose();
  }

  /// A link from the page: ends the dialog if it answers this sign-in.
  void _heard(String link) {
    final answer = widget.signin.answerFrom(link);
    if (answer != null && mounted) Navigator.pop(context, answer);
  }

  void _submit() {
    final answer = widget.signin.answerFrom(_code.text);
    if (answer == null) {
      return setState(() => _error = 'This isn’t the code the sign-in page shows — copy it again');
    }
    Navigator.pop(context, answer);
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final pasteOnly = widget.signin.returnTo == SigninReturn.code;
    return AppDialog(
      title: 'Sign in with browser',
      scrollable: true,
      content: DialogBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              pasteOnly
                  ? 'Sign in on the page that opened and allow Len, then paste the code it '
                        'shows here'
                  : 'Sign in on the page that opened in your browser and allow Len: it '
                        'continues here by itself',
              style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: Gaps.lg),
            TextField(
              controller: _code,
              autocorrect: false,
              enableSuggestions: false,
              autofocus: pasteOnly,
              onChanged: (_) {
                if (_error != null) setState(() => _error = null);
              },
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                labelText: 'Code from the page',
                helperText: pasteOnly ? null : 'Only if Len doesn’t continue by itself',
                errorText: _error,
                errorMaxLines: 3,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton.icon(
          onPressed: widget.open,
          icon: const Icon(Symbols.open_in_new_rounded, size: Glyphs.menu),
          label: const Text('Open page again'),
        ),
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _submit, child: const Text('Continue')),
      ],
    );
  }
}
