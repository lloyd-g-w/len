import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/surface_copier.dart';
import 'package:len/domain/link_target.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/features/editor/tools/content_layer.dart';
import 'package:len/features/library/library_screen.dart';
import 'package:len/features/library/recent_row.dart';

import '../support/selection_actions.dart';
import 'screenshot_harness.dart';

/// Organisation features with real fonts: the editor's outline panel and
/// links, on tablet and phone, light and dark; the library's Recent row
/// at its edges; moving or copying pages from the editor.
void main() {
  setUpAll(loadRealFonts);

  const phone = ('phone', Size(390, 844), 2.0);
  const tablet = ('tablet', Size(1280, 800), 1.0);

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder, warnIfMissed: false);
    await settle(tester);
  }

  for (final mode in [ThemeMode.light, ThemeMode.dark]) {
    for (final (name, size, dpr) in [tablet, phone]) {
      testWidgets('editor outline, links $name ${mode.name}', (tester) async {
        setWindow(tester, size, dpr: dpr);
        final s = seededServices();
        addTearDown(s.dispose);
        final nb = s.notebooks.list().firstWhere((n) => n.title == 'Physics — Mechanics');
        s.pages.addPage(nb.id, template: const PageTemplate(paper: Paper(PaperStyle.wideRuled)));
        s.pages.addPage(nb.id, template: const PageTemplate(paper: Paper(PaperStyle.wideRuled)));
        final pages = s.pages.pagesOf(nb.id);
        final intro = s.outline.add(notebookId: nb.id, pageId: pages[0].id, title: 'Mechanics');
        s.outline.add(
          notebookId: nb.id,
          pageId: pages[0].id,
          title: 'Newton’s laws',
          parentId: intro.id,
        );
        s.outline.add(
          notebookId: nb.id,
          pageId: pages[1].id,
          title: 'Momentum and impulse',
          parentId: intro.id,
        );
        s.outline.add(notebookId: nb.id, pageId: pages[2].id, title: 'Exercises');
        final ink = SurfaceCopier(s.strokes).loadAll(pages[0].id);
        final line = ink.take(4).map((x) => x.bounds).reduce((a, b) => a.expandToInclude(b));
        s.elements.save([
          LinkElements.create(
            id: 'link',
            surfaceId: pages[0].id,
            rect: line.inflate(4),
            target: PageLinkTarget(notebookId: nb.id, pageId: pages[2].id),
            createdAt: 1,
            z: -1,
          ),
        ]);
        await pumpApp(tester, s, EditorScreen(notebook: nb), mode: mode);
        await shoot(tester, 'o_editor_link_${name}_${mode.name}');

        await tap(tester, find.byTooltip('All pages'));
        await tap(tester, find.text('Outline'));
        await shoot(tester, 'o_outline_panel_${name}_${mode.name}');
        await tester.binding.handlePopRoute();
        await settle(tester);

        // A lasso selection's menu with Link….
        final content = tester.widget<ContentLayer>(find.byType(ContentLayer)).content;
        final model = content.selection.model;
        content.selection.select([for (final x in ink.take(4)) ?model.strokeById(x.id)], const []);
        await settle(tester);
        await shoot(tester, 'o_selection_menu_${name}_${mode.name}');
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }
  }

  testWidgets('outline add dialog and link picker (tablet light)', (tester) async {
    setWindow(tester, tablet.$2);
    final s = seededServices();
    addTearDown(s.dispose);
    final nb = s.notebooks.list().firstWhere((n) => n.title == 'Physics — Mechanics');
    s.pages.addPage(nb.id, template: const PageTemplate(paper: Paper(PaperStyle.wideRuled)));
    s.outline.add(notebookId: nb.id, pageId: s.pages.pagesOf(nb.id).first.id, title: 'Start');
    await pumpApp(tester, s, EditorScreen(notebook: nb));
    await tap(tester, find.byTooltip('All pages'));
    await tap(tester, find.text('Outline'));
    await tap(tester, find.text('Add page 1 to outline'));
    await shoot(tester, 'o_outline_add_tablet_light');
    await tester.binding.handlePopRoute();
    await settle(tester);
    await tester.binding.handlePopRoute();
    await settle(tester);

    final content = tester.widget<ContentLayer>(find.byType(ContentLayer)).content;
    final model = content.selection.model;
    final first = SurfaceCopier(s.strokes).loadAll(s.pages.pagesOf(nb.id).first.id).first;
    content.selection.select([?model.strokeById(first.id)], const []);
    await settle(tester);
    await selectionAction(tester, 'Link…');
    await shoot(tester, 'o_link_menu_tablet_light');
    await tap(tester, find.text('Link to page…'));
    await shoot(tester, 'o_link_page_picker_tablet_light');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  // Recent's edge cases (UX_AUDIT R8-34): nothing in an empty library or
  // when everything is at the top level, gaps filled after trashing, not
  // inside a folder; held sideways, the strip's menu says where each is.
  testWidgets('recent edge cases (phone light)', (tester) async {
    setWindow(tester, phone.$2, dpr: phone.$3);
    final empty = AppServices.create(AppDatabase.inMemory());
    addTearDown(empty.dispose);
    empty.settings.recentNotebooks = ['gone-1', 'gone-2'];
    await pumpApp(tester, empty, const LibraryScreen());
    expect(find.byType(RecentRow), findsNothing);
    await shoot(tester, 'o_recent_empty_library_phone');

    await tester.pumpWidget(const SizedBox()); // A fresh library.
    final s = seededServices();
    addTearDown(s.dispose);
    final byTitle = {for (final n in s.notebooks.list()) n.title: n};
    final trashed = byTitle['Recipes']!;
    s.notebooks.trash(trashed.id);
    s.settings.recentNotebooks = [
      trashed.id,
      byTitle['Meeting notes']!.id,
      byTitle['Ideas']!.id,
      byTitle['Physics — Mechanics']!.id,
    ];
    await pumpApp(tester, s, const LibraryScreen());
    expect(find.byType(RecentTile), findsNWidgets(3));
    await shoot(tester, 'o_recent_trashed_phone');
    await tap(tester, find.text('School').last);
    expect(find.byType(RecentRow), findsNothing);
    await shoot(tester, 'o_recent_in_folder_phone');

    s.settings.recentNotebooks = [byTitle['Ideas']!.id, byTitle['Travel plans']!.id];
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, s, const LibraryScreen());
    expect(find.byType(RecentRow), findsNothing);
    await shoot(tester, 'o_recent_all_at_top_phone');
    expect(tester.takeException(), isNull);
  });

  testWidgets('recent sideways: the strip and its menu', (tester) async {
    setWindow(tester, const Size(844, 390), dpr: 2);
    final s = seededServices();
    addTearDown(s.dispose);
    await pumpApp(tester, s, const LibraryScreen());
    await tap(tester, find.byType(RecentStripTile));
    await shoot(tester, 'o_recent_sideways_menu');
    final empty = AppServices.create(AppDatabase.inMemory());
    addTearDown(empty.dispose);
    await tester.pumpWidget(const SizedBox());
    await pumpApp(tester, empty, const LibraryScreen());
    await shoot(tester, 'o_recent_empty_sideways');
    expect(tester.takeException(), isNull);
  });

  // Move or copy pages from the editor's page menu (R8-2, R8-34): the
  // menu, a new notebook chosen, and a notebook's only page (Copy only).
  testWidgets('move or copy page from the editor (phone light)', (tester) async {
    setWindow(tester, phone.$2, dpr: phone.$3);
    final s = seededServices();
    addTearDown(s.dispose);
    final nb = s.notebooks.list().firstWhere((n) => n.title == 'Physics — Mechanics');
    await pumpApp(tester, s, EditorScreen(notebook: nb));
    await tap(tester, find.byTooltip('More options'));
    await tap(tester, find.text('Page'));
    await shoot(tester, 'o_page_menu_move_phone');
    await tap(tester, find.text('Move or copy page…'));
    await shoot(tester, 'o_move_copy_only_phone');
    await tap(tester, find.text('New notebook…'));
    await tester.enterText(find.byType(TextField).last, 'Forces');
    await tester.pump();
    await tap(tester, find.widgetWithText(FilledButton, 'OK'));
    await shoot(tester, 'o_move_new_notebook_phone');
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });
}
