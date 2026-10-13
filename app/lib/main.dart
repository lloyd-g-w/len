import 'dart:async';

import 'package:flutter/material.dart';

import 'app.dart';
import 'app_services.dart';
import 'core/font_licenses.dart';
import 'data/app_database.dart';
import 'data/write_back.dart';
import 'ink/lab/perf_probe.dart';
import 'ink/render/stored_rasters.dart';
import 'platform/app_directory.dart';
import 'platform/blob_backend.dart';
import 'platform/browser_storage.dart';
import 'platform/incoming_files.dart';
import 'platform/outline_preparer.dart';
import 'platform/page_lifecycle.dart';
import 'platform/raster_store.dart';
import 'platform/secure_store.dart';
import 'platform/single_instance.dart';
import 'ui/open_elsewhere.dart';
import 'ui/startup_error.dart';

Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  registerFontLicenses();
  // Web: one tab at a time owns the database; another can take it over.
  final tabs = openTabHandover();
  if (tabs != null) {
    await tabs.claim(onWaiting: () => runApp(OpenElsewhereApp(handover: tabs)));
    // Handed over: start afresh, waiting for a turn again.
    tabs.onHandedOver = reloadTab;
  }
  // Web: ask the browser not to evict the IndexedDB data (where silent).
  unawaited(requestPersistentStorageOnStartup());
  await _start(args, tabs);
}

/// Opens the storage and runs the app; if the storage can't be opened, runs
/// [StartupErrorApp] instead (whose Try again calls this again).
Future<void> _start(List<String> args, TabHandover? tabs) async {
  String? dir;
  AppDatabase? database;
  final AppServices services;
  // Web: writes reach IndexedDB asynchronously.
  final writes = StorageWrites();
  tabs?.onHandOver = () => _handOver(writes);
  watchPageLifecycle(writes);
  try {
    // Natively: files in the app-support directory. Web: IndexedDB.
    dir = await appDataDirectory();
    database = await AppDatabase.openDefault(dir, writes: writes);
    final blobs = await openBlobBackend(dir, writes: writes);
    services = AppServices.create(
      database,
      blobBackend: blobs,
      // "Open with" / "Share to Len", command-line files, PWA file handler.
      incomingFiles: openIncomingFiles(args),
      // `len://sync?…` setup links (Android).
      incomingLinks: incomingLinks,
      // Outlines of loaded ink are built on worker isolates.
      outlines: createOutlinePreparer(),
      writes: writes,
      // Canvases far zoomed out reopen from stored rasters.
      rasterStore: await openRasterStore(format: StoredRasters.format),
      // The sync token: Android Keystore, Secret Service, DPAPI.
      secureStore: platformSecureStore(),
    );
  } on Object catch (error, stack) {
    debugPrint('Cannot open storage: $error\n$stack');
    try {
      database?.close();
    } on Object catch (_) {}
    runApp(
      StartupErrorApp(
        error: error,
        stack: stack,
        dataFolder: dir,
        onRetry: () => _start(args, tabs),
      ),
    );
    return;
  }
  // Sync starts once the token is read from the secure store (which may
  // ask to unlock a keyring, so the app doesn't wait for it).
  unawaited(services.sync.tokens.load().whenComplete(services.sync.start));
  if (PerfProbe.requested) PerfProbe.start();
  runApp(LenApp(services: services));
  // Throttled to once a day; deletes blobs unreferenced for a week.
  unawaited(services.blobGc.runIfDue());
}

/// Another tab asked for the data: stores everything and stops writing.
/// Completes with whether all of it is stored (then the other tab may take
/// over); if storage is failing, this tab keeps running and its changes.
Future<bool> _handOver(StorageWrites writes) async {
  if (!await writes.flush()) return false;
  return writes.close();
}
