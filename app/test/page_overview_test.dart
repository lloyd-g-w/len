import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/surface_copier.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/editor/document/page_overview.dart';
import 'package:len/ui/app_theme.dart';

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

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete 2 pages?'), findsOneWidget);
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(deletedMany, [pages[1].id, pages[3].id]);
    expect(find.text('Select'), findsOneWidget); // Selection mode ended.
    expect(tester.takeException(), isNull);
  });
}
