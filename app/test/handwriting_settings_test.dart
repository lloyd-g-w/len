import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/features/settings/handwriting_settings.dart';
import 'package:len/ink/recognition/handwriting_recognizer.dart';
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
  testWidgets('language, indexing switch and model download / delete', (tester) async {
    final recognizer = FakeRecognizer(downloaded: false);
    final services = await pumpSettings(tester, recognizer);
    final recognition = services.recognition;
    // Indexing is on by default, so the model came over "Wi-Fi" at start.
    expect(recognizer.downloads, 1);
    expect(find.textContaining('is on this device'), findsOneWidget);

    await tester.tap(find.text('Language'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Deutsch'));
    await tester.pumpAndSettle();
    expect(recognition.language, 'de-DE');
    expect(find.text('Deutsch'), findsOneWidget); // the tile's subtitle

    await tester.tap(find.text('Delete…'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(recognition.modelStatus, ModelStatus.missing);
    expect(find.text('Download'), findsOneWidget);
    await tester.tap(find.text('Download'));
    await tester.pumpAndSettle();
    expect(recognition.modelStatus, ModelStatus.downloaded);

    await tester.tap(find.byType(Switch));
    await tester.pumpAndSettle();
    expect(recognition.indexingEnabled, isFalse);
    expect(recognition.indexer.isActive, isFalse);
    expect(find.textContaining('Off: search finds'), findsOneWidget);
  });

  testWidgets('unsupported platforms explain why', (tester) async {
    await pumpSettings(tester, FakeRecognizer(supported: false));
    expect(find.text('Not available here'), findsOneWidget);
    expect(find.text('Not here'), findsOneWidget);
    expect(find.byType(Switch), findsNothing);
  });
}
