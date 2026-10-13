import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:flutter/widgets.dart';

import 'core/clock.dart';
import 'core/pointer_activity.dart';
import 'data/app_database.dart';
import 'data/app_preferences.dart';
import 'data/blob_backend.dart';
import 'data/blob_gc.dart';
import 'data/blob_references.dart';
import 'data/blob_store.dart';
import 'data/element_repository.dart';
import 'data/folder_repository.dart';
import 'data/notebook_repository.dart';
import 'data/outline_repository.dart';
import 'data/page_repository.dart';
import 'data/recording_repository.dart';
import 'data/search/search_service.dart';
import 'data/settings_repository.dart';
import 'data/stroke_reader.dart';
import 'data/stroke_repository.dart';
import 'data/template_repository.dart';
import 'data/tombstone_payloads.dart';
import 'features/audio/backends/audio_backends.dart';
import 'features/audio/backends/platform_audio.dart';
import 'features/documents/import/incoming_files.dart';
import 'features/editor/shared/shared_notebooks.dart';
import 'features/editor/tabs/open_notebooks.dart';
import 'ink/images/element_images.dart';
import 'ink/recognition/handwriting_recognizer.dart';
import 'ink/recognition/recognition_service.dart';
import 'ink/render/outline_preparer.dart';
import 'ink/selection/ink_clipboard.dart';
import 'platform/handwriting_recognizer.dart';
import 'platform/stroke_reader.dart';
import 'sync/sync_api.dart';
import 'sync/sync_controller.dart';
import 'sync/sync_engine.dart';
import 'ui/route_owners.dart';

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
    required this.pointerActivity,
    required this.recordings,
    required this.audio,
    required this.incomingFiles,
    required this.templates,
    required this.outlines,
    required this.outline,
  });

  /// Wires up all services on [database]. [syncApiFactory] lets tests
  /// substitute the sync transport. Blobs (PDFs) are kept in [blobBackend]
  /// (in memory if omitted, e.g. in tests). [audio] replaces the
  /// recorder and player (tests use fakes). [incomingFiles] are files
  /// handed to the app from outside (`platform/incoming_files`).
  factory AppServices.create(
    AppDatabase database, {
    Clock clock = const Clock(),
    BlobBackend? blobBackend,
    AudioBackends? audio,
    SyncApi Function(String url, String token)? syncApiFactory,
    HandwritingRecognizer? recognizer,
    Stream<List<XFile>>? incomingFiles,
    OutlinePreparer outlines = const InlineOutlinePreparer(),
  }) {
    final settings = SettingsRepository(database);
    final deviceId = settings.deviceId(clock);
    final strokes = StrokeRepository(database, deviceId: deviceId, clock: clock);
    final elements = ElementRepository(database, deviceId: deviceId, clock: clock);
    final recordings = RecordingRepository(database, deviceId: deviceId, clock: clock);
    final pages = PageRepository(database, deviceId: deviceId, clock: clock);
    final outline = OutlineRepository(database, deviceId: deviceId, clock: clock);
    final notebooks = NotebookRepository(
      database,
      deviceId: deviceId,
      pages: pages,
      strokes: strokes,
      elements: elements,
      recordings: recordings,
      outline: outline,
      clock: clock,
    );
    final folders = FolderRepository(database, deviceId: deviceId, clock: clock);
    final templates = TemplateRepository(database, deviceId: deviceId, clock: clock);
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
      templates: templates,
      outline: outline,
    );
    final search = SearchService(database, readBlob: blobs.read);
    final pointerActivity = PointerActivity();
    final recognition = RecognitionService(
      recognizer: recognizer ?? createHandwritingRecognizer(),
      settings: settings,
      database: database,
      activity: pointerActivity,
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
      pointerActivity: pointerActivity,
      recordings: recordings,
      audio: audio ?? platformAudioBackends(),
      incomingFiles: IncomingFiles(incomingFiles),
      templates: templates,
      outlines: outlines,
      outline: outline,
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

  /// Whether files added to notebooks (PDFs, images, audio) are kept on
  /// this device. False in a browser that refused storage
  /// ([VolatileBlobBackend]): they then last only until the tab closes, and
  /// the app says so.
  bool get blobsArePersistent => blobs.backend is! VolatileBlobBackend;
  final ElementRepository elements;
  final SyncController sync;

  /// Full-text search over titles, text boxes and PDF text.
  final SearchService search;

  /// Handwriting recognition: language, model, background indexing for
  /// search, "Convert to text".
  final RecognitionService recognition;

  /// Whether the user is touching the app (background work waits); watches
  /// pointers once the app widget attaches it.
  final PointerActivity pointerActivity;

  /// Audio recordings of notebooks (their audio is in [blobs]).
  final RecordingRepository recordings;

  /// The user's own templates (images as blobs).
  final TemplateRepository templates;

  /// Builds the outlines of strokes loaded into editors (natively on
  /// worker isolates, see `platform/outline_preparer`).
  final OutlinePreparer outlines;

  /// Notebooks' own outlines (tables of contents).
  final OutlineRepository outline;

  /// Makes recorders and players (created only when used).
  final AudioBackends audio;

  /// Files opened with / shared to Len, and the editor they may go into.
  final IncomingFiles incomingFiles;

  /// Copied strokes and text, shared by every editor (paste across pages
  /// and notebooks).
  final InkClipboard clipboard = InkClipboard();

  /// Notebooks open in editor tabs (with each tab's place in memory).
  final OpenNotebooks openNotebooks = OpenNotebooks();

  /// Which part of the screen opened each route (register with the app's
  /// navigator).
  final RouteOwners routeOwners = RouteOwners();

  /// What the editors of one notebook share (the notebook, its audio,
  /// surfaces, undo and PDF caches), per open notebook.
  late final SharedNotebooks sharedNotebooks = SharedNotebooks(this);

  /// Deletes blobs nothing references anymore; started by the app at launch.
  late final LocalBlobGc blobGc = LocalBlobGc(
    blobs: blobs,
    references: BlobReferences(database),
    settings: settings,
    tombstones: TombstonePayloads(database: database, strokes: strokes, elements: elements),
  );

  /// Decoded bitmaps of image elements, shared by editors and previews.
  late final ElementImages images = ElementImages(read: blobs.read, fetch: sync.fetchBlob);

  void dispose() {
    sharedNotebooks.dispose();
    incomingFiles.dispose();
    images.dispose();
    openNotebooks.dispose();
    clipboard.dispose();
    recognition.dispose();
    pointerActivity.detach();
    search.dispose();
    sync.dispose();
    closeStrokeReader(strokeReader);
    outlines.close();
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

  /// The services if there is an [AppScope] above [context] (widgets that
  /// also work standalone, e.g. in tests), without subscribing.
  static AppServices? maybeRead(BuildContext context) =>
      context.getInheritedWidgetOfExactType<AppScope>()?.services;

  /// Like [of] but without subscribing; safe to call from `initState`.
  static AppServices read(BuildContext context) {
    final scope = context.getInheritedWidgetOfExactType<AppScope>();
    assert(scope != null, 'No AppScope above this context');
    return scope!.services;
  }

  @override
  bool updateShouldNotify(AppScope old) => old.services != services;
}
