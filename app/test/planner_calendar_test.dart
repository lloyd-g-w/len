import 'dart:io';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/paper_pattern.dart';
import 'package:len/domain/templates/planner_words.dart';
import 'package:pdf/pdf.dart';

DateTime d(int y, int m, int day) => DateTime.utc(y, m, day);

const sunday = PlannerCalendar(weekStart: WeekStart.sunday, language: PlannerLanguage.enUS);
const german = PlannerCalendar(language: PlannerLanguage.de);
const page = Rect.fromLTWH(0, 0, 794, 1123);
const landscape = Rect.fromLTWH(0, 0, 1123, 794);

List<String> texts(Paper paper, [Rect r = page]) =>
    PaperPattern.of(paper, r, page: r).labels.map((l) => l.text).toList();

void main() {
  group('PlannerDates with Sunday weeks', () {
    test('weeks start on the chosen day', () {
      // 11 October 2026 is a Sunday, the 10th a Saturday.
      expect(PlannerDates.weekStart(d(2026, 10, 11), WeekStart.sunday), d(2026, 10, 11));
      expect(PlannerDates.weekStart(d(2026, 10, 10), WeekStart.sunday), d(2026, 10, 4));
      expect(PlannerDates.weekStart(d(2026, 10, 11)), d(2026, 10, 5));
      // Across a year boundary.
      expect(PlannerDates.weekStart(d(2027, 1, 1), WeekStart.sunday), d(2026, 12, 27));
      expect(PlannerDates.weekdays(WeekStart.sunday), [7, 1, 2, 3, 4, 5, 6]);
      expect(PlannerDates.weekdays(WeekStart.monday), [1, 2, 3, 4, 5, 6, 7]);
    });

    test('US week numbers: the week holding 1 January is week 1', () {
      int us(DateTime day) => PlannerDates.weekNumber(day, WeekStart.sunday);
      expect(us(d(2026, 1, 1)), 1); // A Thursday; week from 28 December 2025.
      expect(us(d(2025, 12, 28)), 1);
      expect(us(d(2025, 12, 27)), 52);
      expect(us(d(2026, 1, 4)), 2);
      expect(us(d(2026, 10, 11)), 42);
      expect(us(d(2026, 12, 26)), 52);
      expect(us(d(2026, 12, 27)), 1); // Holds 1 January 2027.
      // 2022 starts on a Saturday: its last week is week 53.
      expect(us(d(2022, 1, 1)), 1);
      expect(us(d(2022, 1, 2)), 2);
      expect(us(d(2022, 12, 31)), 53);
      // Leap year 2024 (starts on a Monday): 29 February.
      expect(us(d(2024, 2, 29)), 9);
      expect(us(d(2024, 12, 28)), 52);
      // Monday weeks stay ISO.
      expect(PlannerDates.weekNumber(d(2021, 1, 3), WeekStart.monday), 53);
    });

    test('month calendars from Sunday', () {
      // March 2026 starts on a Sunday: five rows from Sunday, six from Monday.
      expect(PlannerDates.weeksOfMonth(2026, 3, WeekStart.sunday), hasLength(5));
      expect(PlannerDates.weeksOfMonth(2026, 3, WeekStart.sunday).first, d(2026, 3, 1));
      expect(PlannerDates.weeksOfMonth(2026, 3), hasLength(6));
      // February 2015: 28 days from a Sunday, exactly four rows.
      expect(PlannerDates.weeksOfMonth(2015, 2, WeekStart.sunday), hasLength(4));
      // Leap February 2024 ends on Thursday 29th.
      final feb = PlannerDates.weeksOfMonth(2024, 2, WeekStart.sunday);
      expect(feb.first, d(2024, 1, 28));
      expect(PlannerDates.addDays(feb.last, 4), d(2024, 2, 29));
    });

    test('periods, years included', () {
      expect(PlannerDates.periodStart(PlannerPeriod.year, d(2024, 2, 29)), d(2024, 1, 1));
      expect(PlannerDates.next(PlannerPeriod.year, d(2024, 1, 1)), d(2025, 1, 1));
      expect(PlannerDates.step(PlannerPeriod.week, d(2026, 10, 4), -1), d(2026, 9, 27));
      expect(
        PlannerDates.periodStart(PlannerPeriod.week, d(2026, 10, 8), WeekStart.sunday),
        d(2026, 10, 4),
      );
    });
  });

  group('Paper parameters', () {
    test('the calendar is stored and part of equality', () {
      final week = Paper.planner(PaperStyle.weeklyPlanner, d(2026, 10, 8), calendar: sunday);
      expect(week.date, d(2026, 10, 4));
      expect(week.toData(), {
        'date': '2026-10-04',
        'weekStart': 'sunday',
        'locale': 'en-US',
        'look': PaperLook.standard.toJson(),
      });
      expect(Paper.fromData(PaperStyle.weeklyPlanner, week.toData()), week);
      expect(week.next.date, d(2026, 10, 11));
      expect(week.next.calendar, sunday);
      final monday = Paper.planner(PaperStyle.monthlyCalendar, d(2026, 10, 1));
      final de = Paper.planner(PaperStyle.monthlyCalendar, d(2026, 10, 1), calendar: german);
      expect(de, isNot(monday));
      expect(de.toData()['locale'], 'de');
      final year = Paper.planner(PaperStyle.yearlyOverview, d(2026, 7, 4));
      expect(year.toData()['date'], '2026-01-01');
      expect(year.next.date, d(2027, 1, 1));
    });

    test('every planner field is required and parsed strictly', () {
      final ok = {
        'date': '2026-10-05',
        'weekStart': 'monday',
        'locale': 'de',
        'look': PaperLook.standard.toJson(),
      };
      expect(Paper.fromData(PaperStyle.dailyPlanner, ok)?.calendar, german);
      for (final bad in <Map<String, Object?>>[
        {'date': '2026-10-05'},
        {'date': '2026-10-05', 'weekStart': 'monday'},
        {'date': '2026-10-05', 'locale': 'de'},
        {...ok, 'weekStart': 'saturday'},
        {...ok, 'weekStart': 1},
        {...ok, 'locale': 'de-DE'},
        {...ok, 'locale': 'de_DE'},
        {...ok, 'locale': 'ja'},
        {...ok, 'locale': null},
        {...ok, 'date': '2026-02-30'},
        {'weekStart': 'monday', 'locale': 'de'},
      ]) {
        final data = {'look': PaperLook.standard.toJson(), ...bad};
        expect(Paper.fromData(PaperStyle.dailyPlanner, data), isNull, reason: '$bad');
      }
    });
  });

  group('PlannerLanguage', () {
    test('device locales map to the list, with their customary week start', () {
      expect(PlannerLanguage.forLocale('de', 'AT'), PlannerLanguage.de);
      expect(PlannerLanguage.forLocale('en', 'US'), PlannerLanguage.enUS);
      expect(PlannerLanguage.forLocale('en', 'AU'), PlannerLanguage.enGB);
      expect(PlannerLanguage.forLocale('pt', 'PT'), PlannerLanguage.ptPT);
      expect(PlannerLanguage.forLocale('ja', 'JP'), PlannerLanguage.enGB);
      expect(PlannerCalendar.forLocale('en', 'US'), sunday);
      expect(PlannerCalendar.forLocale('de', 'DE'), german);
      expect(PlannerCalendar.forLocale('ru').weekStart, WeekStart.monday);
      expect(PlannerCalendar.forLocale('pt', 'BR').weekStart, WeekStart.sunday);
      for (final l in PlannerLanguage.values) {
        expect(PlannerLanguage.tryParse(l.tag), l);
      }
    });
  });

  group('localised labels', () {
    test('German, Russian, US English, Greek and Turkish', () {
      final de = PlannerLabels.of(PlannerLanguage.de);
      expect(de.monthName(10), 'Oktober');
      expect(de.weekdayName(DateTime.monday), 'Montag');
      expect(de.weekdayShort(DateTime.monday), 'MO');
      expect(de.longDate(d(2026, 10, 5)), '5. Oktober 2026');
      expect(de.weekRange(d(2026, 10, 5)), '5. – 11. Oktober 2026');
      final ru = PlannerLabels.of(PlannerLanguage.ru);
      expect(ru.monthName(10), 'Октябрь');
      expect(ru.weekRange(d(2026, 10, 5)), '5 – 11 октября 2026\u202fг.');
      expect(ru.weekdayShort(DateTime.sunday), 'ВС');
      final us = PlannerLabels.of(PlannerLanguage.enUS);
      expect(us.weekRange(d(2026, 10, 4)), 'October 4 – 10, 2026');
      expect(us.weekRange(d(2026, 9, 27)), 'September 27 – October 3, 2026');
      expect(
        PlannerLabels.of(PlannerLanguage.es).weekRange(d(2026, 10, 5)),
        '5 – 11 de octubre de 2026',
      );
      final el = PlannerLabels.of(PlannerLanguage.el);
      expect(el.upper(el.weekdayName(DateTime.monday)), 'ΔΕΥΤΕΡΑ');
      final tr = PlannerLabels.of(PlannerLanguage.tr);
      expect(tr.upper(tr.weekdayName(DateTime.saturday)), 'CUMARTESİ');
      expect(PlannerLabels.of(PlannerLanguage.ptPT).weekdayShort(DateTime.sunday), 'DOM');
    });

    test('every language has its headings; a week across months names both', () {
      expect(plannerWords.keys.toSet(), PlannerLanguage.values.toSet());
      for (final words in plannerWords.values) {
        expect(words.week, contains('#'));
      }
      final en = PlannerLabels.of(PlannerLanguage.enGB);
      expect(en.week(41), 'Week 41');
      expect(en.weekMonths(d(2026, 10, 5)), 'October');
      expect(en.weekMonths(d(2026, 12, 28)), 'Dec – Jan');
      expect(PlannerLabels.of(PlannerLanguage.de).weekMonths(d(2026, 9, 28)), 'Sep – Okt');
      final week = Paper.planner(PaperStyle.weeklyPlanner, d(2026, 12, 28));
      expect(texts(week), contains('Dec – Jan'));
    });

    test('pages print in their language', () {
      final month = Paper.planner(PaperStyle.monthlyCalendar, d(2026, 10, 1), calendar: german);
      expect(texts(month), containsAll(['Oktober', '2026', 'MO', 'SO']));
      final day = Paper.planner(PaperStyle.dailyPlanner, d(2026, 10, 5), calendar: german);
      expect(
        texts(day),
        containsAll(['Montag', 'Oktober 2026', 'Woche 41', 'ZEITPLAN', 'PRIORITÄTEN', 'AUFGABEN']),
      );
      expect(texts(day), isNot(contains('Week 41')));
      final week = Paper.planner(PaperStyle.weeklyPlanner, d(2026, 10, 5), calendar: german);
      expect(
        texts(week),
        containsAll([
          'Woche 41',
          'MONTAG',
          'SONNTAG',
          '5. – 11. Oktober 2026',
          'Oktober',
          'NOTIZEN',
        ]),
      );
      const turkish = PlannerCalendar(language: PlannerLanguage.tr);
      final gun = Paper.planner(PaperStyle.dailyPlanner, d(2026, 10, 5), calendar: turkish);
      expect(texts(gun), containsAll(['41. Hafta', 'PROGRAM', 'ÖNCELİKLER', 'YAPILACAKLAR']));
      const russian = PlannerCalendar(weekStart: WeekStart.sunday, language: PlannerLanguage.ru);
      final ned = Paper.planner(PaperStyle.weeklyPlanner, d(2026, 10, 4), calendar: russian);
      expect(texts(ned), containsAll(['Неделя 41', 'ЗАМЕТКИ']));
      expect(month.label, 'Monthly calendar, Oktober 2026');
    });

    test('the bundled Inter covers every label of every language', () {
      Set<int> runes(String file) =>
          TtfParser(ByteData.sublistView(File('assets/fonts/$file').readAsBytesSync()))
              .charToGlyphIndexMap
              .keys
              .toSet();
      final fonts = [runes('Inter-Regular.ttf'), runes('Inter-Bold.ttf')];
      for (final language in PlannerLanguage.values) {
        final calendar = PlannerCalendar(language: language);
        for (final style in PaperStyle.builtIn.where((s) => s.isPlanner)) {
          for (final month in [1, 2, 3, 5, 8, 9, 10, 11, 12]) {
            final paper = Paper.planner(style, d(2026, month, 3), calendar: calendar);
            for (final l in PaperPattern.of(paper, page, page: page).labels) {
              final missing = l.text.runes.where(
                (r) => r != 32 && !fonts[l.bold ? 1 : 0].contains(r),
              );
              expect(missing, isEmpty, reason: '${language.tag} "${l.text}"');
            }
          }
        }
      }
    });
  });

  group('PlannerPlan with options', () {
    test('Sunday weeks', () {
      final plan = PlannerPlan(start: d(2026, 10, 1), calendar: sunday);
      final weeks = plan.papersFor(PaperStyle.weeklyPlanner);
      expect(weeks.map((p) => p.date), [
        d(2026, 9, 27),
        d(2026, 10, 4),
        d(2026, 10, 11),
        d(2026, 10, 18),
        d(2026, 10, 25),
      ]);
      expect(weeks.every((p) => p.calendar == sunday), isTrue);

      final linked = plan.copyWith(linked: true).papersFor(PaperStyle.monthlyCalendar);
      expect(
        linked.first,
        Paper.planner(PaperStyle.monthlyCalendar, d(2026, 10, 1), calendar: sunday),
      );
      expect(linked[1], Paper.planner(PaperStyle.weeklyPlanner, d(2026, 9, 27), calendar: sunday));
      expect(
        linked[2].date,
        d(2026, 9, 27),
        reason: 'each week is followed by its days from Sunday',
      );
      expect(linked.every((p) => p.calendar == sunday), isTrue);
    });

    test('yearly pages and year overviews before the months', () {
      final plan = PlannerPlan(start: d(2026, 11, 1), months: 3);
      expect(plan.papersFor(PaperStyle.yearlyOverview).map((p) => p.date), [
        d(2026, 1, 1),
        d(2027, 1, 1),
      ]);
      expect(
        PlannerPlan(start: d(2026, 1, 1), months: 12).papersFor(PaperStyle.yearlyOverview),
        hasLength(1),
      );

      final plain = plan.copyWith(yearOverview: true).papersFor(PaperStyle.monthlyCalendar);
      expect(plain.map((p) => (p.style, p.date)), [
        (PaperStyle.yearlyOverview, d(2026, 1, 1)),
        (PaperStyle.monthlyCalendar, d(2026, 11, 1)),
        (PaperStyle.monthlyCalendar, d(2026, 12, 1)),
        (PaperStyle.yearlyOverview, d(2027, 1, 1)),
        (PaperStyle.monthlyCalendar, d(2027, 1, 1)),
      ]);

      final linked = plan
          .copyWith(yearOverview: true, linked: true)
          .papersFor(PaperStyle.monthlyCalendar);
      expect(linked.first.style, PaperStyle.yearlyOverview);
      final y27 = linked.indexOf(Paper.planner(PaperStyle.yearlyOverview, d(2027, 1, 1)));
      expect(linked[y27 + 1], Paper.planner(PaperStyle.monthlyCalendar, d(2027, 1, 1)));
      expect(linked.where((p) => p.style == PaperStyle.yearlyOverview), hasLength(2));
      // Every link of every page leads to a page of the planner.
      for (final paper in linked) {
        for (final link in PaperPattern.of(paper, page, page: page).links) {
          if (link.target.date!.isBefore(d(2026, 10, 26)) ||
              !link.target.date!.isBefore(d(2027, 2, 1))) {
            continue; // Days of the years outside the plan.
          }
          expect(linked, contains(link.target), reason: '$paper → ${link.target}');
        }
      }
    });
  });

  group('year overview and Sunday calendars', () {
    test('the year overview links months and days', () {
      final year = Paper.planner(PaperStyle.yearlyOverview, d(2024, 1, 1), calendar: sunday);
      for (final r in [page, landscape]) {
        final pattern = PaperPattern.of(year, r, page: r);
        final months = [
          for (final l in pattern.links)
            if (l.target.style == PaperStyle.monthlyCalendar) l.target,
        ];
        expect(months, [
          for (var m = 1; m <= 12; m++)
            Paper.planner(PaperStyle.monthlyCalendar, d(2024, m, 1), calendar: sunday),
        ]);
        final days = [
          for (final l in pattern.links)
            if (l.target.style == PaperStyle.dailyPlanner) l,
        ];
        expect(days, hasLength(366), reason: 'leap year');
        expect(days.map((l) => l.target.calendar).toSet(), {sunday});
        for (final l in pattern.links) {
          expect(r.contains(l.rect.center), isTrue);
        }
        // 3 × 4 portrait, 4 × 3 landscape: April's title is in the second
        // row on portrait pages, in the first on landscape ones.
        final titles = [
          for (final l in pattern.links)
            if (l.target.style == PaperStyle.monthlyCalendar) l.rect,
        ];
        final january = titles[0], april = titles[3];
        expect(april.top > january.bottom, r == page);
      }
      expect(texts(year), containsAll(['2024', 'January', 'December', 'S', 'M', '29']));
      // The first row of a mini calendar starts on Sunday: S M T W T F S.
      final heads = [
        for (final l in PaperPattern.of(year, page, page: page).labels.skip(2).take(7)) l.text,
      ];
      expect(heads, ['S', 'M', 'T', 'W', 'T', 'F', 'S']);
    });

    test('a Sunday month calendar lays out weeks from Sunday and links to the year', () {
      final oct = Paper.planner(PaperStyle.monthlyCalendar, d(2026, 10, 1), calendar: sunday);
      final pattern = PaperPattern.of(oct, page, page: page);
      final heads = [
        for (final l in pattern.labels)
          if (l.text.length == 3 && l.text == l.text.toUpperCase()) l.text,
      ];
      expect(heads, ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT']);
      // Weekend heads are muted wherever they fall.
      expect(
        [
          for (final l in pattern.labels)
            if (heads.contains(l.text) && l.muted) l.text,
        ],
        ['SUN', 'SAT'],
      );
      final weeks = [
        for (final l in pattern.links)
          if (l.target.style == PaperStyle.weeklyPlanner) l.target,
      ];
      expect(
        weeks.first,
        Paper.planner(PaperStyle.weeklyPlanner, d(2026, 9, 27), calendar: sunday),
      );
      expect(weeks, hasLength(5));
      expect(
        pattern.links.where((l) => l.target.style == PaperStyle.yearlyOverview).single.target,
        Paper.planner(PaperStyle.yearlyOverview, d(2026, 1, 1), calendar: sunday),
      );
      // US week numbers: 27 September 2026 is in week 40.
      expect(texts(oct), containsAll(['40', '44']));
    });
  });
}
