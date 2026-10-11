import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/paper_pattern.dart';

DateTime d(int y, int m, int day) => DateTime.utc(y, m, day);

void main() {
  group('PlannerDates', () {
    test('days in month, leap years included', () {
      expect(PlannerDates.daysInMonth(2024, 2), 29);
      expect(PlannerDates.daysInMonth(2023, 2), 28);
      expect(PlannerDates.daysInMonth(2000, 2), 29);
      expect(PlannerDates.daysInMonth(1900, 2), 28);
      expect(PlannerDates.daysInMonth(2026, 12), 31);
      expect(PlannerDates.daysInMonth(2026, 4), 30);
    });

    test('weeks start on Monday; ISO week numbers', () {
      expect(PlannerDates.weekStart(d(2026, 10, 11)), d(2026, 10, 5)); // A Sunday.
      expect(PlannerDates.weekStart(d(2026, 10, 5)), d(2026, 10, 5));
      expect(PlannerDates.isoWeek(d(2026, 10, 5)), 41);
      expect(PlannerDates.isoWeek(d(2021, 1, 3)), 53); // Belongs to 2020's last week.
      expect(PlannerDates.isoWeek(d(2024, 12, 30)), 1); // Belongs to 2025.
      expect(PlannerDates.isoWeek(d(2026, 1, 1)), 1);
    });

    test('month calendars have four to six week rows', () {
      // February 2021 starts on a Monday and has 28 days: exactly 4 rows.
      expect(PlannerDates.weeksOfMonth(2021, 2), [
        d(2021, 2, 1),
        d(2021, 2, 8),
        d(2021, 2, 15),
        d(2021, 2, 22),
      ]);
      // Leap February 2024 starts on a Thursday: 5 rows, the last holding the 29th.
      final feb = PlannerDates.weeksOfMonth(2024, 2);
      expect(feb.first, d(2024, 1, 29));
      expect(feb, hasLength(5));
      expect(PlannerDates.addDays(feb.last, 3), d(2024, 2, 29));
      // March 2026 starts on a Sunday and has 31 days: 6 rows.
      expect(PlannerDates.weeksOfMonth(2026, 3), hasLength(6));
    });

    test('dates are stored as yyyy-mm-dd and parsed strictly', () {
      expect(PlannerDates.encode(d(2024, 2, 29)), '2024-02-29');
      expect(PlannerDates.decode('2024-02-29'), d(2024, 2, 29));
      expect(PlannerDates.decode('2023-02-29'), isNull);
      expect(PlannerDates.decode('2026-13-01'), isNull);
      expect(PlannerDates.decode('2026-1-01'), isNull);
      expect(PlannerDates.decode('yesterday'), isNull);
    });

    test('labels', () {
      final en = PlannerLabels.of(PlannerLanguage.enGB);
      expect(en.weekRange(d(2026, 10, 5)), '5 – 11 October 2026');
      expect(en.weekRange(d(2026, 9, 28)), '28 September – 4 October 2026');
      expect(en.weekRange(d(2025, 12, 29)), '29 December 2025 – 4 January 2026');
      expect(en.describe(PlannerPeriod.day, d(2026, 10, 11), WeekStart.monday), 'Sun, 11 Oct 2026');
    });
  });

  group('Paper', () {
    test('planner papers start at their period and round-trip', () {
      final week = Paper.planner(PaperStyle.weeklyPlanner, d(2026, 10, 9));
      expect(week.date, d(2026, 10, 5));
      expect(week.toData(), {'date': '2026-10-05', 'weekStart': 'monday', 'locale': 'en-GB'});
      expect(Paper.fromData(PaperStyle.weeklyPlanner, week.toData()), week);
      expect(Paper.planner(PaperStyle.monthlyCalendar, d(2024, 2, 29)).date, d(2024, 2, 1));
    });

    test('next advances planners by their period', () {
      expect(Paper.planner(PaperStyle.dailyPlanner, d(2024, 2, 28)).next.date, d(2024, 2, 29));
      expect(Paper.planner(PaperStyle.dailyPlanner, d(2023, 2, 28)).next.date, d(2023, 3, 1));
      expect(Paper.planner(PaperStyle.monthlyCalendar, d(2026, 12, 1)).next.date, d(2027, 1, 1));
      expect(const Paper(PaperStyle.dotted).next, const Paper(PaperStyle.dotted));
    });

    test('parameters are validated', () {
      expect(Paper.fromData(PaperStyle.dailyPlanner, const {}), isNull);
      expect(Paper.fromData(PaperStyle.dailyPlanner, const {'date': 'soon'}), isNull);
      expect(Paper.fromData(PaperStyle.image, const {'image': 'not-a-hash'}), isNull);
      final image = Paper.image('a' * 64);
      expect(Paper.fromData(PaperStyle.image, image.toData()), image);
      expect(Paper.fromData(PaperStyle.cornell, const {}), const Paper(PaperStyle.cornell));
      expect(Paper.defaultFor(PaperStyle.image, today: d(2026, 1, 1)), isNull);
    });
  });

  group('PlannerPlan', () {
    test('daily pages cover every day, 29 in a leap February', () {
      final feb24 = PlannerPlan(start: d(2024, 2, 10)).papersFor(PaperStyle.dailyPlanner);
      expect(feb24, hasLength(29));
      expect(feb24.first.date, d(2024, 2, 1));
      expect(feb24.last.date, d(2024, 2, 29));
      expect(PlannerPlan(start: d(2023, 2, 1)).papersFor(PaperStyle.dailyPlanner), hasLength(28));
      final year = PlannerPlan(start: d(2024, 1, 1), months: 12);
      expect(year.papersFor(PaperStyle.dailyPlanner), hasLength(366));
    });

    test('weekly pages cover every week overlapping the range', () {
      final oct = PlannerPlan(start: d(2026, 10, 1)).papersFor(PaperStyle.weeklyPlanner);
      expect(oct.map((p) => p.date), [
        d(2026, 9, 28),
        d(2026, 10, 5),
        d(2026, 10, 12),
        d(2026, 10, 19),
        d(2026, 10, 26),
      ]);
    });

    test('monthly pages, plain and linked', () {
      final plain = PlannerPlan(start: d(2026, 11, 1), months: 3);
      expect(plain.papersFor(PaperStyle.monthlyCalendar).map((p) => p.date), [
        d(2026, 11, 1),
        d(2026, 12, 1),
        d(2027, 1, 1),
      ]);

      final linked = PlannerPlan(start: d(2024, 2, 1), months: 2, linked: true);
      final pages = linked.papersFor(PaperStyle.monthlyCalendar);
      final months = [
        for (final p in pages)
          if (p.style == PaperStyle.monthlyCalendar) p.date,
      ];
      final weeks = [
        for (final p in pages)
          if (p.style == PaperStyle.weeklyPlanner) p.date,
      ];
      final days = [
        for (final p in pages)
          if (p.style == PaperStyle.dailyPlanner) p.date,
      ];
      expect(months, [d(2024, 2, 1), d(2024, 3, 1)]);
      expect(pages.first.style, PaperStyle.monthlyCalendar);
      // Weeks from the one holding 1 February to the one holding 31 March.
      expect(weeks.first, d(2024, 1, 29));
      expect(weeks.last, d(2024, 3, 25));
      expect(weeks, hasLength(9));
      expect(days, hasLength(9 * 7));
      expect(days.toSet(), hasLength(days.length), reason: 'each day once');
      // Each week page is followed by its seven days.
      final w = pages.indexWhere((p) => p.style == PaperStyle.weeklyPlanner);
      expect(
        [for (final p in pages.sublist(w + 1, w + 8)) p.date],
        [for (var i = 0; i < 7; i++) PlannerDates.addDays(weeks.first!, i)],
      );
      // March's page comes right before the first week starting in March.
      final march = pages.indexOf(Paper.planner(PaperStyle.monthlyCalendar, d(2024, 3, 1)));
      expect(pages[march + 1], Paper.planner(PaperStyle.weeklyPlanner, d(2024, 3, 4)));
    });

    test('every link on a linked planner leads to one of its pages', () {
      final pages = PlannerPlan(
        start: d(2026, 10, 1),
        linked: true,
        yearOverview: true,
      ).papersFor(PaperStyle.monthlyCalendar);
      const page = Rect.fromLTWH(0, 0, 794, 1123);
      expect(pages.first, Paper.planner(PaperStyle.yearlyOverview, d(2026, 1, 1)));
      final october = pages.firstWhere((p) => p.style == PaperStyle.monthlyCalendar);
      final month = PaperPattern.of(october, page, page: page);
      final inMonth = [
        for (final l in month.links)
          if (l.target.style == PaperStyle.dailyPlanner && l.target.date!.month == 10) l,
      ];
      expect(inMonth, hasLength(31));
      for (final link in month.links) {
        expect(pages, contains(link.target), reason: '${link.target}');
      }
      final week = pages.firstWhere((p) => p.style == PaperStyle.weeklyPlanner);
      for (final link in PaperPattern.of(week, page, page: page).links) {
        expect(pages, contains(link.target), reason: '${link.target}');
      }
    });
  });

  group('planner layouts', () {
    const page = Rect.fromLTWH(0, 0, 794, 1123);
    const landscape = Rect.fromLTWH(0, 0, 1123, 794);

    List<String> texts(Paper paper, [Rect r = page]) =>
        PaperPattern.of(paper, r, page: r).labels.map((l) => l.text).toList();

    test('the month calendar prints the right days (leap February)', () {
      final feb = Paper.planner(PaperStyle.monthlyCalendar, d(2024, 2, 1));
      final pattern = PaperPattern.of(feb, page, page: page);
      expect(texts(feb), containsAll(['February', '2024', 'MON', 'SUN', '29']));
      final bold = [
        for (final l in pattern.labels)
          if (l.bold && int.tryParse(l.text) != null) l.text,
      ];
      expect(bold, [for (var i = 1; i <= 29; i++) '$i'], reason: 'days of the month in order');
      // 35 cells (5 weeks), the 6 outside February tinted.
      expect(pattern.fills, hasLength(35 - 29));
      // Week numbers 5 to 9 lead to the weekly pages.
      final weeks = [
        for (final l in pattern.links)
          if (l.target.style == PaperStyle.weeklyPlanner) l,
      ];
      expect(weeks.map((l) => PlannerDates.isoWeek(l.target.date!)), [5, 6, 7, 8, 9]);
      expect(
        texts(Paper.planner(PaperStyle.monthlyCalendar, d(2023, 2, 1))),
        isNot(contains('29')),
      );
    });

    test('the week page has a box per day with its date', () {
      final week = Paper.planner(PaperStyle.weeklyPlanner, d(2026, 9, 28));
      expect(
        texts(week),
        containsAll([
          'Week 40',
          '28 September – 4 October 2026',
          'MONDAY',
          'SUNDAY',
          'NOTES',
          '28',
          '4',
        ]),
      );
      for (final r in [page, landscape]) {
        final links = PaperPattern.of(week, r, page: r).links;
        expect(links.where((l) => l.target.style == PaperStyle.dailyPlanner), hasLength(7));
        expect(
          links.where((l) => l.target.style == PaperStyle.monthlyCalendar).single.target.date,
          d(2026, 10, 1),
        );
        for (final l in links) {
          expect(r.contains(l.rect.center), isTrue);
        }
      }
    });

    test('the day page links to its week and month', () {
      final day = Paper.planner(PaperStyle.dailyPlanner, d(2026, 10, 11));
      expect(texts(day), containsAll(['11', 'Sunday', 'October 2026', 'Week 41', '7:00', '21:00']));
      final targets = PaperPattern.of(day, page, page: page).links.map((l) => l.target).toSet();
      expect(targets, {
        Paper.planner(PaperStyle.weeklyPlanner, d(2026, 10, 5)),
        Paper.planner(PaperStyle.monthlyCalendar, d(2026, 10, 1)),
      });
    });

    test('layouts stay inside every page format', () {
      for (final format in PageFormat.values) {
        for (final o in PageOrientation.values) {
          final r = Offset.zero & format.sizeFor(o);
          for (final style in PaperStyle.builtIn) {
            final paper = Paper.defaultFor(style, today: d(2024, 2, 29))!;
            final p = PaperPattern.of(paper, r, page: r);
            for (final l in p.lines) {
              expect(r.inflate(0.01).contains(l.a) && r.inflate(0.01).contains(l.b), isTrue);
            }
            for (final l in p.labels) {
              expect(
                r.inflate(0.01).contains(l.box.topLeft),
                isTrue,
                reason: '$style $format $o ${l.text}',
              );
              expect(
                r.inflate(0.01).contains(l.box.bottomRight),
                isTrue,
                reason: '$style $format $o ${l.text}',
              );
            }
          }
        }
      }
    });

    test('repeating detail drops out when too dense, structure stays', () {
      final graph = const Paper(PaperStyle.graph);
      final all = PaperPattern.of(graph, page, page: page);
      final coarse = PaperPattern.of(graph, page, page: page, minPitch: 10);
      expect(all.lines.where((l) => l.weight == PatternWeight.fine), isNotEmpty);
      expect(coarse.lines.where((l) => l.weight == PatternWeight.fine), isEmpty);
      expect(coarse.lines.where((l) => l.weight == PatternWeight.heavy), isNotEmpty);

      final month = Paper.planner(PaperStyle.monthlyCalendar, d(2026, 10, 1));
      final far = PaperPattern.of(month, page, page: page, minPitch: 100);
      expect(far.lines.where((l) => l.weight == PatternWeight.heavy), isNotEmpty);
      expect(far.labels, isNotEmpty);
    });
  });
}
