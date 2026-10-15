import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/raster_store.dart';
import 'package:len/data/write_back.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/recording.dart';
import 'package:len/features/audio/ui/recordings_sheet.dart';
import 'package:len/features/editor/tabs/editor_workspace.dart';
import 'package:len/features/settings/storage_settings.dart';
import 'package:len/platform/blob_backend_native.dart';
import 'package:len/platform/browser_storage_api.dart';
import 'package:len/sync/sync_api.dart';
import 'package:len/ui/app_theme.dart';

import 'support/fake_server.dart';
import 'support/real_async.dart';

class _FakeStorage implements BrowserStorage {
  _FakeStorage({required this.grant});

  final bool grant;
  bool persisted = false;
  int requests = 0;

  @override
  Future<bool> isPersisted() async => persisted;

  @override
  Future<bool> requestPersistence() async {
    requests++;
    persisted = grant;
    return grant;
  }

  @override
  Future<StorageUsage?> usage() async => (usage: 5 * 1024 * 1024, quota: 2 * 1024 * 1024 * 1024);
}

/// A write-back store whose failure the test sets.
class _Store with ChangeNotifier implements WriteBackStore {
  @override
  bool pending = false;

  @override
  WriteFailure? failure;

  int flushes = 0;

  void set(WriteFailure? failure) {
    this.failure = failure;
    pending = failure != null;
    notifyListeners();
  }

  @override
  Future<bool> flush() async {
    flushes++;
    return failure == null;
  }

  @override
  Future<bool> close() async => true;
}

