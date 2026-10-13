import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/preferences.dart';

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

  testWidgets('desktop: Ctrl-click, Shift-click and Ctrl+A select', (tester) async {
    await pumpSeeded(tester, (s) {
      for (final t in ['Algebra', 'Biology', 'Chemistry', 'Drawing']) {
        addNotebook(s, t);
      }
      s.preferences.librarySort = LibrarySort.name;
    });
    Future<void> click(String title, LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(key);
      await tester.tap(find.text(title));
      await tester.sendKeyUpEvent(key);
      await tester.pumpAndSettle();
    }

    await click('Algebra', LogicalKeyboardKey.controlLeft);
    expect(find.text('1 selected'), findsOneWidget);
    await click('Chemistry', LogicalKeyboardKey.shiftLeft);
    expect(find.text('3 selected'), findsOneWidget);
    await click('Biology', LogicalKeyboardKey.controlLeft);
    expect(find.text('2 selected'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsNothing);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyA);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('4 selected'), findsOneWidget);
  });

  testWidgets('searching keeps selection mode and the selected notebooks that match', (
    tester,
  ) async {
    await pumpSeeded(tester, (s) {
      for (final t in ['Algebra', 'Biology', 'Biochemistry', 'Chemistry']) {
        addNotebook(s, t);
      }
    });
    Future<void> ctrlClick(String title) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.tap(find.text(title));
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    await ctrlClick('Algebra');
    await ctrlClick('Biology');
    expect(find.text('2 selected'), findsOneWidget);

    // Narrowing the search keeps selecting; what no longer matches drops out.
    await tester.enterText(find.byType(TextField), 'bio');
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOneWidget);
    await ctrlClick('Biochemistry');
    expect(find.text('2 selected'), findsOneWidget);

    // Clearing the search still selects (both are in the library).
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);
  });
}
