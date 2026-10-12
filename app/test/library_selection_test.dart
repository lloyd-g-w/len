import 'package:flutter_test/flutter_test.dart';

import 'library_ui_test.dart' show addNotebook, pumpSeeded;

void main() {
  testWidgets('select notebooks: favourite, move, trash with undo, restore', (tester) async {
    final s = await pumpSeeded(tester, (s) {
      s.folders.create(name: 'School', color: 0xFF0CA678);
      for (final t in ['Algebra', 'Biology', 'Chemistry']) {
        addNotebook(s, t);
      }
    });
    final ids = {for (final n in s.notebooks.list()) n.title: n.id};
    String id(String title) => ids[title]!;

    await tester.tap(find.byTooltip('View'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select…').last);
    await tester.pumpAndSettle();
    expect(find.text('Select notebooks'), findsOneWidget);
    expect(find.byTooltip('New notebook'), findsNothing); // No FAB while selecting.

    await tester.tap(find.text('Algebra'));
    await tester.tap(find.text('Biology'));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.byTooltip('Add to favourites'));
    await tester.pumpAndSettle();
    expect(s.notebooks.get(id('Algebra'))!.favorite, isTrue);
    expect(s.notebooks.get(id('Biology'))!.favorite, isTrue);
    expect(s.notebooks.get(id('Chemistry'))!.favorite, isFalse);

    await tester.tap(find.byTooltip('Move to folder…'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('School').last);
    await tester.pumpAndSettle();
    final school = s.folders.list().single.id;
    expect(s.notebooks.get(id('Algebra'))!.folderId, school);
    expect(find.text('2 selected'), findsNothing); // Done after moving.

    await tester.tap(find.byTooltip('View'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select…').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Select all'));
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget); // Only Chemistry is here now.
    await tester.tap(find.byTooltip('Move to trash'));
    await tester.pumpAndSettle();
    expect(s.notebooks.get(id('Chemistry'))!.isTrashed, isTrue);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(s.notebooks.get(id('Chemistry'))!.isTrashed, isFalse);
    expect(tester.takeException(), isNull);
  });
}
