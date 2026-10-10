import 'dart:async';

import 'package:flutter/material.dart';

import 'app_services.dart';
import 'domain/preferences.dart';
import 'features/library/library_screen.dart';
import 'ui/app_theme.dart';

/// The root widget: provides [AppServices] and builds the themed app.
class LenApp extends StatefulWidget {
  const LenApp({super.key, required this.services});

  final AppServices services;

  @override
  State<LenApp> createState() => _LenAppState();
}

class _LenAppState extends State<LenApp> with WidgetsBindingObserver {
  /// Themes for the current accent. Building a [ThemeData] is costly, and a
  /// new instance makes every widget that reads the theme rebuild, so they
  /// are only rebuilt when the accent changes — not on every preference
  /// change (library layout, sort, stylus-only, …).
  ({int accent, ThemeData light, ThemeData dark})? _themes;

  ({ThemeData light, ThemeData dark}) _themesFor(int accent) {
    final cached = _themes;
    if (cached != null && cached.accent == accent) return (light: cached.light, dark: cached.dark);
    final color = Color(accent);
    final themes = (
      accent: accent,
      light: AppTheme.light(accent: color),
      dark: AppTheme.dark(accent: color),
    );
    _themes = themes;
    return (light: themes.light, dark: themes.dark);
  }

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
          final themes = _themesFor(preferences.accentColor ?? AppTheme.seed.toARGB32());
          return MaterialApp(
            title: 'Len',
            debugShowCheckedModeBanner: false,
            theme: themes.light,
            darkTheme: themes.dark,
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
