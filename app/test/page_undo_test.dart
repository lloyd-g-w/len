import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/ui/app_theme.dart';

import 'support/page_actions.dart';

/// Page-level changes are steps of the notebook's undo history
/// (UX_AUDIT round 4, P1-7).
void main() {
  late AppServices s;
  late Notebook nb;
  List<NotebookPage> pages() => s.pages.pagesOf(nb.id);
  List<PaperStyle> styles() => [for (final p in pages()) p.paper.style];

  Future<void> pump(WidgetTester tester) async {
    tester.view
      ..physicalSize = const Size(1280, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    s = AppServices.create(AppDatabase.inMemory());
    addTearDown(s.dispose);
    nb = s.notebooks.create(
      title: 'Physics',
      kind: NotebookKind.paged,
      paper: PaperStyle.collegeRuled,
      coverColor: 0,
      firstPage: const PageTemplate(paper: Paper(PaperStyle.collegeRuled)),
    );
    s.pages.addPage(
      nb.id,
      template: const PageTemplate(paper: Paper(PaperStyle.dotted), color: PaperColor.cream),
    );
    s.pages.addPage(nb.id, template: const PageTemplate(paper: Paper(PaperStyle.gridLarge)));
    await tester.pumpWidget(
      AppScope(
        services: s,
        child: MaterialApp(
          theme: AppTheme.light(),
          home: EditorScreen(notebook: nb),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> undo(WidgetTester tester) async {
    await tester.tap(find.byTooltip('Undo (Ctrl+Z)'));
    await tester.pumpAndSettle();
  }

  Future<void> redo(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  Future<void> menu(WidgetTester tester, String item) async {
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Page'));
    await tester.pumpAndSettle();
    await tester.tap(find.text(item).last);
    await tester.pumpAndSettle();
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump();
  }

  testWidgets('a template applied to all pages is undone and redone', (tester) async {
    await pump(tester);
    final before = styles();
    final colours = [for (final p in pages()) p.paperColor];

    await menu(tester, 'Change template…');
    await tester.ensureVisible(find.text('Music staff'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Music staff'));
    await tester.tap(find.text('Apply to all pages'));
    await tester.pumpAndSettle();
    expect(styles(), everyElement(PaperStyle.music));
    expect(find.text('Template changed on 3 pages'), findsOneWidget);

    await undo(tester);
    expect(styles(), before);
    expect([for (final p in pages()) p.paperColor], colours);

    await redo(tester);
    expect(styles(), everyElement(PaperStyle.music));

    // The snack bar's Undo takes it back too, once.
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(styles(), before);
    await close(tester);
  });

  testWidgets('bookmarks, added pages and deletions are undo steps in order', (tester) async {
    await pump(tester);
    final original = [for (final p in pages()) p.id];

    await menu(tester, 'Bookmark page');
    expect(pages()[0].bookmarked, isTrue);
    await addPageAfter(tester);
    expect(pages(), hasLength(4));
    await menu(tester, 'Delete page'); // The added page, now current.
    expect([for (final p in pages()) p.id], original);

    await undo(tester); // The deletion.
    expect(pages(), hasLength(4));
    await undo(tester); // The addition.
    expect([for (final p in pages()) p.id], original);
    expect(pages()[0].bookmarked, isTrue);
    await undo(tester); // The bookmark.
    expect(pages()[0].bookmarked, isFalse);

    await redo(tester);
    await redo(tester);
    expect(pages()[0].bookmarked, isTrue);
    expect(pages(), hasLength(4));
    await close(tester);
  });

  testWidgets('moving a page in the overview is undone in the editor', (tester) async {
    await pump(tester);
    final original = [for (final p in pages()) p.id];
    await tester.tap(find.byTooltip('All pages'));
    await tester.pumpAndSettle();

    final from = tester.getCenter(find.byKey(const ValueKey('page-tile-2')));
    final to = tester.getCenter(find.byKey(const ValueKey('page-tile-0')));
    final gesture = await tester.startGesture(from);
    await tester.pump(const Duration(milliseconds: 400));
    await gesture.moveTo(from + const Offset(-10, 0));
    await tester.pump();
    await gesture.moveTo(to);
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();
    expect([for (final p in pages()) p.id], [original[2], original[0], original[1]]);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await undo(tester);
    expect([for (final p in pages()) p.id], original);
    await close(tester);
  });
}
