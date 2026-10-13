import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/surface_copier.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/notebook_page.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/preferences.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/editor/document/page_overview.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/ink/render/ink_painters.dart';
import 'package:len/ui/app_theme.dart';

import 'support/page_actions.dart';

/// A notebook with three differently shaped pages, some with ink.
Future<(AppServices, Notebook)> pumpEditor(
  WidgetTester tester, {
  Size size = const Size(800, 1300),
  ToolbarPlacement? placement,
}) async {
  tester.view
    ..physicalSize = size
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final services = AppServices.create(AppDatabase.inMemory());
  addTearDown(services.dispose);
  if (placement != null) services.preferences.toolbarPlacement = placement;
  final nb = services.notebooks.create(
    title: 'Physics',
    kind: NotebookKind.paged,
    paper: PaperStyle.collegeRuled,
    coverColor: 0,
    firstPage: const PageTemplate(paper: Paper(PaperStyle.collegeRuled)),
  );
  final first = services.pages.pagesOf(nb.id).single;
  final second = services.pages.addPage(
    nb.id,
    template: const PageTemplate(
      paper: Paper(PaperStyle.gridLarge),
      color: PaperColor.cream,
      format: PageFormat.letter,
      orientation: PageOrientation.landscape,
    ),
  );
  services.pages.addPage(
    nb.id,
    template: const PageTemplate(paper: Paper(PaperStyle.dotted), color: PaperColor.dark),
  );
  services.strokes.save([
    _wave('w1', first.id, const Offset(120, 200), 0xFF1F2937),
    _wave('w2', second.id, const Offset(200, 150), 0xFF1C7ED6),
  ]);
  await tester.pumpWidget(
    AppScope(
      services: services,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: EditorScreen(notebook: nb),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return (services, nb);
}

Stroke _wave(String id, String surface, Offset at, int color) => Stroke(
  id: id,
  surfaceId: surface,
  tool: InkTool.ballpoint,
  color: color,
  width: 4,
  points: [
    for (var i = 0; i < 40; i++)
      StrokePoint(at.dx + i * 12.0, at.dy + 30 * (i.isEven ? 1 : -1) * (i / 40), 0.5),
  ],
  createdAt: 1,
);

Future<void> drawAt(WidgetTester tester, Offset start) async {
  final gesture = await tester.startGesture(start, kind: PointerDeviceKind.mouse);
  for (var i = 1; i <= 10; i++) {
    await gesture.moveTo(start + Offset(i * 6.0, i * 2.0));
  }
  await gesture.up();
  await tester.pump();
}

/// Unmounts the editor while the database is still open.
Future<void> closeEditor(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump();
}

List<Stroke> inkOf(AppServices s, NotebookPage page) => SurfaceCopier(s.strokes).loadAll(page.id);

void main() {
  testWidgets('paged documents paint the live highlighter under the committed ink', (tester) async {
    await pumpEditor(tester);
    final live = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((p) => p.painter)
        .whereType<LiveInkPainter>()
        .toList();
    expect(live.map((p) => p.belowInk), unorderedEquals([true, false]));
  });

  testWidgets('pages scroll continuously and ink lands on the page under the pen', (tester) async {
    final (s, nb) = await pumpEditor(tester);
    await expectLater(
      find.byType(EditorScreen),
      matchesGoldenFile('goldens/editor_continuous.png'),
    );
    final pages = s.pages.pagesOf(nb.id);
    expect(find.text('1 / 3'), findsOneWidget);

    // The fitted A4 page is ~800 px tall: draw on page 1, then lower on
    // the screen, on page 2 (which is visible below it).
    await drawAt(tester, const Offset(300, 400));
    await drawAt(tester, const Offset(300, 1150));
    final onFirst = inkOf(s, pages[0]).where((st) => st.id != 'w1').single;
    final onSecond = inkOf(s, pages[1]).where((st) => st.id != 'w2').single;
    // Stored in page-local coordinates.
    expect(pages[0].bounds.contains(onFirst.points.first.offset), isTrue);
    expect(pages[1].bounds.contains(onSecond.points.first.offset), isTrue);
    expect(onSecond.points.first.y, lessThan(500));

    // Undo spans pages: most recent first.
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ); // ignored without ctrl
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyZ);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pump();
    expect(inkOf(s, pages[1]), hasLength(1));
    expect(inkOf(s, pages[0]), hasLength(2));
    await tester.tap(find.byTooltip('Undo (Ctrl+Z)'));
    await tester.pump();
    expect(inkOf(s, pages[0]), hasLength(1));
    await tester.tap(find.byTooltip('Redo (Ctrl+Shift+Z)'));
    await tester.pump();
    expect(inkOf(s, pages[0]), hasLength(2));

    // Scrolling down updates the page indicator.
    await tester.sendEventToBinding(
      PointerScrollEvent(position: const Offset(400, 600), scrollDelta: const Offset(0, 1500)),
    );
    await tester.pump();
    expect(find.text('1 / 3'), findsNothing);
    expect(tester.takeException(), isNull);
    await closeEditor(tester);
  });

  testWidgets('single-page flow turns pages', (tester) async {
    final (s, nb) = await pumpEditor(tester, size: const Size(1280, 900));
    await tester.tap(find.byTooltip('More options'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('View'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('One page at a time'));
    await tester.pumpAndSettle();
    expect(s.settings.pageFlow, 'single');
    await nextPage(tester);
    expect(find.text('2 / 3'), findsOneWidget);
    await expectLater(find.byType(EditorScreen), matchesGoldenFile('goldens/editor_single.png'));
    await drawAt(tester, const Offset(640, 450));
    expect(inkOf(s, s.pages.pagesOf(nb.id)[1]), hasLength(2));
    await closeEditor(tester);
  });

  testWidgets('page commands: add, bookmark, template, duplicate, delete + undo', (tester) async {
    final (s, nb) = await pumpEditor(tester, size: const Size(1280, 900));
    List<NotebookPage> pages() => s.pages.pagesOf(nb.id);

    await addPageAfter(tester);
    expect(find.text('2 / 4'), findsOneWidget);
    expect(pages()[1].paper.style, PaperStyle.collegeRuled); // Like the page it follows.

    Future<void> menu(String item) async {
      await tester.tap(find.byTooltip('More options'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Page'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(item).last);
      await tester.pumpAndSettle();
    }

    await menu('Bookmark page');
    expect(pages()[1].bookmarked, isTrue);
    await menu('Duplicate page');
    expect(pages(), hasLength(5));
    expect(pages()[2].bookmarked, isFalse);
    expect(find.text('3 / 5'), findsOneWidget);

    await menu('Change template…');
    await tester.ensureVisible(find.text('Music staff'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Music staff'));
    await tester.tap(find.text('All pages'));
    await tester.pump();
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(pages().every((p) => p.paper.style == PaperStyle.music), isTrue);
    // Undo puts every page's own template back.
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(pages().map((p) => p.paper.style), [
      PaperStyle.collegeRuled,
      PaperStyle.collegeRuled,
      PaperStyle.collegeRuled,
      PaperStyle.gridLarge,
      PaperStyle.dotted,
    ]);
    expect(pages().map((p) => p.paperColor).skip(3), [PaperColor.cream, PaperColor.dark]);

    final doomed = pages()[2].id;
    await menu('Delete page');
    expect(pages(), hasLength(4));
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(pages().map((p) => p.id), contains(doomed));
    await closeEditor(tester);
  });

  testWidgets('overview: thumbnails, go to, reorder, bookmarks filter', (tester) async {
    final (s, nb) = await pumpEditor(tester, size: const Size(1000, 800));
    final original = s.pages.pagesOf(nb.id);
    s.pages.setBookmarked(original[2].id, true);
    await tester.tap(find.byTooltip('All pages'));
    await tester.pumpAndSettle();
    expect(find.byType(PageOverview), findsOneWidget);
    await expectLater(find.byType(PageOverview), matchesGoldenFile('goldens/page_overview.png'));

    // Drag page 3 onto page 1.
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
    expect(s.pages.pagesOf(nb.id).map((p) => p.id), [
      original[2].id,
      original[0].id,
      original[1].id,
    ]);

    await tester.tap(find.text('Bookmarked'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('page-tile-0')), findsOneWidget);
    expect(find.byKey(const ValueKey('page-tile-1')), findsNothing);

    await tester.tap(find.byKey(const ValueKey('page-tile-0')));
    await tester.pumpAndSettle();
    expect(find.byType(PageOverview), findsNothing);
    expect(find.text('1 / 3'), findsOneWidget);
    await closeEditor(tester);
  });

  testWidgets('overview: deleting several pages is one undo', (tester) async {
    final (s, nb) = await pumpEditor(tester, size: const Size(1000, 800));
    final original = s.pages.pagesOf(nb.id);
    await tester.tap(find.byTooltip('All pages'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('page-tile-0')));
    await tester.tap(find.byKey(const ValueKey('page-tile-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(s.pages.pagesOf(nb.id).map((p) => p.id), [original[2].id]);
    expect(find.text('2 pages deleted'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(s.pages.pagesOf(nb.id).map((p) => p.id), [for (final p in original) p.id]);
    expect(inkOf(s, original[0]), hasLength(1)); // Content came back too.
    expect(inkOf(s, original[1]), hasLength(1));
    await closeEditor(tester);
  });

  testWidgets('overview: duplicating several pages offers Undo', (tester) async {
    final (s, nb) = await pumpEditor(tester, size: const Size(1000, 800));
    final original = [for (final p in s.pages.pagesOf(nb.id)) p.id];
    await tester.tap(find.byTooltip('All pages'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Select'));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('page-tile-0')));
    await tester.tap(find.byKey(const ValueKey('page-tile-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Duplicate'));
    await tester.pumpAndSettle();
    expect(s.pages.pagesOf(nb.id), hasLength(5));
    expect(find.text('2 pages duplicated'), findsOneWidget);

    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(s.pages.pagesOf(nb.id).map((p) => p.id), original);
    await closeEditor(tester);
  });
}
