import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/editor/document/page_actions.dart';
import 'package:len/features/editor/document/page_edits.dart';
import 'package:len/features/editor/document/page_models.dart';
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
    await tester.tap(find.text('All pages'));
    await tester.pump();
    await tester.tap(find.text('Apply'));
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

  testWidgets('undoing an added page keeps a page when the others went elsewhere', (tester) async {
    await pump(tester);
    await addPageAfter(tester);
    final added = pages()[1];
    // Another device deletes every other page.
    for (final p in pages()) {
      if (p.id != added.id) s.notebooks.deletePage(p.id);
    }
    await undo(tester); // The addition.
    expect(pages(), hasLength(1), reason: 'a notebook keeps a page');
    expect(pages().single.id, isNot(added.id));
    expect(pages().single.paper.style, PaperStyle.collegeRuled, reason: "the notebook's paper");
    await close(tester);
  });

  testWidgets('a notebook opened without pages starts one in its paper colour', (tester) async {
    await pump(tester);
    await close(tester);
    nb = s.notebooks.create(
      title: 'Yellow',
      kind: NotebookKind.paged,
      paper: PaperStyle.dotted,
      paperColor: PaperColor.cream,
      coverColor: 0,
      empty: true,
    );
    expect(pages(), isEmpty);
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
    expect(pages().single.paper.style, PaperStyle.dotted);
    expect(pages().single.paperColor, PaperColor.cream);
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

  testWidgets('each Ctrl+arrow move in the overview is an undo step', (tester) async {
    await pump(tester);
    final original = [for (final p in pages()) p.id];
    await tester.tap(find.byTooltip('All pages'));
    await tester.pumpAndSettle();
    Focus.of(
      tester.element(
        find
            .descendant(
              of: find.byKey(const ValueKey('page-tile-0')),
              matching: find.byType(Column),
            )
            .first,
      ),
    ).requestFocus();
    await tester.pumpAndSettle();
    for (var i = 0; i < 2; i++) {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await tester.pumpAndSettle();
    }
    expect([for (final p in pages()) p.id], [original[1], original[2], original[0]]);

    await tester.pageBack();
    await tester.pumpAndSettle();
    await undo(tester);
    expect([for (final p in pages()) p.id], [original[1], original[0], original[2]]);
    await undo(tester);
    expect([for (final p in pages()) p.id], original);
    await close(tester);
  });

  testWidgets('duplicating several pages in the overview is one undo step', (tester) async {
    await pump(tester);
    final original = [for (final p in pages()) p.id];
    await tester.tap(find.byTooltip('All pages'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('page-tile-0')));
    await tester.tap(find.byKey(const ValueKey('page-tile-2')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicate'));
    await tester.pumpAndSettle();
    expect(styles(), [
      PaperStyle.collegeRuled,
      PaperStyle.collegeRuled,
      PaperStyle.dotted,
      PaperStyle.gridLarge,
      PaperStyle.gridLarge,
    ], reason: 'each copy right after its page');

    await tester.tap(find.byTooltip('Done'));
    await tester.pumpAndSettle();
    await tester.pageBack();
    await tester.pumpAndSettle();
    await undo(tester);
    expect([for (final p in pages()) p.id], original);
    await redo(tester);
    expect(pages(), hasLength(5));
    await close(tester);
  });

  testWidgets('pages inserted from elsewhere (a PDF) are one undo step', (tester) async {
    await pump(tester);
    final original = [for (final p in pages()) p.id];
    final models = PageModels();
    addTearDown(models.dispose);
    final actions = PageActions(s, nb.id);
    final shown = <String?>[];
    final edits = PageEdits(actions: actions, models: models, shown: ({keep}) => shown.add(keep));
    // As the PDF importer inserts them, then made undoable.
    final inserted = actions.addAll([
      PageActions.blankAfter(pages().first),
      PageActions.blankAfter(pages().first),
    ], after: pages().first);
    edits.added(inserted);
    expect(shown, [inserted.first.id]);
    expect(models.canUndo, isTrue);

    models.undo();
    expect([for (final p in pages()) p.id], original);
    models.redo();
    expect(pages().map((p) => p.id), containsAll(inserted.map((p) => p.id)));
    await close(tester);
  });
}
