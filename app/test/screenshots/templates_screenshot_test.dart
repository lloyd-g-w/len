import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/documents/template_picker.dart';
import 'package:len/features/editor/document/paged_document_view.dart';
import 'package:len/features/editor/tabs/editor_workspace.dart';
import 'package:len/features/library/library_screen.dart';
import 'package:len/ink/render/paper_painter.dart';

import 'screenshot_harness.dart';

final _today = DateTime.utc(2026, 10, 11);

/// Templates with real fonts: every template page at overview, page and
/// close-up zoom, and the template picker on a phone and a tablet.
void main() {
  setUpAll(loadRealFonts);

  final pages = <(String, Paper, PageFormat, PageOrientation)>[
    for (final style in PaperStyle.builtIn)
      (
        style.name,
        Paper.defaultFor(style, today: _today)!,
        PageFormat.a4,
        PageOrientation.portrait,
      ),
    (
      'monthly_feb2024',
      Paper.planner(PaperStyle.monthlyCalendar, DateTime.utc(2024, 2, 1)),
      PageFormat.a4,
      PageOrientation.portrait,
    ),
    (
      'monthly_mar2026',
      Paper.planner(PaperStyle.monthlyCalendar, DateTime.utc(2026, 3, 1)),
      PageFormat.a4,
      PageOrientation.portrait,
    ),
    (
      'weekly_landscape',
      Paper.planner(PaperStyle.weeklyPlanner, DateTime.utc(2025, 12, 29)),
      PageFormat.a4,
      PageOrientation.landscape,
    ),
    (
      'daily_a5',
      Paper.planner(PaperStyle.dailyPlanner, DateTime.utc(2024, 2, 29)),
      PageFormat.a5,
      PageOrientation.portrait,
    ),
    (
      'yearly_landscape',
      Paper.planner(PaperStyle.yearlyOverview, DateTime.utc(2024)),
      PageFormat.a4,
      PageOrientation.landscape,
    ),
    (
      'yearly_sunday_el',
      Paper.planner(
        PaperStyle.yearlyOverview,
        DateTime.utc(2026),
        calendar: const PlannerCalendar(weekStart: WeekStart.sunday, language: PlannerLanguage.el),
      ),
      PageFormat.letter,
      PageOrientation.portrait,
    ),
    (
      'monthly_de',
      Paper.planner(
        PaperStyle.monthlyCalendar,
        DateTime.utc(2026, 10),
        calendar: const PlannerCalendar(language: PlannerLanguage.de),
      ),
      PageFormat.a4,
      PageOrientation.portrait,
    ),
    (
      'monthly_sunday_us',
      Paper.planner(
        PaperStyle.monthlyCalendar,
        DateTime.utc(2026, 3),
        calendar: const PlannerCalendar(
          weekStart: WeekStart.sunday,
          language: PlannerLanguage.enUS,
        ),
      ),
      PageFormat.letter,
      PageOrientation.portrait,
    ),
    (
      'weekly_sunday_ru',
      Paper.planner(
        PaperStyle.weeklyPlanner,
        DateTime.utc(2026, 9, 27),
        calendar: const PlannerCalendar(weekStart: WeekStart.sunday, language: PlannerLanguage.ru),
      ),
      PageFormat.a4,
      PageOrientation.portrait,
    ),
    (
      'daily_tr',
      Paper.planner(
        PaperStyle.dailyPlanner,
        DateTime.utc(2026, 10, 10),
        calendar: const PlannerCalendar(language: PlannerLanguage.tr),
      ),
      PageFormat.a5,
      PageOrientation.portrait,
    ),
    (
      'storyboard_landscape',
      const Paper(PaperStyle.storyboard),
      PageFormat.letter,
      PageOrientation.landscape,
    ),
    (
      'meeting_square',
      const Paper(PaperStyle.meeting),
      PageFormat.square,
      PageOrientation.portrait,
    ),
  ];

  for (final (name, paper, format, orientation) in pages) {
    testWidgets('template $name at three zooms', (tester) async {
      final size = format.sizeFor(orientation);
      // Overview (25 %), the whole page at 100 %, and the top-left corner
      // at 300 %: crisp at any zoom.
      setWindow(tester, Size(size.width * 0.25 + 16 + size.width + 16 + 600, size.height + 16));
      await tester.pumpWidget(
        RepaintBoundary(
          key: shotKey,
          child: ColoredBox(
            color: const Color(0xFFE9EAEE),
            child: CustomPaint(painter: _Zooms(paper, size, PaperColor.white), size: Size.infinite),
          ),
        ),
      );
      await shoot(tester, 'paper_$name');
    });
  }

  for (final (name, size) in const [
    ('tablet', Size(1280, 800)),
    ('tablet_portrait', Size(800, 1280)),
  ]) {
    testWidgets('editor with a linked planner $name', (tester) async {
      setWindow(tester, size);
      final services = seededServices();
      addTearDown(services.dispose);
      final nb = services.notebooks.create(
        title: 'Planner 2026',
        kind: NotebookKind.paged,
        paper: PaperStyle.blank,
        coverColor: 0xFF0B7285,
        papers: PlannerPlan(start: _today, linked: true).papersFor(PaperStyle.monthlyCalendar),
        firstPage: const PageTemplate(color: PaperColor.cream),
      );
      services.openNotebooks.open(nb);
      await pumpApp(tester, services, const EditorWorkspace());
      await shoot(tester, 'templates_editor_month_$name');
      final doc = tester.widget<PagedDocumentView>(find.byType(PagedDocumentView)).controller;
      doc.goToPage(doc.indexOfPaper(Paper.planner(PaperStyle.dailyPlanner, _today)));
      await settle(tester);
      expect(tester.takeException(), isNull);
      await shoot(tester, 'templates_editor_day_$name');
    });
  }

  for (final (name, size, dpr, theme) in const [
    ('phone', Size(390, 844), 2.0, ThemeMode.light),
    ('phone_dark', Size(390, 844), 2.0, ThemeMode.dark),
    ('tablet', Size(800, 1280), 1.0, ThemeMode.light),
    ('tablet_landscape', Size(1280, 800), 1.0, ThemeMode.light),
    ('desktop_dark', Size(1440, 900), 1.0, ThemeMode.dark),
  ]) {
    testWidgets('template picker with planners $name', (tester) async {
      setWindow(tester, size, dpr: dpr);
      final services = seededServices();
      addTearDown(services.dispose);
      await pumpApp(tester, services, const LibraryScreen(), mode: theme);
      unawaited(
        showTemplatePicker(
          tester.element(find.byType(LibraryScreen)),
          initial: const PageTemplate(paper: Paper(PaperStyle.collegeRuled)),
          mode: TemplatePickerMode.addPage,
          today: _today,
        ),
      );
      await settle(tester);
      await shoot(tester, 'templates_picker_${name}_all');
      await tester.ensureVisible(find.byKey(const ValueKey('category-planners')));
      await tester.tap(find.byKey(const ValueKey('category-planners')));
      await settle(tester);
      await tester.tap(find.text('Monthly calendar'));
      await settle(tester);
      await tester.ensureVisible(find.byKey(const ValueKey('planner-linked')));
      await tester.tap(find.byKey(const ValueKey('planner-linked')));
      await settle(tester);
      expect(tester.takeException(), isNull);
      await shoot(tester, 'templates_picker_${name}_planner');
      await tester.enterText(find.byKey(const ValueKey('template-search')), 'grid');
      await settle(tester);
      await shoot(tester, 'templates_picker_${name}_search');
      // Dialogs on wide screens, sheets (with a drag handle) on phones.
      expect(find.byType(Dialog), size.width >= 720 ? findsOneWidget : findsNothing);
    });
  }

  for (final (name, size, dpr, theme) in const [
    ('phone', Size(390, 844), 2.0, ThemeMode.light),
    ('tablet_landscape_dark', Size(1280, 800), 1.0, ThemeMode.dark),
  ]) {
    testWidgets('change template and canvas background $name', (tester) async {
      setWindow(tester, size, dpr: dpr);
      final services = seededServices();
      addTearDown(services.dispose);
      await pumpApp(tester, services, const LibraryScreen(), mode: theme);
      final context = tester.element(find.byType(LibraryScreen));
      for (final mode in [TemplatePickerMode.change, TemplatePickerMode.canvas]) {
        unawaited(
          showTemplatePicker(
            context,
            initial: const PageTemplate(paper: Paper(PaperStyle.dotted), color: PaperColor.cream),
            mode: mode,
            today: _today,
          ),
        );
        await settle(tester);
        expect(tester.takeException(), isNull);
        await shoot(tester, 'templates_${mode.name}_$name');
        await tester.tap(find.text('Cancel'));
        await settle(tester);
      }
    });
  }
}

