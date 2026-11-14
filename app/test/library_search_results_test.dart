import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/library/library_screen.dart';
import 'package:len/ui/app_theme.dart';

import 'content_golden_test.dart' show loadFonts;
import 'search_ui_test.dart' show textBox;
import 'ui_library_test.dart' show pumpLibrary;

/// A "Lecture 4" in Year 1 › Calculus and one in Year 1 › Physics, both
/// mentioning integration, and a reader at the top level.
AppServices lectures() {
  final s = AppServices.create(AppDatabase.inMemory());
  final year = s.folders.create(name: 'Year 1', color: 0xFF1C7ED6);
  final calculus = s.folders.create(name: 'Calculus', parentId: year.id, color: 0xFF2F9E44);
  final physics = s.folders.create(name: 'Physics', parentId: year.id, color: 0xFFE8590C);
  void notebook(String title, String? folder, String text) {
    final n = s.notebooks.create(
      title: title,
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0xFF2F9E44,
      folderId: folder,
    );
    s.elements.save([
      textBox('${n.id}-t', s.pages.pagesOf(n.id).single.id, text, const Offset(80, 80)),
    ]);
  }

  notebook('Lecture 4', calculus.id, 'Integration by parts');
  notebook('Lecture 4', physics.id, 'Integration over a volume');
  notebook('Reader', null, 'Integration of pressure');
  return s;
}

Future<void> search(WidgetTester tester, String query) async {
  await tester.enterText(find.widgetWithText(TextField, 'Search'), query);
  await tester.pump(); // The library rebuilds the results…
  await tester.pump(const Duration(milliseconds: 200)); // …which wait for typing to pause.
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('each notebook of page matches says which folder it is in', (tester) async {
    await loadFonts();
    await pumpLibrary(tester, services: lectures(), size: const Size(1024, 600));
    await search(tester, 'integration');
    expect(find.text('Lecture 4'), findsNWidgets(2));
    expect(find.text('Year 1 › Calculus'), findsOneWidget);
    expect(find.text('Year 1 › Physics'), findsOneWidget);
    expect(find.text('Library'), findsWidgets, reason: 'the top level, as in Notebooks');
    await expectLater(
      find.byType(LibraryScreen),
      matchesGoldenFile('goldens/search_library_paths.png'),
    );
  });

  testWidgets('page matches are touch targets', (tester) async {
    Targets.debugTouchFirst = true;
    addTearDown(() => Targets.debugTouchFirst = null);
    await pumpLibrary(tester, services: lectures(), size: const Size(1024, 600));
    await search(tester, 'integration');
    final row = find.ancestor(
      of: find.textContaining('by parts', findRichText: true),
      matching: find.byType(InkWell),
    );
    expect(tester.getSize(row.first).height, greaterThanOrEqualTo(Targets.touch));
  });

  testWidgets('at large text on a phone the page goes above the snippet', (tester) async {
    await loadFonts();
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpLibrary(tester, services: lectures(), size: const Size(390, 844));
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    await search(tester, 'integration');
    final page = tester.getRect(find.text('Page 1').first);
    final snippet = tester.getRect(find.textContaining('by parts', findRichText: true));
    expect(page.bottom, lessThanOrEqualTo(snippet.top), reason: 'on a line of its own');
    expect(snippet.left, page.left, reason: 'the snippet takes the whole width');
    await expectLater(
      find.byType(LibraryScreen),
      matchesGoldenFile('goldens/search_library_phone_large_text.png'),
    );

    // At 1× the page keeps its column beside the snippet.
    tester.platformDispatcher.textScaleFactorTestValue = 1;
    await tester.pumpAndSettle();
    final beside = tester.getRect(find.text('Page 1').first);
    expect(
      beside.right,
      lessThan(tester.getRect(find.textContaining('by parts', findRichText: true)).left),
    );
  });

  testWidgets('more page matches than are listed say so', (tester) async {
    final services = AppServices.create(AppDatabase.inMemory());
    for (var i = 0; i < 320; i++) {
      final n = services.notebooks.create(
        title: 'Notes $i',
        kind: NotebookKind.paged,
        paper: PaperStyle.blank,
        coverColor: 0,
      );
      final page = services.pages.pagesOf(n.id).single.id;
      services.elements.save([textBox('g$i', page, 'Gluon $i', Offset.zero)]);
    }
    await pumpLibrary(tester, services: services, size: const Size(1024, 600));
    await search(tester, 'gluon');
    expect(find.text('300+ matches'), findsOneWidget, reason: 'the best 300 of 320');
    await search(tester, 'gluon 123');
    expect(find.text('1 match'), findsOneWidget);
  });
}
