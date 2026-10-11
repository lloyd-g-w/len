import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/features/library/library_screen.dart';
import 'package:len/features/settings/settings_screen.dart';

import 'screenshot_harness.dart';

const phone = Size(390, 844);
const tabletPortrait = Size(800, 1280);
const tablet = Size(1280, 800);
const desktop = Size(1440, 900);

void main() {
  setUpAll(loadRealFonts);

  for (final (name, size, dpr) in [
    ('phone', phone, 2.0),
    ('tablet_portrait', tabletPortrait, 1.0),
    ('tablet', tablet, 1.0),
    ('desktop', desktop, 1.0),
  ]) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('library $name ${mode.name}', (tester) async {
        setWindow(tester, size, dpr: dpr);
        final services = seededServices();
        addTearDown(services.dispose);
        await pumpApp(tester, services, const LibraryScreen(), mode: mode);
        expect(tester.takeException(), isNull);
        await shoot(tester, 'library_${name}_${mode.name}');
      });
    }
  }

  testWidgets('library empty phone', (tester) async {
    setWindow(tester, phone, dpr: 2);
    final services = AppServices.create(AppDatabase.inMemory());
    addTearDown(services.dispose);
    await pumpApp(tester, services, const LibraryScreen());
    await shoot(tester, 'empty_phone_light');
  });

  testWidgets('desktop: folder, list view, trash, menu, new sheet', (tester) async {
    setWindow(tester, desktop);
    final services = seededServices();
    addTearDown(services.dispose);
    await pumpApp(tester, services, const LibraryScreen());

    await tester.tap(find.text('School').first);
    await settle(tester);
    await shoot(tester, 'desktop_folder');

    await tester.tap(find.text('Library').first);
    await settle(tester);
    await tester.tap(find.byTooltip('Show as list'));
    await settle(tester);
    await shoot(tester, 'desktop_list');
    await tester.tap(find.byTooltip('Show as grid'));
    await settle(tester);

    await tester.tap(find.byTooltip('More').first);
    await settle(tester);
    await shoot(tester, 'desktop_menu');

    await tester.tap(find.text('Change cover'));
    await settle(tester);
    await shoot(tester, 'desktop_cover_sheet');
    await tester.tap(find.text('Apply'));
    await settle(tester);

    await tester.enterText(find.byType(TextField), 'o');
    await settle(tester);
    await shoot(tester, 'desktop_search');
    await tester.enterText(find.byType(TextField), '');
    await settle(tester);

    await tester.tap(find.text('Trash').first);
    await settle(tester);
    await shoot(tester, 'desktop_trash');

    await tester.tap(find.text('Library').first);
    await settle(tester);
    await tester.tap(find.text('New'));
    await settle(tester);
    await shoot(tester, 'desktop_new_sheet');
    expect(tester.takeException(), isNull);
  });

  for (final (name, size, dpr) in [('phone', phone, 2.0), ('desktop', desktop, 1.0)]) {
    testWidgets('folder dialog $name', (tester) async {
      setWindow(tester, size, dpr: dpr);
      final services = seededServices();
      addTearDown(services.dispose);
      await pumpApp(tester, services, const LibraryScreen());
      await tester.longPress(find.text('Work').last);
      await settle(tester);
      await tester.tap(find.text('Edit folder'));
      await settle(tester);
      await shoot(tester, 'folder_dialog_$name');
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('phone new sheet dark', (tester) async {
    setWindow(tester, phone, dpr: 2);
    final services = seededServices();
    addTearDown(services.dispose);
    await pumpApp(tester, services, const LibraryScreen(), mode: ThemeMode.dark);
    await tester.tap(find.text('New'));
    await settle(tester);
    await shoot(tester, 'phone_new_sheet_dark');
    expect(tester.takeException(), isNull);
  });

  for (final (name, size, dpr) in [
    ('phone', phone, 2.0),
    ('desktop', desktop, 1.0),
    ('tall', const Size(900, 1760), 1.0),
  ]) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('settings $name ${mode.name}', (tester) async {
        setWindow(tester, size, dpr: dpr);
        final services = AppServices.create(AppDatabase.inMemory());
        addTearDown(services.dispose);
        await pumpApp(tester, services, const SettingsScreen(), mode: mode);
        expect(tester.takeException(), isNull);
        await shoot(tester, 'settings_${name}_${mode.name}');
      });
    }
  }
}
