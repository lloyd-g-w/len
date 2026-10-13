import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import 'app_theme.dart';
import 'messages.dart';

/// The whole app when its storage could not be opened at startup (a
/// locked, corrupt or unwritable database, a full disk, a browser that
/// blocks storage): what happened, what to try, Copy details, Try again.
class StartupErrorApp extends StatelessWidget {
  const StartupErrorApp({
    super.key,
    required this.error,
    this.stack,
    this.dataFolder,
    required this.onRetry,
  });

  final Object error;
  final StackTrace? stack;

  /// Where Len keeps its data (shown on desktops, where people can look).
  final String? dataFolder;

  /// Tries opening the storage again; resolves when the attempt is over.
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Len',
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    debugShowCheckedModeBanner: false,
    home: StartupErrorScreen(error: error, stack: stack, dataFolder: dataFolder, onRetry: onRetry),
  );
}

/// The screen of [StartupErrorApp].
class StartupErrorScreen extends StatefulWidget {
  const StartupErrorScreen({
    super.key,
    required this.error,
    this.stack,
    this.dataFolder,
    required this.onRetry,
  });

  final Object error;
  final StackTrace? stack;
  final String? dataFolder;
  final Future<void> Function() onRetry;

  /// Whether the data folder is worth showing: on desktops people can open
  /// it (phones and browsers hide it).
  static bool get showsFolder =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.linux ||
          defaultTargetPlatform == TargetPlatform.windows ||
          defaultTargetPlatform == TargetPlatform.macOS);

  @override
  State<StartupErrorScreen> createState() => _StartupErrorScreenState();
}

class _StartupErrorScreenState extends State<StartupErrorScreen> {
  bool _retrying = false;

  String? get _folder => StartupErrorScreen.showsFolder ? widget.dataFolder : null;

  /// What to try, by platform.
  String get _advice => kIsWeb
      ? 'Close other Len tabs, and check that this browser allows sites to store data '
            '(private windows often don\'t). Then try again.'
      : 'Close any other Len window, and check that the device has free space. '
            'Then try again.';

  String get _details => [
    'Len could not open its storage.',
    if (widget.dataFolder case final folder?) 'Data folder: $folder',
    'Error: ${widget.error}',
    if (widget.stack case final stack?) '$stack',
  ].join('\n');

  Future<void> _copy() async {
    await Clipboard.setData(ClipboardData(text: _details));
    if (!mounted) return;
    showMessage(context, 'Details copied');
  }

  Future<void> _retry() async {
    setState(() => _retrying = true);
    try {
      await widget.onRetry();
    } finally {
      // Still shown when the attempt failed again (a new error replaces it).
      if (mounted) setState(() => _retrying = false);
    }
  }

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
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    Symbols.folder_off_sharp,
                    size: Glyphs.empty,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(height: Gaps.lg),
                  Text('Len couldn\'t open your notes', style: theme.textTheme.titleLarge),
                  const SizedBox(height: Gaps.sm),
                  Text(
                    'The place where Len keeps them couldn\'t be opened, so nothing was '
                    'loaded or changed. $_advice',
                    style: theme.textTheme.bodyMedium,
                  ),
                  if (_folder case final folder?) ...[
                    const SizedBox(height: Gaps.md),
                    SelectableText(folder, style: theme.textTheme.bodySmall),
                  ],
                  const SizedBox(height: Gaps.xl),
                  Wrap(
                    spacing: Gaps.sm,
                    runSpacing: Gaps.sm,
                    children: [
                      FilledButton(
                        onPressed: _retrying ? null : () => unawaited(_retry()),
                        child: const Text('Try again'),
                      ),
                      TextButton.icon(
                        onPressed: () => unawaited(_copy()),
                        icon: const Icon(Symbols.content_copy_sharp, size: Glyphs.menu),
                        label: const Text('Copy details'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
