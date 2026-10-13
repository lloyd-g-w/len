import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/features/settings/handwriting_settings.dart';
import 'package:len/ink/recognition/handwriting_recognizer.dart';
import 'package:len/ink/recognition/recognition_languages.dart';
import 'package:len/ui/app_switch.dart';
import 'package:len/ui/app_theme.dart';

import 'support/fake_recognizer.dart';

Future<AppServices> pumpSettings(WidgetTester tester, FakeRecognizer recognizer) async {
  tester.view
    ..physicalSize = const Size(800, 1400)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final services = AppServices.create(AppDatabase.inMemory(), recognizer: recognizer);
  addTearDown(services.dispose);
  addTearDown(() => tester.pumpWidget(const SizedBox()));
  await tester.pumpWidget(
    AppScope(
      services: services,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(
            child: HandwritingSettings(recognition: services.recognition),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return services;
}

void main() {
  testWidgets('language, indexing switch and model download', (tester) async {
    final recognizer = FakeRecognizer(downloaded: false);
    final services = await pumpSettings(tester, recognizer);
    final recognition = services.recognition;
    // Indexing is on by default, so the model came over "Wi-Fi" at start.
    expect(recognizer.downloads, 1);
    // Once on the device, the model needs no row of its own.
    expect(find.text('Handwriting model'), findsNothing);

    await tester.tap(find.text('Language'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deutsch'));
    await tester.pumpAndSettle();
    expect(recognition.language, 'de-DE');
    expect(find.text('Deutsch'), findsOneWidget); // the tile's subtitle

    await tester.tap(find.byType(AppSwitch));
    await tester.pumpAndSettle();
    expect(recognition.indexingEnabled, isFalse);
    expect(recognition.indexer.isActive, isFalse);
    expect(find.textContaining('Off: search finds'), findsOneWidget);

    // Missing (e.g. removed by Android): offered for download.
    recognizer.downloaded = false;
    await tester.runAsync(recognition.refreshModel);
    await tester.pumpAndSettle();
    expect(recognition.modelStatus, ModelStatus.missing);
    expect(find.text('Handwriting model'), findsOneWidget);
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();
    expect(recognition.modelStatus, ModelStatus.downloaded);
  });

  testWidgets('the language sheet opens at the current language; ✕ keeps it', (tester) async {
    final services = await pumpSettings(tester, FakeRecognizer());
    final recognition = services.recognition;
    final last = RecognitionLanguages.all.last;
    await recognition.setLanguage(last.tag);
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(390, 700);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Language'));
    await tester.pumpAndSettle();
    final sheet = find.byType(BottomSheet);
    final row = find.descendant(of: sheet, matching: find.text(last.name));
    expect(row, findsOneWidget);
    expect(tester.getRect(row).bottom, lessThan(700), reason: 'scrolled to the current one');
    expect(find.descendant(of: sheet, matching: find.byType(Scrollbar)), findsOneWidget);
    await tester.tap(find.byTooltip('Close'));
    await tester.pumpAndSettle();
    expect(sheet, findsNothing);
    expect(recognition.language, last.tag);
    await tester.pump(const Duration(seconds: 2)); // The scrollbar's fade.
  });

  testWidgets('unsupported platforms explain that Android devices recognise', (tester) async {
    final services = await pumpSettings(tester, FakeRecognizer(supported: false));
    expect(find.textContaining('written on Android is recognised there'), findsOneWidget);
    expect(find.text('Search handwriting'), findsNothing, reason: 'no row that isn\'t a control');
    expect(find.byType(AppSwitch), findsNothing, reason: 'no dead toggles');
    expect(find.text('Language'), findsNothing);

    services.database.db.execute(
      'INSERT INTO ink_text (surface_id, stroke_key, language, text, x, y, w, h) '
      "VALUES ('p', 'k', 'en-US', 'hello', 0, 0, 1, 1)",
    );
    await tester.runAsync(services.recognition.indexer.run); // Notifies when done.
    await tester.pump();
    expect(find.textContaining('finds it here. 1 line so far'), findsOneWidget);
  });
}
