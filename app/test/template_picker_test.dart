import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/documents/template_picker.dart';
import 'package:len/features/documents/templates/template_catalog.dart';
import 'package:len/ui/app_theme.dart';

final _today = DateTime.utc(2026, 10, 11);

Widget _host(Widget child, {AppServices? services}) {
  final app = MaterialApp(
    theme: AppTheme.light(),
    home: Scaffold(body: Material(child: child)),
  );
  return services == null ? app : AppScope(services: services, child: app);
}

/// Opens the picker from a button; returns a getter for its result.
Future<TemplateChoice? Function()> _open(
  WidgetTester tester, {
  required TemplatePickerMode mode,
  PageTemplate initial = const PageTemplate(),
  AppServices? services,
}) async {
  TemplateChoice? choice;
  await tester.pumpWidget(
    _host(
      services: services,
      Builder(
        builder: (context) => TextButton(
          onPressed: () async => choice = await showTemplatePicker(
            context,
            initial: initial,
            mode: mode,
            today: _today,
          ),
          child: const Text('open'),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return () => choice;
}

Future<void> _tapKey(WidgetTester tester, String key) async {
  await tester.ensureVisible(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
  await tester.tap(find.byKey(ValueKey(key)));
  await tester.pumpAndSettle();
}

Future<void> _tapText(WidgetTester tester, String text) async {
  await tester.ensureVisible(find.text(text).last);
  await tester.pumpAndSettle();
  await tester.tap(find.text(text).last);
  await tester.pumpAndSettle();
}

void main() {
  group('catalog', () {
    test('sections follow the categories; search and filters narrow them', () {
      final all = templateSections();
      expect(all.map((s) => s.$1), TemplateCategory.values);
      expect(
        all.expand((s) => s.$2).whereType<BuiltInTemplate>(),
        hasLength(PaperStyle.builtIn.length),
      );

      final planners = templateSections(query: 'calendar');
      expect(planners.single.$2.map((e) => e.name), contains('Monthly calendar'));
      expect(templateSections(query: 'zzz'), isEmpty);
      expect(
        templateSections(only: TemplateCategory.paper).single.$2.map((e) => e.name),
        containsAll(['Graph paper', 'Engineering', 'Storyboard', 'Music staff']),
      );
      final canvas = templateSections(canvas: true).expand((s) => s.$2).toList();
      expect(canvas.map((e) => e.category), isNot(contains(TemplateCategory.planners)));
      expect(canvas.map((e) => e.category), isNot(contains(TemplateCategory.mine)));
      expect(canvas.map((e) => e.name), isNot(contains('Cornell notes')));
    });

    test('selecting a planner dates it; generating follows the plan', () {
      final s = TemplateSelection(
        const PageTemplate(),
        PlannerPlan(start: DateTime.utc(2024, 2, 1)),
      ).select(const BuiltInTemplate(PaperStyle.dailyPlanner));
      expect(s.template.paper, Paper.planner(PaperStyle.dailyPlanner, DateTime.utc(2024, 2, 1)));
      expect(s.pagesToCreate(), hasLength(29));
      final weekly = s.select(const BuiltInTemplate(PaperStyle.weeklyPlanner));
      expect(weekly.template.paper.date, DateTime.utc(2024, 1, 29));
      expect(weekly.select(const BuiltInTemplate(PaperStyle.dotted)).pagesToCreate(), [
        const Paper(PaperStyle.dotted),
      ]);
    });
  });

  testWidgets('template picker renders every template (tablet, golden)', (tester) async {
    tester.view.physicalSize = const Size(760, 1400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _host(
        TemplatePicker(
          initial: const PageTemplate(paper: Paper(PaperStyle.cornell), color: PaperColor.cream),
          mode: TemplatePickerMode.create,
          today: _today,
        ),
      ),
    );
    for (final style in PaperStyle.builtIn) {
      expect(find.text(style.label), findsOneWidget);
    }
    await expectLater(
      find.byType(TemplatePicker),
      matchesGoldenFile('goldens/template_picker.png'),
    );
  });

  testWidgets('template picker on a phone with a planner chosen (golden)', (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _host(
        TemplatePicker(
          initial: PageTemplate(paper: Paper.planner(PaperStyle.monthlyCalendar, _today)),
          mode: TemplatePickerMode.addPage,
          today: _today,
        ),
      ),
    );
    await _tapKey(tester, 'category-planners');
    expect(find.text('Daily planner'), findsOneWidget);
    expect(find.text('Dotted'), findsNothing);
    expect(find.text('Add page'), findsNWidgets(2)); // Title and button: one month.
    await expectLater(
      find.byType(TemplatePicker),
      matchesGoldenFile('goldens/template_picker_phone.png'),
    );
  });

  testWidgets('search filters templates and says when nothing matches', (tester) async {
    await _open(tester, mode: TemplatePickerMode.create);
    await tester.enterText(find.byKey(const ValueKey('template-search')), 'engin');
    await tester.pumpAndSettle();
    expect(find.text('Engineering'), findsOneWidget);
    expect(find.text('Dotted'), findsNothing);
    await tester.enterText(find.byKey(const ValueKey('template-search')), 'hexagons');
    await tester.pumpAndSettle();
    expect(find.textContaining('No templates match'), findsOneWidget);
    await tester.tap(find.byTooltip('Clear search'));
    await tester.pumpAndSettle();
    expect(find.text('Dotted'), findsOneWidget);
  });

  testWidgets('choosing a template returns it', (tester) async {
    final choice = await _open(tester, mode: TemplatePickerMode.change);
    expect(find.text('Page size'), findsNothing); // Size is fixed when changing.
    await _tapText(tester, 'Dotted');
    await _tapText(tester, 'Dark');
    await tester.tap(find.text('Apply to all pages'));
    await tester.pumpAndSettle();
    expect(choice()!.template.style, PaperStyle.dotted);
    expect(choice()!.template.color, PaperColor.dark);
    expect(choice()!.allPages, isTrue);
  });

  testWidgets('a planner added from the picker generates its pages', (tester) async {
    final choice = await _open(tester, mode: TemplatePickerMode.addPage);
    await _tapText(tester, 'Daily planner');
    expect(find.text('October 2026'), findsOneWidget);
    expect(find.text('Add 31 pages'), findsOneWidget);
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    expect(find.text('August 2026'), findsOneWidget);
    await tester.tap(find.byTooltip('More months'));
    await tester.pumpAndSettle();
    expect(find.text('Add 61 pages'), findsOneWidget); // August + September.
    await tester.tap(find.text('Add 61 pages'));
    await tester.pumpAndSettle();
    final papers = choice()!.papers;
    expect(papers.first, Paper.planner(PaperStyle.dailyPlanner, DateTime.utc(2026, 8, 1)));
    expect(papers.last, Paper.planner(PaperStyle.dailyPlanner, DateTime.utc(2026, 9, 30)));
  });

  testWidgets('a linked monthly planner; changing a page steps one period', (tester) async {
    var choice = await _open(tester, mode: TemplatePickerMode.create);
    await _tapText(tester, 'Monthly calendar');
    await _tapKey(tester, 'planner-linked');
    await tester.tap(find.text('Use template'));
    await tester.pumpAndSettle();
    final linked = choice()!.papers;
    expect(linked.first, Paper.planner(PaperStyle.monthlyCalendar, _today));
    expect(linked.where((p) => p.style == PaperStyle.weeklyPlanner), hasLength(5));

    choice = await _open(
      tester,
      mode: TemplatePickerMode.change,
      initial: PageTemplate(paper: Paper.planner(PaperStyle.weeklyPlanner, _today)),
    );
    expect(find.text('Week 41 · 5 – 11 October 2026'), findsOneWidget);
    await tester.ensureVisible(find.byTooltip('Next'));
    await tester.tap(find.byTooltip('Next'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Apply to all pages'));
    await tester.pumpAndSettle();
    final pages = choice()!.papersForPages(3).map((p) => p.date).toList();
    expect(pages, [
      DateTime.utc(2026, 10, 12),
      DateTime.utc(2026, 10, 19),
      DateTime.utc(2026, 10, 26),
    ]);
  });

  testWidgets('My templates: listed, chosen with their size, renamed and deleted', (tester) async {
    final services = AppServices.create(AppDatabase.inMemory());
    addTearDown(services.dispose);
    final png = await tester.runAsync(() async {
      final recorder = ui.PictureRecorder();
      Canvas(recorder).drawRect(const Rect.fromLTWH(0, 0, 40, 30), Paint()..color = Colors.teal);
      final image = await recorder.endRecording().toImage(40, 30);
      return (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
    });
    final blob = await tester.runAsync(() => services.blobs.putBytes(png!, mime: 'image/png'));
    final mine = services.templates.create(
      name: 'Lab sheet',
      blob: blob!,
      size: const Size(1000, 750),
    );

    final choice = await _open(tester, mode: TemplatePickerMode.create, services: services);
    await _tapKey(tester, 'category-mine');
    expect(find.text('Lab sheet'), findsOneWidget);
    expect(find.text('Import…'), findsOneWidget);

    await tester.longPress(find.text('Lab sheet'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Rename…'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, 'Lab');
    await tester.tap(find.widgetWithText(FilledButton, 'Rename'));
    await tester.pumpAndSettle();
    expect(services.templates.get(mine.id)!.name, 'Lab');

    await tester.tap(find.text('Lab'));
    await tester.pumpAndSettle();
    expect(find.text('Set by the template'), findsOneWidget);
    await tester.tap(find.text('Use template'));
    await tester.pumpAndSettle();
    expect(choice()!.template.paper, Paper.image(blob));
    expect(choice()!.template.size, const Size(1000, 750));

    await _open(tester, mode: TemplatePickerMode.create, services: services);
    await _tapKey(tester, 'category-mine');
    await tester.longPress(find.text('Lab'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete…'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await tester.pumpAndSettle();
    expect(services.templates.list(), isEmpty);
    expect(find.text('Lab'), findsNothing);
  });
}
