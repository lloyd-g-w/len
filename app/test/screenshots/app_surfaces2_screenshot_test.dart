import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/features/library/library_screen.dart';
import 'package:len/features/library/library_sidebar.dart';
import 'package:len/features/library/notebook_card.dart';
import 'package:len/ink/recognition/handwriting_indexer.dart';
import 'package:len/ui/app_theme.dart';

import '../support/fake_recognizer.dart';
import 'screenshot_harness.dart';

/// Library surfaces: full-text search results (text boxes and
/// handwriting), the sort, folder, sidebar and trash menus, list layout,
/// favourites, an emptied trash, selection mode and the Undo snackbar.
void main() {
  setUpAll(loadRealFonts);

  const phone = ('phone', Size(390, 844), 2.0);
  const desktop = ('desktop', Size(1440, 900), 1.0);
  const modes = [ThemeMode.light, ThemeMode.dark];

  AppServices library() {
    final s = seededServices();
    addTearDown(s.dispose);
    return s;
  }

  Notebook byTitle(AppServices s, String title) =>
      s.notebooks.list().firstWhere((n) => n.title == title);

  /// The "More" button of [title]'s card.
  Finder moreOf(String title) => find.descendant(
    of: find.ancestor(of: find.text(title), matching: find.byType(NotebookCard)),
    matching: find.byTooltip('More'),
  );

  Future<void> tap(WidgetTester tester, Finder finder) async {
    await tester.tap(finder, warnIfMissed: false);
    await settle(tester);
  }

  /// Scrolls the library content until [finder] is on screen.
  Future<void> reveal(WidgetTester tester, Finder finder) async {
    await tester.scrollUntilVisible(
      finder,
      200,
      scrollable: find
          .byWidgetPredicate((w) => w is Scrollable && w.axisDirection == AxisDirection.down)
          .first,
    );
    await settle(tester);
  }

  /// Closes a menu or dialog by tapping its barrier.
  Future<void> dismiss(WidgetTester tester) async {
    await tester.tapAt(const Offset(2, 2));
    await settle(tester);
  }

  /// Text boxes and recognised handwriting mentioning "plan", besides the
  /// "Travel plans" title.
  Future<void> seedSearch(AppServices s) async {
    final physics = s.pages.pagesOf(byTitle(s, 'Physics — Mechanics').id).first;
    final meeting = s.pages.pagesOf(byTitle(s, 'Meeting notes').id).first;
    final whiteboard = byTitle(s, 'Whiteboard');
    SurfaceElement text(String id, String surface, String body, double y) => SurfaceElement(
      id: id,
      surfaceId: surface,
      type: 'text',
      rect: Rect.fromLTWH(90, y, 420, 40),
      z: 1,
      createdAt: 1,
      data: {'text': body, 'size': 24},
    );
    s.elements.save([
      text('t1', physics.id, 'Lab plan: measure g with a pendulum', 820),
      text('t2', meeting.id, 'Q4 roadmap — plan the launch with design', 760),
      text('t3', whiteboard.id, 'Floor plan sketch', 400),
    ]);
    final lecture = s.notebooks.create(
      title: 'Lecture notes',
      kind: NotebookKind.paged,
      paper: PaperStyle.collegeRuled,
      coverColor: Palette.covers[3],
    );
    final page = s.pages.pagesOf(lecture.id).first.id;
    const words = {'w1': 'revision', 'w2': 'plan', 'w3': 'for', 'w4': 'exams', 'w5': 'monday'};
    s.strokes.save([
      scribble('w1', page, const Rect.fromLTRB(110, 140, 250, 170), createdAt: 1),
      scribble('w2', page, const Rect.fromLTRB(270, 140, 340, 170), createdAt: 2),
      scribble('w3', page, const Rect.fromLTRB(360, 140, 410, 170), createdAt: 3),
      scribble('w4', page, const Rect.fromLTRB(430, 140, 540, 170), createdAt: 4),
      scribble('w5', page, const Rect.fromLTRB(110, 210, 240, 240), createdAt: 5),
    ]);
    final indexer = HandwritingIndexer(
      s.database,
      recognizer: FakeRecognizer(words: {...words}),
      language: () => 'en-US',
      idleDelay: Duration.zero,
      pauseBetweenLines: Duration.zero,
    );
    addTearDown(indexer.dispose);
    await indexer.indexSurface(page);
  }

  for (final (name, size, dpr) in [phone, desktop]) {
    for (final mode in modes) {
      final m = mode.name;

      testWidgets('search results $name $m', (tester) async {
        setWindow(tester, size, dpr: dpr);
        final services = library();
        await seedSearch(services);
        await pumpApp(tester, services, const LibraryScreen(), mode: mode);
        await tester.enterText(find.byType(TextField).first, 'plan');
        await settle(tester);
        expect(find.text('Lecture notes'), findsWidgets);
        expect(tester.takeException(), isNull);
        await shoot(tester, 's_library_search_${name}_$m');
        if (name == 'phone') {
          await tester.drag(find.byType(CustomScrollView).first, const Offset(0, -500));
          await settle(tester);
          await shoot(tester, 's_library_search_scrolled_${name}_$m');
        }
      });

      testWidgets('library menus and views $name $m', (tester) async {
        setWindow(tester, size, dpr: dpr);
        final services = library();
        await pumpApp(tester, services, const LibraryScreen(), mode: mode);
        final wide = name != 'phone';

        await tap(tester, find.byTooltip('Sort: Last edited'));
        expect(find.text('Date created'), findsOneWidget);
        await shoot(tester, 's_library_sort_menu_${name}_$m');
        await tap(tester, find.text('Name'));
        await shoot(tester, 's_library_sorted_by_name_${name}_$m');

        if (wide) {
          await tap(tester, find.byTooltip('Folder options').first);
        } else {
          await tester.longPress(find.text('Work').last);
          await settle(tester);
        }
        expect(find.text('Edit folder…'), findsOneWidget);
        await shoot(tester, 's_library_folder_menu_${name}_$m');
        await dismiss(tester);

        if (wide) {
          await tester.longPress(
            find.descendant(of: find.byType(LibrarySidebar), matching: find.text('Work')),
          );
          await settle(tester);
          expect(find.text('Delete folder…'), findsOneWidget);
          await shoot(tester, 's_library_sidebar_folder_menu_${name}_$m');
          await dismiss(tester);
        }

        await tap(tester, find.byTooltip('Show as list'));
        await shoot(tester, 's_library_list_${name}_$m');
        await tap(tester, find.byTooltip('Show as grid'));

        await tap(tester, find.text('Favourites').first);
        expect(find.text('Journal 2026'), findsOneWidget);
        await shoot(tester, 's_library_favourites_${name}_$m');
        await tap(tester, moreOf('Journal 2026'));
        await tap(tester, find.text('Remove from favourites'));
        await shoot(tester, 's_library_favourites_empty_${name}_$m');

        await tap(tester, find.text('Trash').first);
        await tap(tester, moreOf('Old drafts'));
        expect(find.text('Delete forever…'), findsOneWidget);
        await shoot(tester, 's_library_trash_menu_${name}_$m');
        await tap(tester, find.text('Delete forever…'));
        await shoot(tester, 's_dialog_delete_forever_${name}_$m');
        await tap(tester, find.text('Cancel'));
        await tap(tester, emptyTrashButton());
        await tap(tester, find.text('Empty trash').last);
        expect(find.text('Old drafts'), findsNothing);
        await shoot(tester, 's_library_trash_empty_${name}_$m');

        await tap(tester, find.text('Library').first);
        await tap(tester, find.byTooltip('Select notebooks'));
        for (final title in ['Ideas', 'Recipes', 'Travel plans']) {
          await reveal(tester, find.text(title));
          await tap(tester, find.text(title));
        }
        expect(find.text('3 selected'), findsOneWidget);
        await shoot(tester, 's_library_selection_${name}_$m');
        await tap(tester, find.byTooltip('Done'));
        expect(tester.takeException(), isNull);
      });

      testWidgets('trash undo snackbar $name $m', (tester) async {
        setWindow(tester, size, dpr: dpr);
        await pumpApp(tester, library(), const LibraryScreen(), mode: mode);
        await reveal(tester, moreOf('Recipes'));
        await tap(tester, moreOf('Recipes'));
        await tap(tester, find.text('Move to trash'));
        expect(find.text('Undo'), findsOneWidget);
        expect(tester.takeException(), isNull);
        await shoot(tester, 's_snackbar_trash_undo_${name}_$m');
        await tap(tester, find.text('Undo'));
        expect(find.text('Recipes'), findsOneWidget);
      });
    }
  }

  testWidgets('selection in the trash phone dark', (tester) async {
    setWindow(tester, phone.$2, dpr: phone.$3);
    final services = library();
    services.notebooks.trash(byTitle(services, 'Recipes').id);
    await pumpApp(tester, services, const LibraryScreen(), mode: ThemeMode.dark);
    await tap(tester, find.text('Trash').first);
    await tap(tester, find.byTooltip('Select notebooks'));
    await tap(tester, find.text('Recipes'));
    expect(find.text('1 selected'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await shoot(tester, 's_library_trash_selection_phone_dark');
  });

  for (final (name, size, dpr) in [phone, desktop]) {
    testWidgets('library first frame $name', (tester) async {
      setWindow(tester, size, dpr: dpr);
      final services = library();
      await tester.pumpWidget(
        AppScope(
          services: services,
          child: RepaintBoundary(
            key: shotKey,
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: AppTheme.light(),
              home: const LibraryScreen(),
            ),
          ),
        ),
      );
      // Thumbnails are rendered in batches after the first frame.
      expect(tester.takeException(), isNull);
      await shoot(tester, 's_library_loading_$name');
      await settle(tester);
    });
  }
}
