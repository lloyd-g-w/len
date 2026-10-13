import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/settings_repository.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/settings/settings_screen.dart';
import 'package:len/features/settings/sync_alert_button.dart';
import 'package:len/sync/sync_api.dart';
import 'package:len/ui/app_theme.dart';

import 'support/fake_server.dart';
import 'ui_library_test.dart' show pumpLibrary;

/// A device whose syncs fail: the server refuses its token ([auth]), or
/// can't be reached. [lastSuccess] is when it last synced, as kept.
AppServices _failing({bool auth = false, DateTime? lastSuccess}) {
  final db = AppDatabase.inMemory();
  if (lastSuccess != null) {
    SettingsRepository(db).syncLastSuccess = lastSuccess.millisecondsSinceEpoch;
  }
  final server = FakeServer();
  final s = AppServices.create(
    db,
    syncApiFactory: (url, t) => auth
        ? SyncApi(baseUrl: url, token: t, client: server.client)
        : throw SyncException.unreachable(Exception('Connection refused')),
  );
  s.sync.configure(url: 'http://sync.test', token: auth ? 'wrong' : FakeServer.token);
  return s;
}

const _alert = ValueKey('sync-alert');

/// Sync failing for a while is seen outside Settings (UX_AUDIT R7-14).
void main() {
  test('failing since: kept through retries, cleared by a sync that works', () async {
    final server = FakeServer();
    var down = true;
    final s = AppServices.create(
      AppDatabase.inMemory(),
      syncApiFactory: (url, t) => down
          ? throw SyncException.unreachable(Exception('Connection refused'))
          : SyncApi(baseUrl: url, token: t, client: server.client),
    );
    addTearDown(s.dispose);
    s.sync.configure(url: 'http://sync.test', token: FakeServer.token);
    await s.sync.syncNow();
    final since = s.sync.failingSince!;
    expect(s.sync.failingFor(const Duration(minutes: 15)), isFalse); // A moment offline.
    expect(
      s.sync.failingFor(const Duration(minutes: 15), now: since.add(const Duration(minutes: 16))),
      isTrue,
    );
    await s.sync.syncNow();
    expect(s.sync.failingSince, since); // Retrying doesn't restart the clock.

    down = false;
    await s.sync.syncNow();
    expect(s.sync.failingSince, isNull);
    // When it last worked is kept for the next launch.
    expect(s.settings.syncLastSuccess, s.sync.lastSuccess!.millisecondsSinceEpoch);
  });

  testWidgets('phones: a mark in the library header opens Settings → Sync', (tester) async {
    final s = _failing(auth: true);
    await pumpLibrary(tester, services: s, size: const Size(390, 844));
    expect(find.byKey(_alert), findsNothing); // Syncing works so far.
    await tester.runAsync(s.sync.syncNow);
    await tester.pump();
    expect(find.byKey(_alert), findsOneWidget);
    await tester.tap(find.byKey(_alert));
    await tester.pumpAndSettle();
    expect(find.byType(SettingsScreen), findsOneWidget);
  });

  testWidgets('the editor shows the mark in its bar', (tester) async {
    final s = _failing(auth: true);
    addTearDown(s.dispose);
    final nb = s.notebooks.create(
      title: 'N',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    await tester.runAsync(s.sync.syncNow);
    await tester.pumpWidget(
      AppScope(
        services: s,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: EditorScreen(notebook: nb),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(_alert), findsOneWidget);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  });

  testWidgets('a day without syncing is said once, with Settings', (tester) async {
    final s = _failing(lastSuccess: DateTime.now().subtract(const Duration(days: 3)));
    addTearDown(s.dispose);
    await tester.pumpWidget(LenApp(services: s));
    await tester.pumpAndSettle();
    await tester.runAsync(s.sync.syncNow);
    await tester.pump();
    expect(find.textContaining('Not synced since'), findsOneWidget);
    expect(find.widgetWithText(SnackBarAction, 'Settings'), findsOneWidget);
    await tester.pumpAndSettle(); // In, then its time runs out.
    await tester.pump(const Duration(seconds: 10));
    await tester.pumpAndSettle();
    await tester.runAsync(s.sync.syncNow);
    await tester.pump();
    expect(find.textContaining('Not synced since'), findsNothing); // Once.
  });

  test('offline is grey and says so; a refused token is red (R8-12)', () async {
    final offline = _failing(lastSuccess: DateTime.now());
    addTearDown(offline.dispose);
    await offline.sync.syncNow();
    final quiet = syncAlert(offline.sync);
    expect(quiet.fix, isFalse);
    expect(quiet.offline, isTrue);
    expect(quiet.tooltip, 'Offline: not synced since just now');

    final refused = _failing(auth: true);
    addTearDown(refused.dispose);
    await refused.sync.syncNow();
    final red = syncAlert(refused.sync);
    expect(red.fix, isTrue);
    expect(red.tooltip, 'Not synced yet: open Sync settings');
  });
}
