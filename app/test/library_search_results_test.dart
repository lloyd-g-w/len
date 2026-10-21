import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/library/library_screen.dart';

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
  await tester.pump(const Duration(milliseconds: 200)); // Debounce.
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
}
