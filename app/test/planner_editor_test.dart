import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/surface_copier.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/paper_pattern.dart';
import 'package:len/features/editor/document/paged_document_view.dart';
import 'package:len/features/editor/editor_screen.dart';
import 'package:len/ui/app_theme.dart';

final _oct = DateTime.utc(2026, 10, 1);
final _oct12 = Paper.planner(PaperStyle.dailyPlanner, DateTime.utc(2026, 10, 12));

/// Opens a notebook made of [papers] in the editor.
Future<(AppServices, Notebook)> _open(
  WidgetTester tester,
  List<Paper> papers, {
  bool stylusOnly = true,
}) async {
  tester.view
    ..physicalSize = const Size(900, 1300)
    ..devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  final services = AppServices.create(AppDatabase.inMemory());
  addTearDown(services.dispose);
  services.preferences.stylusOnly = stylusOnly;
  final nb = services.notebooks.create(
    title: 'Planner',
    kind: NotebookKind.paged,
    paper: PaperStyle.blank,
    coverColor: 0,
    papers: papers,
  );
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

/// The global position of the link to [target] on page [index].
Offset _linkOn(WidgetTester tester, int index, Paper target) {
  final view = find.byType(PagedDocumentView);
  final doc = tester.widget<PagedDocumentView>(view).controller;
  final page = doc.pages[index];
  final link = PaperPattern.of(
    page.paper,
    page.bounds,
    page: page.bounds,
  ).links.firstWhere((l) => l.target == target);
  final frame = doc.layout.frameOf(index)!;
  return tester.getTopLeft(view) + doc.viewport.toScreen(frame.topLeft + link.rect.center);
}

int _current(WidgetTester tester) =>
    tester.widget<PagedDocumentView>(find.byType(PagedDocumentView)).controller.currentPage;

Future<void> _closeEditor(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a finger tap on a calendar day opens its page (stylus mode)', (tester) async {
    final papers = PlannerPlan(start: _oct, linked: true).papersFor(PaperStyle.monthlyCalendar);
    final (s, nb) = await _open(tester, papers);
    final target = papers.indexOf(_oct12);
    expect(_current(tester), 0);

    await tester.tapAt(_linkOn(tester, 0, _oct12));
    await tester.pumpAndSettle();
    expect(_current(tester), target);
    expect(SurfaceCopier(s.strokes).loadAll(s.pages.pagesOf(nb.id).first.id), isEmpty);

    // From the day page back up to its week.
    final week = Paper.planner(PaperStyle.weeklyPlanner, DateTime.utc(2026, 10, 12));
    await tester.tapAt(_linkOn(tester, target, week));
    await tester.pumpAndSettle();
    expect(_current(tester), papers.indexOf(week));
    await _closeEditor(tester);
  });

  testWidgets('Ctrl-click follows a link; a plain finger tap draws instead', (tester) async {
    final papers = PlannerPlan(start: _oct, linked: true).papersFor(PaperStyle.monthlyCalendar);
    await _open(tester, papers, stylusOnly: false);
    final at = _linkOn(tester, 0, _oct12);
    await tester.tapAt(at);
    await tester.pumpAndSettle();
    expect(_current(tester), 0, reason: 'fingers write');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.tapAt(at, kind: PointerDeviceKind.mouse);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
    expect(_current(tester), papers.indexOf(_oct12));
    await _closeEditor(tester);
  });

  testWidgets('a link to a missing page offers to add it', (tester) async {
    final (s, nb) = await _open(tester, [Paper.planner(PaperStyle.monthlyCalendar, _oct)]);
    await tester.tapAt(_linkOn(tester, 0, _oct12));
    await tester.pumpAndSettle();
    expect(find.text('This notebook has no page for Mon 12 Oct 2026'), findsOneWidget);
    await tester.tap(find.text('Add page'));
    await tester.pumpAndSettle();
    final pages = s.pages.pagesOf(nb.id);
    expect(pages.map((p) => p.paper), [Paper.planner(PaperStyle.monthlyCalendar, _oct), _oct12]);
    expect(_current(tester), 1);
    await _closeEditor(tester);
  });

  testWidgets('adding a page after a planner page continues the dates', (tester) async {
    final (s, nb) = await _open(tester, [
      Paper.planner(PaperStyle.dailyPlanner, DateTime.utc(2024, 2, 28)),
    ]);
    await tester.tap(find.byTooltip('Add page after this one'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Add page after this one'));
    await tester.pumpAndSettle();
    expect(s.pages.pagesOf(nb.id).map((p) => p.paper.date), [
      DateTime.utc(2024, 2, 28),
      DateTime.utc(2024, 2, 29),
      DateTime.utc(2024, 3, 1),
    ]);
    await _closeEditor(tester);
  });
}
