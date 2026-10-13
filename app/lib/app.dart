import 'dart:async';

import 'package:flutter/material.dart';

import 'app_services.dart';
import 'domain/preferences.dart';
import 'features/library/library_screen.dart';
import 'ui/app_theme.dart';
import 'ui/system_bars.dart';
import 'ui/touch_menus.dart';

/// The root widget: provides [AppServices] and builds the themed app.
class LenApp extends StatefulWidget {
  const LenApp({super.key, required this.services});

  final AppServices services;

  @override
  State<LenApp> createState() => _LenAppState();
}

class _LenAppState extends State<LenApp> with WidgetsBindingObserver {
  /// The themes, built once: building a [ThemeData] is costly, and a new
  /// instance makes every widget that reads the theme rebuild.
  final ThemeData _light = AppTheme.light();
  final ThemeData _dark = AppTheme.dark();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.services.pointerActivity.attach();
  }

  @override
  void dispose() {
    widget.services.pointerActivity.detach();
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
      // The theme mode rebuilds the whole app when changed.
      child: ListenableBuilder(
        listenable: preferences,
        builder: (context, _) {
          return MaterialApp(
            title: 'Len',
            debugShowCheckedModeBanner: false,
            theme: _light,
            darkTheme: _dark,
            themeMode: themeModeOf(preferences.themeMode),
            themeAnimationDuration: Motion.medium,
            builder: (context, child) => SystemBars(child: TouchMenus(child: child!)),
            navigatorObservers: [widget.services.routeOwners],
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
