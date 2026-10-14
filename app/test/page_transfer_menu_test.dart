import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/ui/app_theme.dart';

/// Moving or copying pages from the editor's page menu (UX_AUDIT R8-2),
/// the picker's captions (R8-6) and every page (R8-3).
void main() {
  late AppServices s;
  setUp(() => s = AppServices.create(AppDatabase.inMemory()));
  tearDown(() => s.dispose());

  Notebook paged(String title, {String? folderId}) => s.notebooks.create(
    title: title,
    kind: NotebookKind.paged,
    paper: PaperStyle.wideRuled,
    coverColor: 0,
    folderId: folderId,
  );

  Future<void> pumpEditor(WidgetTester tester, Notebook notebook) async {
    tester.view
      ..physicalSize = const Size(1280, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      AppScope(
        services: s,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: EditorScreen(notebook: notebook),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openFromMenu(WidgetTester tester) async {
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Page'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Move or copy page…'));
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  testWidgets('⋯ › Page › Move or copy page… sends the current page', (tester) async {
    final school = s.folders.create(name: 'School', color: 0);
    final maths = s.folders.create(name: 'Maths', color: 0, parentId: school.id);
    final source = paged('Physics');
    final first = s.pages.pagesOf(source.id).single;
    s.pages.addPage(source.id);
    final target = paged('Week 3', folderId: maths.id);
    await pumpEditor(tester, source);

    await openFromMenu(tester);
    expect(find.text('Move or copy 1 page'), findsOneWidget);
    // Where it lives, as the library says it.
    expect(find.text('School › Maths'), findsOneWidget);
    await tester.tap(find.text('Week 3'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Move'));
    await tester.pumpAndSettle();
    expect(find.text('Moved 1 page to “Week 3”'), findsOneWidget);
    expect(s.pages.pagesOf(source.id), hasLength(1));
    expect(s.pages.pagesOf(source.id).single.id, isNot(first.id));
    expect(s.pages.pagesOf(target.id), hasLength(2));
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('a notebook’s only page can be copied, not moved', (tester) async {
    final source = paged('Physics');
    final target = paged('Notes');
    await pumpEditor(tester, source);

    await openFromMenu(tester);
    expect(find.textContaining('A notebook needs at least one page'), findsOneWidget);
    await tester.tap(find.text('Notes'));
    await tester.pumpAndSettle();
    final move = tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Move'));
    expect(move.onPressed, isNull);
    await tester.tap(find.widgetWithText(OutlinedButton, 'Copy'));
    await tester.pumpAndSettle();
    expect(s.pages.pagesOf(source.id), hasLength(1));
    expect(s.pages.pagesOf(target.id), hasLength(2));
    await close(tester);
  });

  testWidgets('a long list gets a filter', (tester) async {
    final source = paged('Physics');
    for (var i = 0; i < 14; i++) {
      paged('Notebook $i');
    }
    paged('Biology');
    await pumpEditor(tester, source);

    await openFromMenu(tester);
    await tester.enterText(find.byKey(const ValueKey('destination-filter')), 'bio');
    await tester.pumpAndSettle();
    expect(find.text('Biology'), findsOneWidget);
    expect(find.text('Notebook 1'), findsNothing);
    expect(find.text('New notebook…'), findsOneWidget);
    await close(tester);
  });
}
