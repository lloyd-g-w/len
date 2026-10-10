import 'dart:async';

import 'package:flutter/widgets.dart';

import 'core/clock.dart';
import 'data/app_database.dart';
import 'data/app_preferences.dart';
import 'data/blob_backend.dart';
import 'data/blob_store.dart';
import 'data/element_repository.dart';
import 'data/folder_repository.dart';
import 'data/notebook_repository.dart';
import 'data/page_repository.dart';
import 'data/recording_repository.dart';
import 'data/search/search_service.dart';
import 'data/settings_repository.dart';
import 'data/stroke_reader.dart';
import 'data/stroke_repository.dart';
import 'features/audio/backends/audio_backends.dart';
import 'features/audio/backends/platform_audio.dart';
import 'features/editor/tabs/open_notebooks.dart';
import 'ink/images/element_images.dart';
import 'ink/recognition/handwriting_recognizer.dart';
import 'ink/recognition/recognition_service.dart';
import 'ink/selection/ink_clipboard.dart';
import 'platform/handwriting_recognizer.dart';
import 'platform/stroke_reader.dart';
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
    required this.recognition,
    required this.recordings,
    required this.audio,
  });

  /// Wires up all services on [database]. [syncApiFactory] lets tests
  /// substitute the sync transport. Blobs (PDFs) are kept in [blobBackend]
  /// (in memory if omitted, e.g. in tests). [audio] replaces the
  /// recorder and player (tests use fakes).
  factory AppServices.create(
    AppDatabase database, {
    Clock clock = const Clock(),
    BlobBackend? blobBackend,
    AudioBackends? audio,
    SyncApi Function(String url, String token)? syncApiFactory,
    HandwritingRecognizer? recognizer,
  }) {
    final settings = SettingsRepository(database);
    final deviceId = settings.deviceId(clock);
    final strokes = StrokeRepository(database, deviceId: deviceId, clock: clock);
    final elements = ElementRepository(database, deviceId: deviceId, clock: clock);
    final recordings = RecordingRepository(database, deviceId: deviceId, clock: clock);
    final pages = PageRepository(database, deviceId: deviceId, clock: clock);
    final notebooks = NotebookRepository(
      database,
      deviceId: deviceId,
      pages: pages,
      strokes: strokes,
      elements: elements,
      recordings: recordings,
      clock: clock,
    );
    final folders = FolderRepository(database, deviceId: deviceId, clock: clock);
    final blobs = BlobStore(database, blobBackend ?? MemoryBlobBackend(), clock: clock);
    final engine = SyncEngine(
      database: database,
      settings: settings,
      notebooks: notebooks,
      pages: pages,
      strokes: strokes,
      folders: folders,
      blobs: blobs,
      elements: elements,
      recordings: recordings,
    );
    final search = SearchService(database, readBlob: blobs.read);
    final recognition = RecognitionService(
      recognizer: recognizer ?? createHandwritingRecognizer(),
      settings: settings,
      database: database,
    );
    recognition.indexer.onIndexed = search.contentChanged;
    unawaited(recognition.start());
    return AppServices._(
      database: database,
      settings: settings,
      preferences: AppPreferences(settings),
      notebooks: notebooks,
      folders: folders,
      pages: pages,
      strokes: strokes,
      strokeReader: openStrokeReader(database.path, fallback: strokes),
      blobs: blobs,
      elements: elements,
      sync: syncApiFactory == null
          ? SyncController(engine: engine, settings: settings)
          : SyncController(engine: engine, settings: settings, apiFactory: syncApiFactory),
      search: search,
      recognition: recognition,
      recordings: recordings,
      audio: audio ?? platformAudioBackends(),
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

  /// Handwriting recognition: language, model, background indexing for
  /// search, "Convert to text".
  final RecognitionService recognition;
  /// Audio recordings of notebooks (their audio is in [blobs]).
  final RecordingRepository recordings;

  /// Makes recorders and players (created only when used).
  final AudioBackends audio;

  /// Copied strokes and text, shared by every editor (paste across pages
  /// and notebooks).
  final InkClipboard clipboard = InkClipboard();

  /// Notebooks open in editor tabs (with each tab's place in memory).
  final OpenNotebooks openNotebooks = OpenNotebooks();

  /// Decoded bitmaps of image elements, shared by editors and previews.
  late final ElementImages images = ElementImages(read: blobs.read, fetch: sync.fetchBlob);

  void dispose() {
    images.dispose();
    openNotebooks.dispose();
    clipboard.dispose();
    recognition.dispose();
    search.dispose();
    sync.dispose();
    closeStrokeReader(strokeReader);
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
