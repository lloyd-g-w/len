import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/features/settings/settings_screen.dart';
import 'package:len/features/settings/sync_settings.dart';
import 'package:len/platform/secure_store.dart';
import 'package:len/sync/sync_api.dart';
import 'package:len/sync/sync_controller.dart';
import 'package:len/sync/sync_setup_link.dart';
import 'package:len/ui/app_theme.dart';
import 'package:len/ui/qr_code_view.dart';
import 'package:len/ui/sync_status_button.dart';

import 'support/fake_server.dart';

/// A device syncing with [server] using [token]; [onApi] sees each API
/// client made.
AppServices _device(FakeServer server, {required String token, void Function()? onApi}) {
  final s = AppServices.create(
    AppDatabase.inMemory(),
    syncApiFactory: (url, t) {
      onApi?.call();
      return SyncApi(baseUrl: url, token: t, client: server.client);
    },
  );
  s.sync.configure(url: 'http://sync.test', token: token);
  return s;
}

void main() {
  group('a rejected token (UX_AUDIT P1-22)', () {
    test('stops automatic syncs until the settings change', () async {
      var apis = 0;
      final s = _device(FakeServer(), token: 'wrong', onApi: () => apis++);
      addTearDown(s.dispose);
      await s.sync.syncNow();
      expect(s.sync.state, SyncState.error);
      expect(s.sync.lastFailure, SyncFailure.auth);
      expect(s.sync.waitsForSettings, isTrue);
      expect(apis, 1);

      await s.sync.syncInBackground();
      expect(apis, 1, reason: 'no retry: it cannot work');

      s.sync.configure(url: 'http://sync.test', token: FakeServer.token);
      expect(s.sync.waitsForSettings, isFalse);
      await s.sync.syncInBackground();
      expect(apis, 2);
      expect(s.sync.state, SyncState.idle);
    });

    test('network failures keep retrying', () async {
      final server = FakeServer();
      var apis = 0;
      final s = AppServices.create(
        AppDatabase.inMemory(),
        syncApiFactory: (url, t) {
          apis++;
          throw SyncException.unreachable(Exception('Connection refused'));
        },
      );
      addTearDown(s.dispose);
      s.sync.configure(url: 'http://sync.test', token: FakeServer.token);
      await s.sync.syncNow();
      expect(s.sync.lastFailure, SyncFailure.network);
      await s.sync.syncInBackground();
      expect(apis, 2);
      expect(server.pulls, 0);
    });

    testWidgets('says so once, with Settings', (tester) async {
      final s = _device(FakeServer(), token: 'wrong');
      addTearDown(s.dispose);
      await tester.pumpWidget(LenApp(services: s));
      await tester.pumpAndSettle();
      await tester.runAsync(s.sync.syncNow);
      await tester.pump();
      const told = 'Sync stopped: the server refused the access token';
      expect(find.text(told), findsOneWidget);
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(SnackBarAction, 'Settings'));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(find.textContaining('access token. Sync is paused'), findsOneWidget);
      // Trying again by hand and failing again isn't announced twice.
      await tester.pump(const Duration(seconds: 10));
      await tester.pumpAndSettle();
      await tester.runAsync(s.sync.syncNow);
      await tester.pump();
      expect(find.text(told), findsNothing);
    });
  });

  testWidgets('a failed status opens the settings instead of retrying', (tester) async {
    final s = _device(FakeServer(), token: 'wrong');
    addTearDown(s.dispose);
    await tester.runAsync(s.sync.syncNow);
    var opened = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SyncStatusButton(sync: s.sync, onOpenSettings: () => opened++, caption: true),
        ),
      ),
    );
    await tester.tap(find.text('Sync failed'));
    expect(opened, 1);
    expect(s.sync.state, SyncState.error);
  });

  group('sync setup (UX_AUDIT P1-23)', () {
    test('assumes https:// when no scheme is typed', () {
      expect(SyncSettings.completeUrl(' len.example '), 'https://len.example');
      expect(SyncSettings.completeUrl('http://10.0.0.2:8080'), 'http://10.0.0.2:8080');
      expect(SyncSettings.completeUrl(''), '');
      expect(SyncSettings.validateUrl('https://len.example'), isNull);
      expect(SyncSettings.validateUrl('ftp://len.example'), isNotNull);
    });

    testWidgets('connected: shows the server and turns off with a confirm', (tester) async {
      final s = _device(FakeServer(), token: FakeServer.token);
      addTearDown(s.dispose);
      tester.view
        ..physicalSize = const Size(800, 1400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        AppScope(
          services: s,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: SingleChildScrollView(child: SyncSettings())),
          ),
        ),
      );
      expect(find.text('http://sync.test'), findsOneWidget);
      expect(find.text('Server URL'), findsNothing);
      await tester.tap(find.text('Turn off sync…'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Turn off'));
      await tester.pumpAndSettle();
      expect(s.sync.isConfigured, isFalse);
      expect(s.sync.state, SyncState.disabled);
      expect(find.text('Server URL'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a token kept out of secure storage is mentioned once', (tester) async {
      final secure = MemorySecureStore()..available = false;
      final s = AppServices.create(AppDatabase.inMemory(), secureStore: secure);
      addTearDown(s.dispose);
      s.sync.configure(url: 'http://sync.test', token: FakeServer.token);
      await tester.runAsync(() => s.sync.tokens.save(FakeServer.token));
      expect(s.sync.tokens.inDatabase, isTrue);
      Future<void> show() => tester.pumpWidget(
        AppScope(
          services: s,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: SingleChildScrollView(child: SyncSettings())),
          ),
        ),
      );
      final note = find.textContaining('secure storage isn\'t available');
      await show();
      expect(note, findsOneWidget);
      expect(s.sync.isConfigured, isTrue, reason: 'sync goes on');
      await tester.pumpWidget(const SizedBox());
      await show();
      expect(note, findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });
  group('setup links (UX_AUDIT R6-23)', () {
    const link = SyncSetupLink(url: 'http://192.168.1.10:8080/len', token: 'a+b/c=&d e');

    test('round-trip, and only len://sync links with a URL count', () {
      expect(link.link, startsWith('len://sync?url='));
      expect(SyncSetupLink.parse('  ${link.link}\n'), link);
      expect(SyncSetupLink.parse('https://len.example'), isNull);
      expect(SyncSetupLink.parse('len://sync?token=x'), isNull);
      expect(SyncSetupLink.parse('len://other?url=x'), isNull);
      expect(link.toString(), isNot(contains('a+b')), reason: 'no token in logs');
    });

    Future<void> show(WidgetTester tester, AppServices s) async {
      tester.view
        ..physicalSize = const Size(800, 1400)
        ..devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        AppScope(
          services: s,
          child: MaterialApp(
            theme: AppTheme.light(),
            home: const Scaffold(body: SingleChildScrollView(child: SyncSettings())),
          ),
        ),
      );
    }

    String field(WidgetTester tester, String label) =>
        tester.widget<TextField>(find.widgetWithText(TextField, label)).controller!.text;

    testWidgets('a link pasted into Server URL fills both fields', (tester) async {
      final s = AppServices.create(AppDatabase.inMemory());
      addTearDown(s.dispose);
      await show(tester, s);
      await tester.enterText(find.widgetWithText(TextField, 'Server URL'), link.link);
      await tester.pump();
      expect(field(tester, 'Server URL'), link.url);
      expect(field(tester, 'Access token'), link.token);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a link opened with Len fills the form, even when connected', (tester) async {
      final s = _device(FakeServer(), token: FakeServer.token);
      addTearDown(s.dispose);
      await show(tester, s);
      expect(find.text('Server URL'), findsNothing);
      s.incomingFiles.addLink(link.link);
      await tester.pump();
      expect(field(tester, 'Server URL'), link.url);
      expect(field(tester, 'Access token'), link.token);
      expect(s.incomingFiles.syncSetup.value, isNull, reason: 'taken');
      expect(s.settings.syncUrl, 'http://sync.test', reason: 'only once connected');
      expect(
        find.textContaining('Settings → Sync → Set up another device…'),
        findsOneWidget,
        reason: 'says where links come from, for next time',
      );
      await tester.tap(find.text('Cancel'));
      await tester.pump();
      await tester.tap(find.text('Change…'));
      await tester.pump();
      expect(find.textContaining('Filled from a setup link'), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('a link opened with Len opens Settings on its form', (tester) async {
      final s = AppServices.create(AppDatabase.inMemory());
      addTearDown(s.dispose);
      s.incomingFiles.addLink(link.link); // A cold start: before the library.
      await tester.pumpWidget(LenApp(services: s));
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);
      expect(field(tester, 'Server URL'), link.url);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsNothing, reason: 'once');
    });

    testWidgets('a connected device shows a QR code and copies the link', (tester) async {
      String? copied;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (
        call,
      ) async {
        if (call.method == 'Clipboard.setData') {
          copied = (call.arguments as Map<Object?, Object?>)['text'] as String?;
        }
        return null;
      });
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          SystemChannels.platform,
          null,
        ),
      );
      final s = _device(FakeServer(), token: FakeServer.token);
      addTearDown(s.dispose);
      await show(tester, s);
      await tester.tap(find.text('Set up another device…'));
      await tester.pumpAndSettle();
      final qr = tester.widget<QrCodeView>(find.byType(QrCodeView));
      expect(
        SyncSetupLink.parse(qr.data),
        SyncSetupLink(url: 'http://sync.test', token: FakeServer.token),
      );
      expect(find.textContaining('includes your access token'), findsOneWidget);
      await tester.tap(find.text('Copy link'));
      await tester.pumpAndSettle();
      expect(copied, qr.data);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
