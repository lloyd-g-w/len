@Tags(['screenshots'])
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/features/library/library_screen.dart';

import 'screenshot_harness.dart';

/// A brand-new user (UX_AUDIT Round 14): the empty library, the first
/// notebook's form and its first page, on a phone, a tablet and a desktop.
void main() {
  setUpAll(loadRealFonts);

  const sizes = [
    ('phone', Size(390, 844), 2.0),
    ('tablet', Size(1280, 800), 1.0),
    ('desktop', Size(1440, 900), 1.0),
  ];

  for (final (name, size, dpr) in sizes) {
    testWidgets('first run $name', (tester) async {
      setWindow(tester, size, dpr: dpr);
      final services = AppServices.create(AppDatabase.inMemory());
      addTearDown(services.dispose);
      addTearDown(() => tester.pumpWidget(const SizedBox()));
      await pumpApp(tester, services, const LibraryScreen());
      await shoot(tester, 'fr_library_$name');
      await tester.tap(find.text('New notebook').last);
      await settle(tester);
      await shoot(tester, 'fr_new_$name');
      await tester.tap(find.text('Create'));
      await settle(tester);
      await settle(tester);
      expect(tester.takeException(), isNull);
      await shoot(tester, 'fr_first_page_$name');
      await tester.tap(find.byTooltip('All pages'));
      await settle(tester);
      await tester.tap(find.text('Bookmarked'));
      await settle(tester);
      await shoot(tester, 'fr_bookmarks_$name');
      await tester.tap(find.text('Outline'));
      await settle(tester);
      await shoot(tester, 'fr_outline_$name');
      await tester.binding.handlePopRoute();
      await settle(tester);
      await tester.tap(find.byTooltip('More options'));
      await settle(tester);
      await shoot(tester, 'fr_more_$name');
      await tester.tap(find.textContaining('Search').last);
      await settle(tester);
      await tester.enterText(find.byType(TextField).last, 'zzz');
      await settle(tester);
      await shoot(tester, 'fr_search_$name');
      expect(tester.takeException(), isNull);
    });

    testWidgets('first run sections $name', (tester) async {
      setWindow(tester, size, dpr: dpr);
      final services = AppServices.create(AppDatabase.inMemory());
      addTearDown(services.dispose);
      await pumpApp(tester, services, const LibraryScreen());
      await openLibrarySection(tester, 'Favourites');
      await shoot(tester, 'fr_favourites_$name');
      await openLibrarySection(tester, 'Trash');
      await shoot(tester, 'fr_trash_$name');
      expect(tester.takeException(), isNull);
    });
  }
}
