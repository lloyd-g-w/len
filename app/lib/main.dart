import 'dart:async';

import 'package:flutter/material.dart';

import 'app.dart';
import 'app_services.dart';
import 'core/font_licenses.dart';
import 'data/app_database.dart';
import 'ink/lab/perf_probe.dart';
import 'ink/render/stored_rasters.dart';
import 'platform/app_directory.dart';
import 'platform/blob_backend.dart';
import 'platform/browser_storage.dart';
import 'platform/incoming_files.dart';
import 'platform/outline_preparer.dart';
import 'platform/raster_store.dart';
import 'platform/single_instance.dart';
import 'ui/app_theme.dart';
import 'ui/startup_error.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicenses();
  // Web: one tab at a time owns the database.
  await claimSingleInstance(onWaiting: () => runApp(const _OpenElsewhere()));
  // Web: ask the browser not to evict the IndexedDB data (where silent).
  unawaited(requestPersistentStorageOnStartup());
  await _start(args);
}

/// Opens the storage and runs the app; if the storage can't be opened, runs
/// [StartupErrorApp] instead (whose Try again calls this again).
Future<void> _start(List<String> args) async {
  String? dir;
  AppDatabase? database;
  final AppServices services;
  try {
    // Natively: files in the app-support directory. Web: IndexedDB.
    dir = await appDataDirectory();
    database = await AppDatabase.openDefault(dir);
    final blobs = await openBlobBackend(dir);
    services = AppServices.create(
      database,
      blobBackend: blobs,
      // "Open with" / "Share to Len", command-line files, PWA file handler.
      incomingFiles: openIncomingFiles(args),
      // Outlines of loaded ink are built on worker isolates.
      outlines: createOutlinePreparer(),
      // Canvases far zoomed out reopen from stored rasters.
      rasterStore: await openRasterStore(format: StoredRasters.format),
    );
  } on Object catch (error, stack) {
    debugPrint('Cannot open storage: $error\n$stack');
    try {
      database?.close();
    } on Object catch (_) {}
    runApp(
      StartupErrorApp(error: error, stack: stack, dataFolder: dir, onRetry: () => _start(args)),
    );
    return;
  }
  services.sync.start();
  if (PerfProbe.requested) PerfProbe.start();
  runApp(LenApp(services: services));
  // Throttled to once a day; deletes blobs unreferenced for a week.
  unawaited(services.blobGc.runIfDue());
}

/// Shown in a browser tab while Len is open in another tab.
class _OpenElsewhere extends StatelessWidget {
  const _OpenElsewhere();

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Len',
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    debugShowCheckedModeBanner: false,
    home: const Scaffold(
      body: Center(
        child: Padding(
          padding: EdgeInsets.all(Gaps.lg),
          child: Text(
            'Len is open in another tab.\nClose it to continue here.',
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ),
  );
}