Future<AppServices> _pump(
  WidgetTester tester, {
  BrowserStorage? storage,
  StorageWrites? writes,
  AppServices? services,
}) async {
  final s = services ?? AppServices.create(AppDatabase.inMemory());
  if (services == null) addTearDown(s.dispose);
  await tester.pumpWidget(
    AppScope(
      services: s,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: StorageSettings(overview: s.storage, storage: storage, writes: writes),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return s;
}

void main() {
  testWidgets('shows usage and turns persistent storage on', (tester) async {
    final storage = _FakeStorage(grant: true);
    await _pump(tester, storage: storage);
    expect(find.textContaining('5 MB of 2 GB'), findsOneWidget);
    expect(find.textContaining('Off:'), findsOneWidget);

    await tester.tap(find.text('Turn on'));
    await tester.pumpAndSettle();
    expect(storage.requests, 1);
    expect(find.textContaining('On:'), findsOneWidget);
    expect(find.text('Turn on'), findsNothing);
  });

  testWidgets('explains a refusal', (tester) async {
    final storage = _FakeStorage(grant: false);
    await _pump(tester, storage: storage);
    await tester.tap(find.text('Turn on'));
    await tester.pumpAndSettle();
    expect(find.textContaining('The browser declined'), findsOneWidget);
    expect(find.text('Turn on'), findsOneWidget);
  });

  testWidgets('says while changes can\'t be saved, like the library', (tester) async {
    final store = _Store();
    await _pump(tester, storage: _FakeStorage(grant: true), writes: StorageWrites()..add(store));
    expect(find.textContaining('aren’t saved yet'), findsNothing);

    store.set(WriteFailure.full);
    await tester.pump();
    expect(find.text('Your latest changes aren’t saved yet'), findsOneWidget);
    expect(find.textContaining('Browser storage is full'), findsOneWidget);
    await tester.tap(find.text('Try again'));
    expect(store.flushes, 1);

    store.set(null);
    await tester.pumpAndSettle();
    expect(find.textContaining('aren’t saved yet'), findsNothing);
  });

  group('overview', () {
    late Directory dir;
    late FakeServer server;
    late MemoryRasterStore rasters;
    late AppServices s;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('len_storage_ui_test_');
      server = FakeServer();
      rasters = MemoryRasterStore();
      s = AppServices.create(
        AppDatabase.inMemory(),
        blobBackend: FileBlobBackend(dir.path),
        rasterStore: rasters,
        syncApiFactory: (url, token) => SyncApi(baseUrl: url, token: token, client: server.client),
      );
    });
    tearDown(() {
      s.dispose();
      dir.deleteSync(recursive: true);
    });

    /// A notebook with a [mb]-MB recording the server holds.
    Future<(Notebook, String)> lecture(WidgetTester tester, String title, int mb) async {
      final bytes = Uint8List(mb << 20)..setAll(0, utf8.encode(title));
      final sha = (await tester.runAsync(() => s.blobs.putBytes(bytes, mime: 'audio/mp4')))!;
      s.blobs.markUploaded(sha);
      server.blobs[sha] = bytes;
      final n = s.notebooks.create(
        title: title,
        kind: NotebookKind.paged,
        paper: PaperStyle.blank,
        coverColor: 0,
      );
      s.recordings.save(
        notebookId: n.id,
        parts: [RecordingPart(sha, 1000)],
        mime: 'audio/mp4',
        title: 'Recording',
        segments: [RecordingSegment(s.clock.nowMs(), 1000)],
      );
      // Synced (files only unsynced rows show stay).
      s.database.execute('UPDATE recordings SET dirty = 0');
      return (n, sha);
    }

    testWidgets('shows the space by kind and the largest notebooks', (tester) async {
      await lecture(tester, 'Physics', 3);
      await lecture(tester, 'Chemistry', 5);
      await _pump(tester, services: s);
      expect(find.text('Space used'), findsOneWidget);
      expect(find.textContaining('MB on this device'), findsOneWidget);
      expect(find.text('Recordings'), findsNWidgets(3)); // The kind, then two buttons.
      expect(find.text('8 MB'), findsOneWidget);
      expect(find.text('Largest notebooks'), findsOneWidget);
      final chemistry = tester.getTopLeft(find.text('Chemistry')).dy;
      expect(chemistry, lessThan(tester.getTopLeft(find.text('Physics')).dy));
      expect(find.text('5 MB, all recordings'), findsOneWidget);
      // Without sync nothing offers to free up; no previews to clear.
      expect(find.textContaining('Free up'), findsNothing);
      expect(find.text('Cached previews'), findsNothing);
      expect(find.text('Browser storage'), findsNothing);
    });

    testWidgets('frees up copies the server holds, after asking once', (tester) async {
      s.sync.configure(url: 'http://sync.test', token: FakeServer.token);
      final (_, sha) = await lecture(tester, 'Physics', 3);
      await _pump(tester, services: s);
      await tester.tap(find.text('Free up 3 MB…'));
      await tester.pumpAndSettle();
      expect(find.text('Free up 3 MB?'), findsOneWidget);
      expect(find.textContaining('can’t be undone'), findsOneWidget);
      expect(find.textContaining('The sync server must keep its files'), findsOneWidget);
      await tester.tap(find.widgetWithText(FilledButton, 'Free up'));
      await pumpUntil(tester, () => find.text('Freed up 3 MB').evaluate().isNotEmpty);
      await pumpUntil(tester, () => !s.storage.freeing && s.storage.survey!.freeable == 0);
      await tester.pump(const Duration(seconds: 1)); // The dialog has gone.
      expect(await tester.runAsync(() => s.blobs.has(sha)), isFalse);
      expect(find.textContaining('Free up'), findsNothing);
    });

    testWidgets('clears cached previews', (tester) async {
      await tester.runAsync(() => rasters.write('chunk', Uint8List(2 << 20)));
      await _pump(tester, services: s);
      expect(find.text('Cached previews'), findsNWidgets(2)); // The kind and the row.
      await tester.tap(find.text('Clear'));
      await tester.pumpAndSettle();
      expect(rasters.length, 0);
      expect(find.text('Cached previews'), findsNothing);
    });

    testWidgets('opens a notebook at its recordings', (tester) async {
      final (n, _) = await lecture(tester, 'Physics', 1);
      await _pump(tester, services: s);
      await tester.tap(find.widgetWithText(TextButton, 'Recordings'));
      await tester.pumpAndSettle();
      expect(s.openNotebooks.activeId, n.id);
      expect(find.byType(EditorWorkspace), findsOneWidget);
      expect(find.byType(RecordingsList), findsOneWidget);
    });
  });
}
