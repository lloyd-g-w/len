import 'dart:async';

import 'package:flutter/material.dart';

import 'app_services.dart';
import 'domain/preferences.dart';
import 'features/library/library_screen.dart';
import 'ui/app_theme.dart';

class LenApp extends StatefulWidget {
  const LenApp({super.key, required this.services});

  final AppServices services;

  @override
  State<LenApp> createState() => _LenAppState();
}

class _LenAppState extends State<LenApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Sync when leaving the app (to upload) and when returning (to fetch).
    if (state == AppLifecycleState.resumed || state == AppLifecycleState.paused) {
      unawaited(widget.services.sync.syncNow());
    }
  }

  @override
  Widget build(BuildContext context) {
    final preferences = widget.services.preferences;
    return AppScope(
      services: widget.services,
      // Theme mode and accent colour rebuild the whole app when changed.
      child: ListenableBuilder(
        listenable: preferences,
        builder: (context, _) {
          final accent = Color(preferences.accentColor ?? AppTheme.seed.toARGB32());
          return MaterialApp(
            title: 'Len',
            debugShowCheckedModeBanner: false,
            theme: AppTheme.light(accent: accent),
            darkTheme: AppTheme.dark(accent: accent),
            themeMode: themeModeOf(preferences.themeMode),
            themeAnimationDuration: const Duration(milliseconds: 300),
            home: const LibraryScreen(),
          );
        },
      ),
    );
  }
}

/// Maps the stored preference to Flutter's [ThemeMode].
ThemeMode themeModeOf(ThemePreference preference) => switch (preference) {
  ThemePreference.system => ThemeMode.system,
  ThemePreference.light => ThemeMode.light,
  ThemePreference.dark => ThemeMode.dark,
};
