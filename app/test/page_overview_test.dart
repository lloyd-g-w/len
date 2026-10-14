import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/surface_copier.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/editor/document/page_overview.dart';
import 'package:len/ui/app_theme.dart';

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
}
