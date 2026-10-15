import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/surface_copier.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/documents/overview/page_moves.dart';
import 'package:len/features/editor/document/page_overview.dart';
import 'package:len/ui/app_theme.dart';

import 'keyboard_shortcuts_test.dart' as keys show boundNow, group, unbound;
import 'support/semantics_actions.dart';

void main() {
  testWidgets('selection mode: select, bookmark, delete many; add page tile', (tester) async {
    tester.view
      ..physicalSize = const Size(1000, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = AppServices.create(AppDatabase.inMemory());
    addTearDown(s.dispose);
    final nb = s.notebooks.create(
      title: 'N',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    for (var i = 0; i < 4; i++) {
      s.pages.addPage(nb.id, template: const PageTemplate());
    }
    final commands = <(PageCommand, String)>[];
    List<String>? deletedMany;
    List<String>? exported;
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: PageOverview(
          currentPage: 0,
          copier: SurfaceCopier(s.strokes, elements: s.elements),
          handlers: OverviewHandlers(
            load: () => s.pages.pagesOf(nb.id),
            move: s.pages.move,
            command: (context, command, page) async {
              commands.add((command, page.id));
              if (command == PageCommand.bookmark) {
                s.pages.setBookmarked(page.id, !page.bookmarked);
              }
            },
            deleteMany: (context, pages) async => deletedMany = [for (final p in pages) p.id],
            exportMany: (context, pages) async => exported = [for (final p in pages) p.id],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final pages = s.pages.pagesOf(nb.id);
    expect(find.text('5 pages'), findsOneWidget);

    await tester.tap(find.text('Add page'));
    await tester.pumpAndSettle();
    expect(commands.single, (PageCommand.insertAfter, pages.last.id));
    // Held down, it asks for a template.
    await tester.longPress(find.text('Add page'));
    await tester.pumpAndSettle();
    expect(commands.last, (PageCommand.insertWithTemplate, pages.last.id));

    // A tile's ⋯ is the one page menu (the editor's ⋯ → Page too).
    await tester.tap(find.byTooltip('Page 1 options'));
    await tester.pumpAndSettle();
    for (final c in PageCommand.menu) {
      expect(find.text(c.labelFor()), findsOneWidget, reason: c.name);
    }
    await tester.longPress(find.text('Add page after'));
    await tester.pumpAndSettle();
    expect(find.text('Duplicate page'), findsNothing);
    expect(commands.last, (PageCommand.insertWithTemplate, pages.first.id));
    // Screen readers offer it as an action on the row.
    final semantics = tester.ensureSemantics();
    await tester.tap(find.byTooltip('Page 2 options'));
    await tester.pumpAndSettle();
    await performCustomAction(tester, 'Add page after', 'Add page with template');
    expect(find.text('Duplicate page'), findsNothing);
    expect(commands.last, (PageCommand.insertWithTemplate, pages[1].id));
    semantics.dispose();
    commands.clear();

    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    expect(find.text('Select pages'), findsOneWidget);
    expect(find.text('Add page'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('page-tile-1')));
    await tester.tap(find.byKey(const ValueKey('page-tile-3')));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);

    await tester.tap(find.text('Bookmark'));
    await tester.pumpAndSettle();
    expect(s.pages.pagesOf(nb.id).where((p) => p.bookmarked).map((p) => p.id), [
      pages[1].id,
      pages[3].id,
    ]);

    // The Bookmarked filter deselects what it hides; Select all picks
    // the shown pages only.
    await tester.tap(find.byKey(const ValueKey('page-tile-0')));
    await tester.pumpAndSettle();
    expect(find.text('3 selected'), findsOneWidget);
    await tester.tap(find.text('Bookmarked'));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);
    await tester.tap(find.text('Select none'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select all'));
    await tester.pumpAndSettle();
    expect(find.text('2 selected'), findsOneWidget);
    await tester.tap(find.text('All'));
    await tester.pumpAndSettle();

    // Export… hands the selection on (the sheet takes it as the range).
    await tester.tap(find.text('Export…'));
    await tester.pumpAndSettle();
    expect(exported, [pages[1].id, pages[3].id]);
    expect(find.text('Change template…'), findsNothing); // No handler, no command.

    // No question: the deletion offers Undo.
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(deletedMany, [pages[1].id, pages[3].id]);
    expect(find.text('Select'), findsOneWidget); // Selection mode ended.
    expect(tester.takeException(), isNull);
  });

  test('pageStep: a place along, a row across, stopping at the ends', () {
    int step(int from, AxisDirection d, {bool rtl = false}) =>
        pageStep(from, d, columns: 4, count: 10, rtl: rtl);
    expect(step(0, AxisDirection.right), 1);
    expect(step(0, AxisDirection.left), 0);
    expect(step(5, AxisDirection.down), 9);
    expect(step(7, AxisDirection.down), 9);
    expect(step(5, AxisDirection.up), 1);
    expect(step(2, AxisDirection.up), 0);
    expect(step(3, AxisDirection.left, rtl: true), 4);
    expect(pageStep(0, AxisDirection.down, columns: 4, count: 1), 0);
  });

  testWidgets('Ctrl+arrows move the focused page; focus follows, readers hear it', (tester) async {
    tester.view
      ..physicalSize = const Size(1000, 1400)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final s = AppServices.create(AppDatabase.inMemory());
    addTearDown(s.dispose);
    final nb = s.notebooks.create(
      title: 'N',
      kind: NotebookKind.paged,
      paper: PaperStyle.blank,
      coverColor: 0,
    );
    for (var i = 0; i < 7; i++) {
      s.pages.addPage(nb.id, template: const PageTemplate());
    }
    final said = <String>[];
    tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<Object?>(
      SystemChannels.accessibility,
      (message) async {
        final data = (message! as Map<Object?, Object?>)['data']! as Map<Object?, Object?>;
        if (data['message'] case final String text) said.add(text);
        return null;
      },
    );
    addTearDown(
      () => tester.binding.defaultBinaryMessenger.setMockDecodedMessageHandler<Object?>(
        SystemChannels.accessibility,
        null,
      ),
    );
    final original = [for (final p in s.pages.pagesOf(nb.id)) p.id];
    List<int> order() => [for (final p in s.pages.pagesOf(nb.id)) original.indexOf(p.id)];
    await tester.pumpWidget(
      MaterialApp(
        theme: AppTheme.light(),
        home: PageOverview(
          currentPage: 0,
          copier: SurfaceCopier(s.strokes, elements: s.elements),
          handlers: OverviewHandlers(
            load: () => s.pages.pagesOf(nb.id),
            move: s.pages.move,
            command: (context, command, page) async {},
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    // 936 dp across at most 200 + 24 each: 5 columns.
    FocusNode focusOf(int index) => Focus.of(
      tester.element(
        find
            .descendant(of: find.byKey(ValueKey('page-tile-$index')), matching: find.byType(Column))
            .first,
      ),
    );
    Future<void> ctrl(LogicalKeyboardKey key) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(key);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }

    focusOf(1).requestFocus();
    await tester.pumpAndSettle();
    // The shortcut sheet's entry is bound here.
    expect(
      keys.unbound(
        keys.boundNow(tester),
        keys.group('Pages').where((h) => h.label == 'Move page in the overview'),
      ),
      isEmpty,
    );

    await ctrl(LogicalKeyboardKey.arrowRight);
    expect(order(), [0, 2, 1, 3, 4, 5, 6, 7]);
    expect(said.last, 'Page 2 moved to 3');
    expect(focusOf(2).hasPrimaryFocus, isTrue);

    await ctrl(LogicalKeyboardKey.arrowDown); // A row down: 3 → 8.
    expect(order(), [0, 2, 3, 4, 5, 6, 7, 1]);
    expect(said.last, 'Page 3 moved to 8');
    expect(focusOf(7).hasPrimaryFocus, isTrue);

    await ctrl(LogicalKeyboardKey.arrowDown); // Already last: stays, says nothing.
    expect(said, hasLength(2));

    await ctrl(LogicalKeyboardKey.arrowUp);
    await ctrl(LogicalKeyboardKey.arrowLeft);
    expect(order(), [0, 1, 2, 3, 4, 5, 6, 7]);
    expect(said.sublist(2), ['Page 8 moved to 3', 'Page 3 moved to 2']);
    expect(focusOf(1).hasPrimaryFocus, isTrue);

    // Screen readers move it with custom actions.
    final semantics = tester.ensureSemantics();
    final node = tester.getSemantics(find.byKey(const ValueKey('page-tile-1')));
    expect(node.label, startsWith('Page 2'));
    final later = CustomSemanticsAction.getIdentifier(
      const CustomSemanticsAction(label: 'Move later'),
    );
    expect(node.getSemanticsData().customSemanticsActionIds, contains(later));
    node.owner!.performAction(node.id, SemanticsAction.customAction, later);
    await tester.pumpAndSettle();
    expect(order(), [0, 2, 1, 3, 4, 5, 6, 7]);
    semantics.dispose();
  });
}
