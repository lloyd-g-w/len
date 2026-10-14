import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/blob_backend.dart';
import 'package:len/features/library/library_notice.dart';
import 'package:len/platform/browser_storage_api.dart';
import 'package:len/ui/startup_error.dart';

import 'ui_library_test.dart' show pumpLibrary;

class _Storage implements BrowserStorage {
  bool persisted = false;
  bool grant = true;

  @override
  Future<bool> isPersisted() async => persisted;

  @override
  Future<bool> requestPersistence() async => persisted = grant;

  @override
  Future<StorageUsage?> usage() async => null;
}

void main() {
  group('a browser that may clear the data (UX_AUDIT P2-30)', () {
    Future<AppServices> pump(WidgetTester tester, BrowserStorage storage) async {
      final services = AppServices.create(AppDatabase.inMemory());
      addTearDown(services.dispose);
      await tester.pumpWidget(
        AppScope(
          services: services,
          child: MaterialApp(
            home: Scaffold(
              body: LibraryNotices(storage: storage, child: const SizedBox()),
            ),
          ),
        ),
      );
      await tester.pump();
      return services;
    }

    const title = 'This browser may clear your notebooks';

    testWidgets('says so once while sync is off; Keep data asks the browser', (tester) async {
      final storage = _Storage();
      final services = await pump(tester, storage);
      expect(find.text(title), findsOneWidget);
      await tester.tap(find.text('Keep data'));
      await tester.pump();
      expect(storage.persisted, isTrue);
      expect(find.text(title), findsNothing);
      expect(services.settings.seenTips, contains(LibraryNotices.evictionTip));
    });

    testWidgets('not with sync on, nor once dismissed', (tester) async {
      final services = await pump(tester, _Storage());
      services.sync.configure(url: 'https://len.example', token: 't');
      await tester.pump();
      expect(find.text(title), findsNothing);
      services.sync.configure(url: '', token: '');
      await tester.pump();
      await tester.tap(find.byTooltip('Dismiss'));
      await tester.pump();
      expect(find.text(title), findsNothing);
      expect(services.settings.seenTips, contains(LibraryNotices.evictionTip));
    });
  });

  group('files that are not kept (UX_AUDIT P0-1)', () {
    testWidgets('the library says so when blobs only live in memory', (tester) async {
      final services = AppServices.create(
        AppDatabase.inMemory(),
        blobBackend: VolatileBlobBackend(),
      );
      expect(services.blobsArePersistent, isFalse);
      await pumpLibrary(tester, services: services);
      expect(find.text('Files you add won’t be kept in this browser window'), findsOneWidget);
    });

    testWidgets('no notice with real storage', (tester) async {
      final services = await pumpLibrary(tester);
      expect(services.blobsArePersistent, isTrue);
      expect(find.textContaining('won’t be kept'), findsNothing);
    });

    testWidgets('the first file stored warns once', (tester) async {
      final services = AppServices.create(
        AppDatabase.inMemory(),
        blobBackend: VolatileBlobBackend(),
      );
      addTearDown(services.dispose);
      await tester.pumpWidget(LenApp(services: services));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => services.blobs.putBytes(Uint8List.fromList([1, 2, 3]), mime: 'image/png'),
      );
      await tester.pump();
      const warning = 'This browser won’t keep this file once the tab is closed';
      expect(find.text(warning), findsOneWidget);
      await tester.pumpAndSettle();
      await tester.pump(const Duration(seconds: 11));
      await tester.pumpAndSettle();
      await tester.runAsync(
        () => services.blobs.putBytes(Uint8List.fromList([4, 5, 6]), mime: 'image/png'),
      );
      await tester.pump();
      expect(find.text(warning), findsNothing);
    });
  });

  group('startup error (UX_AUDIT P0-2)', () {
    testWidgets('explains, copies details and retries', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
        call,
      ) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map)['text'] as String;
        }
        return null;
      });
      var retries = 0;
      await tester.pumpWidget(
        StartupErrorApp(
          error: StateError('database is locked'),
          dataFolder: '/home/me/.local/share/len',
          onRetry: () async => retries++,
        ),
      );
      expect(find.text('Len couldn’t open your notes'), findsOneWidget);
      // The raw error stays out of sight, in the details.
      expect(find.textContaining('database is locked'), findsNothing);
      await tester.tap(find.text('Copy details'));
      await tester.pump();
      expect(copied, contains('database is locked'));
      expect(copied, contains('/home/me/.local/share/len'));
      expect(find.text('Details copied'), findsOneWidget);
      await tester.tap(find.text('Try again'));
      await tester.pump();
      expect(retries, 1);
    });
  });
}
