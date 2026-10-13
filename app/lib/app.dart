import 'dart:async';

import 'package:flutter/material.dart';

import 'app_services.dart';
import 'data/blob_backend.dart';
import 'domain/preferences.dart';
import 'features/library/library_screen.dart';
import 'features/settings/sync_attention.dart';
import 'features/storage/storage_attention.dart';
import 'ui/app_theme.dart';
import 'ui/messages.dart';
import 'ui/phone_menus.dart';
import 'ui/system_bars.dart';

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
    _syncAttention;
    _storageAttention;
    if (widget.services.blobs.backend case final VolatileBlobBackend volatile) {
      volatile.onWrite = _warnFilesNotKept;
    }
  }

  final _messenger = GlobalKey<ScaffoldMessengerState>();
  final _navigator = GlobalKey<NavigatorState>();
  late final _syncAttention = SyncAttention(
    sync: widget.services.sync,
    messenger: _messenger,
    navigator: _navigator,
  );
  late final _storageAttention = StorageAttention(
    writes: widget.services.writes,
    messenger: _messenger,
  );

  /// The first file stored in a browser that refused storage: say right
  /// away that it won't be kept (the library shows a banner too).
  void _warnFilesNotKept() {
    final volatile = widget.services.blobs.backend as VolatileBlobBackend;
    volatile.onWrite = null;
    final context = _messenger.currentContext;
    if (context == null) return;
    _messenger.currentState?.showSnackBar(
      appSnackBar(
        context,
        'This browser won\'t keep this file once the tab is closed',
        duration: const Duration(seconds: 10),
      ),
    );
  }

  @override
  void dispose() {
    widget.services.pointerActivity.detach();
    _syncAttention.dispose();
    _storageAttention.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Sync when leaving the app (to upload) and when returning (to fetch).
    if (state == AppLifecycleState.resumed || state == AppLifecycleState.paused) {
      unawaited(widget.services.sync.syncInBackground());
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
            builder: (context, child) => SystemBars(child: PhoneMenus(child: child!)),
            scaffoldMessengerKey: _messenger,
            navigatorKey: _navigator,
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
