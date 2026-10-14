import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/domain/preferences.dart';
import 'package:len/features/library/folder_tile.dart';
import 'package:len/features/library/notebook_card.dart';
import 'package:len/features/library/notebook_list_tile.dart';
import 'package:len/ui/design_tokens.dart';

import 'library_ui_test.dart' show addNotebook, pumpSeeded;

/// Found in the real web build (tool/web_explore.py): once the ⋯ showed
/// (hover, focus, always on touch) a card was a group, not a button, for
/// screen readers, and the hidden ⋯ was out of their reach. Folder tiles
/// and list rows had the same trouble.
void main() {
  tearDown(() => Targets.debugTouchFirst = null);

  /// Checks that [item] is a button named [name] (its first line), with a
  /// ⋯ of its own beside it, before and while a mouse hovers it.
  Future<void> expectButton(
    WidgetTester tester,
    Type item,
    String name,
    void Function(AppServices s) seed,
  ) async {
    final semantics = tester.ensureSemantics();
    await pumpSeeded(tester, seed);
    final widget = find.byType(item);
    expect(widget, findsOne);

    void check() {
      final node = tester.getSemantics(
        find.descendant(of: widget, matching: find.bySemanticsLabel(RegExp('^$name\n'))).first,
      );
      final data = node.getSemanticsData();
      expect(data.flagsCollection.isButton, isTrue);
      expect(data.hasAction(SemanticsAction.tap), isTrue);
      expect(data.label, startsWith('$name\n'));
      // The ⋯ is its own button, not inside the item's, reachable while
      // hidden too.
      final more = find.semantics.byPredicate(
        (n) => n.getSemanticsData().tooltip == 'More' && !n.isInvisible,
      );
      expect(more, findsOne);
      for (SemanticsNode? up = more.evaluate().single.parent; up != null; up = up.parent) {
        expect(up, isNot(same(node)));
      }
    }

    check();
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: tester.getCenter(widget));
    await tester.pumpAndSettle();
    check();
    await mouse.removePointer();
    semantics.dispose();
  }

  for (final touch in [false, true]) {
    final on = touch ? 'on touch' : 'with a mouse';

    testWidgets('a card is a button named by its title, beside its ⋯ ($on)', (tester) async {
      Targets.debugTouchFirst = touch;
      await expectButton(tester, NotebookCard, 'Algebra', (s) => addNotebook(s, 'Algebra'));
    });

    testWidgets('a folder tile is a button named by its name, beside its ⋯ ($on)', (tester) async {
      Targets.debugTouchFirst = touch;
      await expectButton(
        tester,
        FolderTile,
        'School',
        (s) => s.folders.create(name: 'School', color: 0xFF495057),
      );
    });

    testWidgets('a list row is a button named by its title, beside its ⋯ ($on)', (tester) async {
      Targets.debugTouchFirst = touch;
      await expectButton(tester, NotebookListTile, 'Algebra', (s) {
        addNotebook(s, 'Algebra');
        s.preferences.libraryLayout = LibraryLayout.list;
      });
    });
  }

  testWidgets('a folder tile opens on tap; taps on a list row\'s title reach the row', (
    tester,
  ) async {
    Targets.debugTouchFirst = false;
    await pumpSeeded(tester, (s) {
      final school = s.folders.create(name: 'School', color: 0xFF495057);
      addNotebook(s, 'Algebra', folderId: school.id);
      s.preferences.libraryLayout = LibraryLayout.list;
    });
    await tester.tap(find.descendant(of: find.byType(FolderTile), matching: find.text('School')));
    await tester.pumpAndSettle();
    final row = find.byType(NotebookListTile);
    expect(row, findsOne);
    // Ctrl-click selects: the tap reached the row's ink under the title.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tapAt(tester.getCenter(find.descendant(of: row, matching: find.text('Algebra'))));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(find.text('1 selected'), findsOne);
  });
}
