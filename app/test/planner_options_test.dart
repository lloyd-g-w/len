import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/data/app_database.dart';
import 'package:len/domain/paper.dart';
import 'package:len/features/documents/template_picker.dart';
import 'package:len/ui/app_theme.dart';

final _today = DateTime.utc(2026, 10, 11);

/// Opens the "Add page" picker on a device set to [locale]; returns a
/// getter for its result.
Future<TemplateChoice? Function()> _open(
  WidgetTester tester,
  AppServices services, {
  Locale locale = const Locale('en', 'US'),
  PageTemplate initial = const PageTemplate(),
  TemplatePickerMode mode = TemplatePickerMode.addPage,
}) async {
  tester.platformDispatcher.localeTestValue = locale;
  addTearDown(tester.platformDispatcher.clearLocaleTestValue);
  TemplateChoice? choice;
  await tester.pumpWidget(
    AppScope(
      services: services,
      child: MaterialApp(
        theme: AppTheme.light(),
        home: Scaffold(
          body: Builder(
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
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
  return () => choice;
}

Future<void> _tap(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await tester.pumpAndSettle();
  await tester.tap(finder);
  await tester.pumpAndSettle();
}

void main() {
  late AppServices services;
  setUp(() => services = AppServices.create(AppDatabase.inMemory()));
  tearDown(() => services.dispose());

  testWidgets('the language and week start follow the device; More options changes the week', (
    tester,
  ) async {
    var choice = await _open(tester, services);
    await _tap(tester, find.text('Monthly calendar'));
    // A US device: Sunday weeks, US English. The week start is under More options.
    expect(find.text('Week starts on'), findsNothing);
    await _tap(tester, find.text('More options'));
    expect(find.text('Week starts on'), findsOneWidget);
    final weekStart = find.byKey(const ValueKey('planner-week-start'));
    expect(tester.widget<SegmentedButton<WeekStart>>(weekStart).selected, {WeekStart.sunday});
    expect(find.text('October 2026'), findsOneWidget);

    // Monday weeks, starting with the year overview.
    await _tap(tester, find.descendant(of: weekStart, matching: find.text('Monday')));
    await _tap(tester, find.byKey(const ValueKey('planner-year')));
    expect(find.text('Add 2 pages'), findsOneWidget);
    await tester.tap(find.text('Add 2 pages'));
    await tester.pumpAndSettle();
    const usMonday = PlannerCalendar(language: PlannerLanguage.enUS);
    expect(choice()!.papers, [
      Paper.planner(PaperStyle.yearlyOverview, _today, calendar: usMonday),
      Paper.planner(PaperStyle.monthlyCalendar, _today, calendar: usMonday),
    ]);

    // The next planner takes the device's language and week start again.
    choice = await _open(tester, services, locale: const Locale('de', 'DE'));
    await _tap(tester, find.text('Weekly planner'));
    await _tap(tester, find.text('Add 5 pages'));
    expect(
      choice()!.papers.first,
      Paper.planner(
        PaperStyle.weeklyPlanner,
        DateTime.utc(2026, 9, 28),
        calendar: const PlannerCalendar(language: PlannerLanguage.de),
      ),
    );
  });

  testWidgets('changing a page keeps its calendar; Sunday re-dates its week', (tester) async {
    const sunday = PlannerCalendar(weekStart: WeekStart.sunday, language: PlannerLanguage.enUS);
    final choice = await _open(
      tester,
      services,
      locale: const Locale('de', 'DE'),
      mode: TemplatePickerMode.change,
      initial: PageTemplate(
        paper: Paper.planner(PaperStyle.weeklyPlanner, _today, calendar: sunday),
      ),
    );
    expect(find.text('Week 42 · October 11 – 17, 2026'), findsOneWidget);
    await _tap(tester, find.text('More options'));
    final weekStart = find.byKey(const ValueKey('planner-week-start'));
    await _tap(tester, find.descendant(of: weekStart, matching: find.text('Monday')));
    expect(find.text('Week 41 · October 5 – 11, 2026'), findsOneWidget);
    await tester.tap(find.text('Apply'));
    await tester.pumpAndSettle();
    expect(
      choice()!.template.paper,
      Paper.planner(
        PaperStyle.weeklyPlanner,
        DateTime.utc(2026, 10, 5),
        calendar: sunday.copyWith(weekStart: WeekStart.monday),
      ),
    );
  });

  testWidgets('the options fit a phone at 1.3× text', (tester) async {
    tester.view.physicalSize = const Size(360, 740);
    tester.view.devicePixelRatio = 1;
    tester.platformDispatcher.textScaleFactorTestValue = 1.3;
    addTearDown(tester.view.reset);
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await _open(tester, services, locale: const Locale('pt', 'PT'));
    await _tap(tester, find.text('Monthly calendar'));
    expect(find.text('Outubro de 2026'), findsOneWidget);
    await tester.ensureVisible(find.byKey(const ValueKey('planner-year')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