class _Zooms extends CustomPainter {
  _Zooms(this.paper, this.page, this.color);

  final Paper paper;
  final Size page;
  final PaperColor color;

  void _sheet(Canvas canvas, Offset at, double scale, Rect clip) {
    final rect = Offset.zero & page;
    canvas
      ..save()
      ..clipRect(clip)
      ..translate(at.dx, at.dy)
      ..scale(scale);
    PaperRenderer.paintSheet(canvas, rect, color, scale: scale);
    final visible = clip.shift(-at).topLeft / scale & clip.size / scale;
    PaperRenderer.paintPattern(
      canvas,
      paper,
      color,
      visible.intersect(rect),
      page: rect,
      scale: scale,
    );
    canvas.restore();
  }

  @override
  void paint(Canvas canvas, Size size) {
    const pad = 8.0;
    final small = Offset(pad, pad);
    _sheet(canvas, small, 0.25, small & page * 0.25);
    final full = Offset(pad * 2 + page.width * 0.25, pad);
    _sheet(canvas, full, 1, full & page);
    final close = Offset(full.dx + page.width + pad, pad);
    _sheet(canvas, close - const Offset(40, 40) * 3, 3, close & Size(600 - pad * 2, page.height));
  }

  @override
  bool shouldRepaint(_Zooms old) => false;
}
