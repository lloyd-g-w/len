import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/blob_backend.dart';
import 'package:len/features/settings/font_settings.dart';
import 'package:len/ink/fonts/text_fonts.dart';
import 'package:len/ui/app_theme.dart';

import 'support/font_fixtures.dart';

void main() {
  tearDown(TextFonts.reset);

  testWidgets('a font whose file isn\'t here says so, then shows its sample once loaded', (
    tester,
  ) async {
    final s = AppServices.create(AppDatabase.inMemory(), blobBackend: MemoryBlobBackend());
    addTearDown(s.dispose);
    // A file no other test loads.
    final font = s.sync.engine.repositories.fonts.add(name: 'Later', blob: '7' * 64);
    await tester.runAsync(s.fonts.refresh);
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: SingleChildScrollView(child: FontSettings(fonts: s.fonts)),
        ),
      ),
    );
    const sample = 'The quick brown fox jumps over the lazy dog';
    expect(find.text('Later'), findsOneWidget);
    expect(find.text('Not on this device yet'), findsOneWidget);
    // No sample in Sans passing for the font.
    expect(find.text(sample), findsNothing);

    await tester.runAsync(() => TextFonts.load(font.id, caveatFile()));
    await tester.pump();
    expect(find.text('Not on this device yet'), findsNothing);
    expect(find.text(sample), findsOneWidget);
    // Screen readers hear the font's name, not the pangram.
    expect(find.bySemanticsLabel(sample), findsNothing);
  });

  testWidgets('Remove asks, says it is for every device, and Undo brings the font back', (
    tester,
  ) async {
    final s = AppServices.create(AppDatabase.inMemory(), blobBackend: MemoryBlobBackend());
    addTearDown(s.dispose);
    s.sync.engine.repositories.fonts.add(name: 'Gone soon', blob: '6' * 64);
    await tester.runAsync(s.fonts.refresh);
    await tester.pumpWidget(
      AppScope(
        services: s,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: Scaffold(
            body: SingleChildScrollView(child: FontSettings(fonts: s.fonts)),
          ),
        ),
      ),
    );
    await tester.tap(find.byTooltip('Remove “Gone soon”'));
    await tester.pumpAndSettle();
    expect(find.text('Remove “Gone soon”?'), findsOneWidget);
    expect(find.textContaining('shown in Sans on all your devices'), findsOneWidget);
    await tester.tap(find.text('Remove'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(s.fonts.fonts, isEmpty);
    expect(find.text('Gone soon'), findsNothing);
    expect(find.text('Removed “Gone soon”'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pumpAndSettle();
    expect(s.fonts.fonts.map((f) => f.name), ['Gone soon']);
    expect(find.text('Gone soon'), findsOneWidget);
  });
}
