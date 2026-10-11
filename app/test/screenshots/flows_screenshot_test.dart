import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/documents/progress_dialog.dart';
import 'package:len/features/documents/template_picker.dart';
import 'package:len/features/library/library_screen.dart';
import 'package:len/features/settings/settings_screen.dart';

import 'screenshot_harness.dart';

/// Sheets, dialogs, empty states and large text: every surface of the
/// library, settings and document flows at the four reference sizes.
void main() {
  setUpAll(loadRealFonts);

  const sizes = [
    ('phone', Size(390, 844), 2.0),
    ('tablet_portrait', Size(800, 1280), 1.0),
    ('tablet', Size(1280, 800), 1.0),
    ('desktop', Size(1440, 900), 1.0),
  ];

  BuildContext ctx(WidgetTester tester) => tester.element(find.byType(LibraryScreen));

  for (final (name, size, dpr) in sizes) {
    for (final mode in [ThemeMode.light, ThemeMode.dark]) {
      testWidgets('new sheet $name ${mode.name}', (tester) async {
        setWindow(tester, size, dpr: dpr);
        final services = seededServices();
        addTearDown(services.dispose);
        await pumpApp(tester, services, const LibraryScreen(), mode: mode);
        await tester.tap(find.text('New').last);
        await settle(tester);
        expect(tester.takeException(), isNull);
        await shoot(tester, 'new_${name}_${mode.name}');
      });
    }

    testWidgets('template picker $name', (tester) async {
      setWindow(tester, size, dpr: dpr);
      final services = seededServices();
      addTearDown(services.dispose);
      await pumpApp(tester, services, const LibraryScreen());
      unawaited(
        showTemplatePicker(
          ctx(tester),
          initial: const PageTemplate(paper: Paper(PaperStyle.collegeRuled)),
          mode: TemplatePickerMode.change,
        ),
      );
      await settle(tester);
      expect(tester.takeException(), isNull);
      await shoot(tester, 'template_${name}_light');
    });

    testWidgets('settings $name light', (tester) async {
      setWindow(tester, size, dpr: dpr);
      final services = seededServices();
      addTearDown(services.dispose);
      await pumpApp(tester, services, const SettingsScreen());
      expect(tester.takeException(), isNull);
      await shoot(tester, 'settings2_${name}_light');
    });
  }

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    testWidgets('dialogs ${mode.name}', (tester) async {
      setWindow(tester, const Size(1280, 800));
      final services = seededServices();
      addTearDown(services.dispose);
      await pumpApp(tester, services, const LibraryScreen(), mode: mode);

      Future<void> menu(String item, String shot) async {
        await tester.tap(find.byTooltip('More').first);
        await settle(tester);
        await tester.tap(find.text(item));
        await settle(tester);
        await shoot(tester, '${shot}_${mode.name}');
        await tester.tap(find.text('Cancel').last);
        await settle(tester);
      }

      await menu('Rename', 'dialog_rename');
      await menu('Move to folder…', 'dialog_move');
      await menu('Change cover', 'dialog_cover');

      await tester.tap(find.byTooltip('New folder').last);
      await settle(tester);
      await shoot(tester, 'dialog_folder_${mode.name}');
      await tester.tap(find.text('Cancel').last);
      await settle(tester);

      await tester.tap(find.text('Trash').first);
      await settle(tester);
      await tester.tap(find.text('Empty Trash'));
      await settle(tester);
      await shoot(tester, 'dialog_empty_trash_${mode.name}');
      await tester.tap(find.text('Cancel').last);
      await settle(tester);

      final done = Completer<void>();
      unawaited(
        runWithSteps(ctx(tester), 'Exporting', subject: 'Physics — Mechanics.pdf', (progress) {
          progress.step(41, 120, stage: 'Writing PDF…');
          return done.future;
        }),
      );
      await settle(tester);
      await shoot(tester, 'dialog_progress_${mode.name}');
      done.complete();
      await settle(tester);
      expect(tester.takeException(), isNull);
    });
  }

  for (final (name, size, dpr) in [sizes[0], sizes[2]]) {
    testWidgets('library selection $name', (tester) async {
      setWindow(tester, size, dpr: dpr);
      final services = seededServices();
      addTearDown(services.dispose);
      await pumpApp(tester, services, const LibraryScreen());
      await tester.tap(find.byTooltip('Select notebooks'));
      await settle(tester);
      await tester.tap(find.text('Travel plans'));
      await tester.tap(find.text('Spanish vocabulary'));
      await settle(tester);
      expect(tester.takeException(), isNull);
      await shoot(tester, 'select_$name');
    });
  }

  testWidgets('empty states phone', (tester) async {
    setWindow(tester, const Size(390, 844), dpr: 2);
    final services = seededServices();
    addTearDown(services.dispose);
    await pumpApp(tester, services, const LibraryScreen());
    await tester.tap(find.text('Sketches'));
    await settle(tester);
    await shoot(tester, 'empty_folder_phone');
    await tester.tap(find.text('Library').last);
    await settle(tester);
    await tester.enterText(find.byType(TextField), 'zzz');
    await settle(tester);
    await shoot(tester, 'empty_search_phone');
    await tester.enterText(find.byType(TextField), '');
    await settle(tester);
    await tester.tap(find.byTooltip('More').first);
    await settle(tester);
    await tester.tap(find.text('Change cover'));
    await settle(tester);
    await shoot(tester, 'cover_sheet_phone');
    expect(tester.takeException(), isNull);
  });

  for (final (name, size, dpr) in [sizes[0], sizes[2]]) {
    testWidgets('large text $name', (tester) async {
      setWindow(tester, size, dpr: dpr);
      final services = seededServices();
      addTearDown(services.dispose);
      await pumpApp(tester, services, const LibraryScreen(), textScale: 1.3);
      expect(tester.takeException(), isNull);
      await shoot(tester, 'large_library_$name');
      await tester.tap(find.text('New').last);
      await settle(tester);
      expect(tester.takeException(), isNull);
      await shoot(tester, 'large_new_$name');
    });

    testWidgets('large text settings $name', (tester) async {
      setWindow(tester, size, dpr: dpr);
      final services = seededServices();
      addTearDown(services.dispose);
      await pumpApp(tester, services, const SettingsScreen(), textScale: 1.3);
      expect(tester.takeException(), isNull);
      await shoot(tester, 'large_settings_$name');
    });
  }
}
