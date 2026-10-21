import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/features/settings/sync_settings.dart';
import 'package:len/sync/sync_api.dart';
import 'package:len/ui/app_theme.dart';

import 'content_golden_test.dart' show loadFonts;
import 'support/fake_server.dart';

// Settings → Sync → Device name: what the user's other devices and
// version history call this one.

void main() {
  testWidgets('Device name: shown in Settings → Sync, renamed, cleared back', (tester) async {
    await loadFonts();
    tester.view
      ..physicalSize = const Size(720, 640)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final server = FakeServer();
    final s = AppServices.create(
      AppDatabase.inMemory(),
      syncApiFactory: (url, t) => SyncApi(baseUrl: url, token: t, client: server.client),
    );
    addTearDown(s.dispose);
    s.sync.configure(url: 'https://len.example', token: FakeServer.token);
    // What Android calls it (a test has no system name to ask).
    await s.sync.deviceName.detect(ask: () async => 'Galaxy Tab S9');
    await tester.pumpWidget(
      AppScope(
        services: s,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          home: const Scaffold(body: SingleChildScrollView(child: SyncSettings())),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Device name'), findsOneWidget);
    expect(find.text('Galaxy Tab S9'), findsOneWidget);
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/device_name.png'));

    await tester.tap(find.text('Device name'));
    await tester.pumpAndSettle();
    expect(find.text('Name this device'), findsOneWidget);
    await tester.enterText(find.byType(TextField), 'Studio tablet');
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('goldens/device_name_rename.png'),
    );
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pumpAndSettle();
    expect(s.settings.deviceName, 'Studio tablet');
    expect(find.text('Studio tablet'), findsOneWidget);

    // Empty: back to the suggested name.
    await tester.tap(find.text('Device name'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '');
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pumpAndSettle();
    expect(s.settings.deviceName, isNull);
    expect(find.text('Galaxy Tab S9'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
  });
}
