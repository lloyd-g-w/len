import 'dart:io';

import 'package:flutter/widgets.dart';

import 'core/clock.dart';
import 'data/app_database.dart';
import 'data/app_preferences.dart';
import 'data/background_stroke_reader.dart';
import 'data/blob_store.dart';
import 'data/element_repository.dart';
import 'data/folder_repository.dart';
import 'data/notebook_repository.dart';
import 'data/page_repository.dart';
import 'data/search/search_service.dart';
import 'data/settings_repository.dart';
import 'data/stroke_reader.dart';
import 'data/stroke_repository.dart';
import 'ink/selection/ink_clipboard.dart';
import 'sync/sync_api.dart';
import 'sync/sync_controller.dart';
import 'sync/sync_engine.dart';

/// Composition root: constructs and owns the app's long-lived services.
class AppServices {
  AppServices._({
    required this.database,
    required this.settings,
    required this.preferences,
    required this.notebooks,
    required this.folders,
    required this.pages,
    required this.strokes,
    required this.strokeReader,
    required this.blobs,
    required this.elements,
    required this.sync,
    required this.search,
  });

  /// Wires up all services on [database]. [syncApiFactory] lets tests
  /// substitute the sync transport. Blob files (PDFs) are kept in
  /// [blobDirectory] (a temporary directory if omitted, e.g. in tests).
  factory AppServices.create(
    AppDatabase database, {
    Clock clock = const Clock(),
    Directory? blobDirectory,
    SyncApi Function(String url, String token)? syncApiFactory,
  }) {
    final settings = SettingsRepository(database);
    final deviceId = settings.deviceId(clock);
    final strokes = StrokeRepository(database, deviceId: deviceId, clock: clock);
    final elements = ElementRepository(database, deviceId: deviceId, clock: clock);
    final pages = PageRepository(database, deviceId: deviceId, clock: clock);
    final notebooks = NotebookRepository(
      database,
      deviceId: deviceId,
      pages: pages,
      strokes: strokes,
      elements: elements,
      clock: clock,
    );
    final folders = FolderRepository(database, deviceId: deviceId, clock: clock);
    final blobs = BlobStore(
      database,
      blobDirectory ?? Directory.systemTemp.createTempSync('len_blobs_'),
      clock: clock,
    );
    final engine = SyncEngine(
      database: database,
      settings: settings,
      notebooks: notebooks,
      pages: pages,
      strokes: strokes,
      folders: folders,
      blobs: blobs,
      elements: elements,
    );
    return AppServices._(
      database: database,
      settings: settings,
      preferences: AppPreferences(settings),
      notebooks: notebooks,
      folders: folders,
      pages: pages,
      strokes: strokes,
      strokeReader: switch (database.path) {
        final path? => BackgroundStrokeReader(path, fallback: strokes),
        null => strokes, // In-memory (tests): no second connection possible.
      },
      blobs: blobs,
      elements: elements,
      sync: syncApiFactory == null
          ? SyncController(engine: engine, settings: settings)
          : SyncController(engine: engine, settings: settings, apiFactory: syncApiFactory),
      search: SearchService(database, readBlob: blobs.read),
    );
  }

  final AppDatabase database;
  final SettingsRepository settings;

  /// Observable user preferences (theme, accent, input gestures, library view).
  final AppPreferences preferences;
  final NotebookRepository notebooks;
  final FolderRepository folders;
  final PageRepository pages;
  final StrokeRepository strokes;

  /// Reads strokes for lazy loading off the UI isolate when possible.
  final StrokeReader strokeReader;
  final BlobStore blobs;
  final ElementRepository elements;
  final SyncController sync;

  /// Full-text search over titles, text boxes and PDF text.
  final SearchService search;

  /// Copied strokes and text, shared by every editor (paste across pages
  /// and notebooks).
  final InkClipboard clipboard = InkClipboard();

  void dispose() {
    clipboard.dispose();
    search.dispose();
    sync.dispose();
    if (strokeReader case final BackgroundStrokeReader reader) reader.close();
    preferences.dispose();
    database.close();
  }
}

/// Makes [AppServices] available to the widget tree.
class AppScope extends InheritedWidget {
  const AppScope({super.key, required this.services, required super.child});

  final AppServices services;

  static AppServices of(BuildContext context) {
    final scope = context.dependOnInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope above this context');
    return scope!.services;
  }

  /// Like [of] but without subscribing; safe to call from `initState`.
  static AppServices read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope above this context');
    return scope!.services;
  }

  @override
  bool updateShouldNotify(AppScope old) => old.services != services;
}
