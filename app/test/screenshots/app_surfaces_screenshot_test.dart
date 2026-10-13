import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/features/settings/settings_screen.dart';
import 'package:len/features/settings/settings_section.dart';

import 'package:len/sync/sync_api.dart';

import '../support/fake_recognizer.dart';
import '../support/fake_server.dart';
import 'screenshot_harness.dart';

/// Settings, section by section: the column on tablets, desktop and phones
/// scrolled to each section (phones also at 1.3× text),
/// plus the sync and handwriting states and dialogs.
void main() {
  setUpAll(loadRealFonts);

  const phone = ('phone', Size(390, 844), 2.0);
  const tablet = ('tablet', Size(1280, 800), 1.0);
  const desktop = ('desktop', Size(1440, 900), 1.0);
  const sections = ['General', 'Writing', 'Handwriting', 'Sync', 'About'];
  const modes = [ThemeMode.light, ThemeMode.dark];

  /// Settings services; with [handwriting], recognition is supported and
  /// its model downloaded.
  AppServices services({bool handwriting = false}) {
    final s = AppServices.create(
      AppDatabase.inMemory(),
      recognizer: handwriting ? FakeRecognizer() : null,
    );
    addTearDown(s.dispose);
    return s;
  }

  Finder section(String title) =>
      find.byWidgetPredicate((w) => w is SettingsSection && w.title == title);

  /// Scrolls the column so [title]'s section is at the top.
  Future<void> scrollTo(WidgetTester tester, String title) async {
    await tester.ensureVisible(section(title));
    await settle(tester);
  }

  for (final (name, size, dpr) in [tablet, desktop]) {
    for (final mode in modes) {
      testWidgets('settings sections $name ${mode.name}', (tester) async {
        setWindow(tester, size, dpr: dpr);
        await pumpApp(tester, services(), const SettingsScreen(), mode: mode);
        for (final title in sections) {
          await scrollTo(tester, title);
          expect(section(title), findsOneWidget);
          expect(tester.takeException(), isNull);
          await shoot(tester, 's_settings_${title.toLowerCase()}_${name}_${mode.name}');
        }
      });
    }
  }

  for (final (mode, scale, suffix) in [
    (ThemeMode.light, 1.0, 'light'),
    (ThemeMode.dark, 1.0, 'dark'),
    (ThemeMode.light, 1.3, 'light_large'),
  ]) {
    testWidgets('settings sections phone $suffix', (tester) async {
      setWindow(tester, phone.$2, dpr: phone.$3);
      await pumpApp(tester, services(), const SettingsScreen(), mode: mode, textScale: scale);
      for (final title in sections) {
        await scrollTo(tester, title);
        expect(tester.takeException(), isNull);
        await shoot(tester, 's_settings_${title.toLowerCase()}_phone_$suffix');
      }
    });
  }

  for (final (name, size, dpr) in [phone, desktop]) {
    for (final mode in modes) {
      testWidgets('sync URL error $name ${mode.name}', (tester) async {
        setWindow(tester, size, dpr: dpr);
        await pumpApp(tester, services(), const SettingsScreen(), mode: mode);
        await scrollTo(tester, 'Sync');
        await tester.enterText(find.widgetWithText(TextField, 'Server URL'), 'ftp://len.example');
        await tester.enterText(find.widgetWithText(TextField, 'Access token'), 'secret-token');
        await tester.tap(find.byTooltip('Show'));
        await tester.tap(find.text('Connect'));
        await settle(tester);
        expect(find.textContaining('Enter a web address'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await shoot(tester, 's_settings_sync_error_${name}_${mode.name}');
      });

      testWidgets('sync connected, set up another device $name ${mode.name}', (tester) async {
        setWindow(tester, size, dpr: dpr);
        final server = FakeServer();
        final s = AppServices.create(
          AppDatabase.inMemory(),
          syncApiFactory: (url, t) => SyncApi(baseUrl: url, token: t, client: server.client),
        );
        addTearDown(s.dispose);
        s.sync.configure(url: 'https://len.example.org', token: FakeServer.token);
        await pumpApp(tester, s, const SettingsScreen(), mode: mode);
        await scrollTo(tester, 'Sync');
        await shoot(tester, 's_settings_sync_connected_${name}_${mode.name}');
        await tester.tap(find.text('Set up another device…'));
        await settle(tester);
        expect(tester.takeException(), isNull);
        await shoot(tester, 's_dialog_sync_setup_${name}_${mode.name}');
        await tester.tap(find.text('Close'));
        await settle(tester);
      });

      testWidgets('handwriting supported $name ${mode.name}', (tester) async {
        setWindow(tester, size, dpr: dpr);
        await pumpApp(tester, services(handwriting: true), const SettingsScreen(), mode: mode);
        await scrollTo(tester, 'Handwriting');
        expect(find.text('Search handwriting'), findsOneWidget);
        // Nothing written yet: said so, not "0 lines recognised".
        expect(find.text('Up to date'), findsOneWidget);
        await shoot(tester, 's_settings_handwriting_on_${name}_${mode.name}');

        await tester.tap(find.text('Language'));
        await settle(tester);
        expect(find.text('Handwriting language'), findsOneWidget);
        await shoot(tester, 's_settings_handwriting_language_${name}_${mode.name}');
        await tester.tapAt(const Offset(4, 4));
        await settle(tester);
        expect(tester.takeException(), isNull);
      });
    }
  }

  testWidgets('handwriting supported phone large text', (tester) async {
    setWindow(tester, phone.$2, dpr: phone.$3);
    await pumpApp(tester, services(handwriting: true), const SettingsScreen(), textScale: 1.3);
    await scrollTo(tester, 'Handwriting');
    expect(tester.takeException(), isNull);
    await shoot(tester, 's_settings_handwriting_on_phone_light_large');
  });
}
