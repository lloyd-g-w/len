import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../platform/tab_handover.dart';
import 'app_theme.dart';

/// The whole app in a browser tab while Len is open in another tab: says
/// so, with "Use here", which asks the other tab to save and hand over.
class OpenElsewhereApp extends StatelessWidget {
  const OpenElsewhereApp({super.key, required this.handover});

  final TabHandover handover;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Len',
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    debugShowCheckedModeBanner: false,
    home: OpenElsewhereScreen(state: handover.state, onUseHere: handover.useHere),
  );
}

/// The screen of [OpenElsewhereApp].
class OpenElsewhereScreen extends StatelessWidget {
  const OpenElsewhereScreen({super.key, required this.state, required this.onUseHere});

  final ValueListenable<WaitState> state;
  final VoidCallback onUseHere;

  static String _explanation(WaitState state) => switch (state) {
    WaitState.waiting =>
      'Close it to continue here, or use Len here: the other tab saves your changes '
          'and steps aside.',
    WaitState.asking => 'Moving Len to this tab…',
    WaitState.refused =>
      'The other tab can’t save its latest changes because browser storage is full, '
          'so it keeps Len open. Free up space, then try again.',
    WaitState.noAnswer =>
      'The other tab isn’t answering. Switch to it, or close it to continue here.',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(Gaps.xl),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: ValueListenableBuilder(
                valueListenable: state,
                builder: (context, state, _) => Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Symbols.tab_rounded,
                      size: Glyphs.empty,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: Gaps.lg),
                    Text('Len is open in another tab', style: theme.textTheme.titleLarge),
                    const SizedBox(height: Gaps.sm),
                    Text(_explanation(state), style: theme.textTheme.bodyMedium),
                    const SizedBox(height: Gaps.xl),
                    if (state == WaitState.asking)
                      // A ruled progress line (DESIGN §6), where the button was.
                      const SizedBox(
                        width: 160,
                        height: Targets.bar,
                        child: Center(child: LinearProgressIndicator()),
                      )
                    else
                      FilledButton(
                        onPressed: onUseHere,
                        child: Text(state == WaitState.waiting ? 'Use here' : 'Try again'),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
