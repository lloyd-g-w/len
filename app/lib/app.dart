import 'dart:async';

import 'package:flutter/material.dart';

import 'app_services.dart';
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
    return AppScope(
      services: widget.services,
      child: MaterialApp(
        title: 'Len',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        darkTheme: AppTheme.dark(),
        home: const LibraryScreen(),
      ),
    );
  }
}
