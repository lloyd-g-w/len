import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/paper.dart';

import 'support/property.dart';

DateTime _utc(int y, [int m = 1, int d = 1]) => DateTime.utc(y, m, d);

/// A random day from 1600 to 2400 (a leap day now and then, years either
/// side of the leap-century rules), as a UTC midnight.
DateTime _date(math.Random r) {
  final y = 1600 + r.nextInt(801);
  if (r.nextInt(10) == 0) {
    // Year ends, leap days and month ends, where week numbers turn.
    final m = [1, 2, 3, 12][r.nextInt(4)];
    return _utc(y, m, 1 + r.nextInt(PlannerDates.daysInMonth(y, m)));
  }
  final m = 1 + r.nextInt(12);
  return _utc(y, m, 1 + r.nextInt(PlannerDates.daysInMonth(y, m)));
}

bool _leap(int y) => y % 4 == 0 && (y % 100 != 0 || y % 400 == 0);

/// Day of the year (1-based), counted by hand.
int _ordinal(DateTime d) {
  const days = [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31];
  var n = d.day;
  for (var m = 1; m < d.month; m++) {
    n += days[m - 1] + (m == 2 && _leap(d.year) ? 1 : 0);
  }
  return n;
}

/// Weekday (1 = Monday … 7 = Sunday) by Zeller's congruence, not `DateTime`.
int _weekday(int y, int m, int d) {
  if (m < 3) {
    m += 12;
    y -= 1;
  }
  final k = y % 100, j = y ~/ 100;
  final h = (d + (13 * (m + 1)) ~/ 5 + k + k ~/ 4 + j ~/ 4 + 5 * j) % 7; // 0 = Saturday
  return (h + 5) % 7 + 1;
}

/// ISO 8601 weeks in [year]: 53 when it starts on a Thursday, or on a
/// Wednesday in a leap year.
int _isoWeeks(int year) {
  final jan1 = _weekday(year, 1, 1);
  return jan1 == 4 || (jan1 == 3 && _leap(year)) ? 53 : 52;
}

/// ISO week number by the textbook ordinal formula.
int _isoWeekRef(DateTime d) {
  final w = (_ordinal(d) - _weekday(d.year, d.month, d.day) + 10) ~/ 7;
  if (w < 1) return _isoWeeks(d.year - 1);
  if (w > _isoWeeks(d.year)) return 1;
  return w;
}

/// US week number: week 1 holds 1 January; the last days of December
/// share the next year's week 1.
int _sundayWeekRef(DateTime d) {
  final jan1 = _weekday(d.year, 1, 1) % 7; // 0 = Sunday
  final daysLeft = (_leap(d.year) ? 366 : 365) - _ordinal(d);
  final weekdayFromSunday = _weekday(d.year, d.month, d.day) % 7;
  // Its week holds the next 1 January (daysLeft + 1 days on).
  if (daysLeft + 1 <= 6 - weekdayFromSunday) return 1;
  return (_ordinal(d) - 1 + jan1) ~/ 7 + 1;
}

void main() {
  test('day arithmetic matches a hand-made calendar', () async {
    await forAll(
      (r) => (_date(r), r.nextInt(2000) - 1000),
      (c) {
        final (d, n) = c;
        expect(d.weekday, _weekday(d.year, d.month, d.day), reason: 'Zeller agrees');
        final moved = PlannerDates.addDays(d, n);
        expect(moved.isUtc, isTrue);
        expect(moved.hour, 0);
        expect(moved.difference(d).inDays, n);
        expect(PlannerDates.addDays(moved, -n), d);
        expect(PlannerDates.daysInMonth(d.year, 2), _leap(d.year) ? 29 : 28);
        expect(PlannerDates.decode(PlannerDates.encode(d)), d);
      },
      runs: 2000,
      seed: 1,
    );
  });

  test('a local time, also around daylight saving changes, is its own calendar day', () async {
    await forAll(
      (r) {
        // Late March and October Sundays (European and US changes), at any hour.
        final y = 1970 + r.nextInt(100), m = [3, 10, 11][r.nextInt(3)];
        return DateTime(y, m, 1 + r.nextInt(31), r.nextInt(24), r.nextInt(60));
      },
      (local) {
        final day = PlannerDates.day(local);
        expect(day, _utc(local.year, local.month, local.day));
        for (final period in PlannerPeriod.values) {
          final start = PlannerDates.periodStart(period, local);
          expect(start.isUtc, isTrue);
          expect(start.isAfter(day), isFalse);
          expect(PlannerDates.next(period, start).isAfter(day), isTrue, reason: '$period');
        }
      },
      runs: 1000,
      seed: 2,
    );
  });

  test('week numbers match ISO 8601 and the US rule', () async {
    await forAll(
      _date,
      (d) {
        expect(PlannerDates.isoWeek(d), _isoWeekRef(d), reason: 'ISO');
        expect(PlannerDates.weekNumber(d, WeekStart.monday), _isoWeekRef(d));
        expect(PlannerDates.sundayWeek(d), _sundayWeekRef(d), reason: 'US');
        // A number changes only where a week starts.
        for (final start in WeekStart.values) {
          final tomorrow = PlannerDates.addDays(d, 1);
          final a = PlannerDates.weekNumber(d, start), b = PlannerDates.weekNumber(tomorrow, start);
          if (tomorrow.weekday == start.weekday) {
            expect(b, anyOf(a + 1, 1), reason: '$start: a new week');
          } else {
            expect(b, a, reason: '$start: the same week');
          }
        }
      },
      runs: 3000,
      seed: 3,
    );
  });

  test('periods: starts are on their weekday and stepping is invertible', () async {
    await forAll(
      (r) => (_date(r), WeekStart.values[r.nextInt(2)], r.nextInt(60) - 30),
      (c) {
        final (d, ws, n) = c;
        final week = PlannerDates.weekStart(d, ws);
        expect(week.weekday, ws.weekday);
        expect(d.difference(week).inDays, inInclusiveRange(0, 6));
        expect(PlannerDates.weekdays(ws).first, ws.weekday);
        expect(PlannerDates.weekdays(ws).toSet(), hasLength(7));
        for (final period in PlannerPeriod.values) {
          final start = PlannerDates.periodStart(period, d, ws);
          final there = PlannerDates.step(period, start, n);
          expect(PlannerDates.periodStart(period, there, ws), there, reason: '$period start');
          expect(PlannerDates.step(period, there, -n), start, reason: '$period back');
          // The period holds d, and the next one starts after it.
          expect(start.isAfter(d), isFalse);
          expect(PlannerDates.next(period, start).isAfter(d), isTrue);
        }
      },
      runs: 2000,
      seed: 4,
    );
  });

  test('a month calendar has 4–6 weeks of 7 days, every day of the month once', () async {
    await forAll(
      (r) => (_date(r), WeekStart.values[r.nextInt(2)]),
      (c) {
        final (d, ws) = c;
        final weeks = PlannerDates.weeksOfMonth(d.year, d.month, ws);
        expect(weeks.length, inInclusiveRange(4, 6));
        final days = [
          for (final w in weeks)
            for (var i = 0; i < 7; i++) PlannerDates.addDays(w, i),
        ];
        expect(days.toSet(), hasLength(days.length), reason: 'no day twice');
        final inMonth = days.where((x) => x.month == d.month && x.year == d.year).toList();
        expect(inMonth, [
          for (var i = 1; i <= PlannerDates.daysInMonth(d.year, d.month); i++)
            _utc(d.year, d.month, i),
        ]);
        expect(weeks.first.weekday, ws.weekday);
        expect(days.first.isAfter(_utc(d.year, d.month)), isFalse);
      },
      runs: 2000,
      seed: 5,
    );
  });

  test('planner pages: every day of the range once, and a page for every date', () async {
    await forAll(
      (r) => PlannerPlan(
        start: _date(r),
        months: 1 + r.nextInt(PlannerPlan.maxMonths),
        linked: r.nextBool(),
        yearOverview: r.nextBool(),
        calendar: PlannerCalendar(
          weekStart: WeekStart.values[r.nextInt(2)],
          language: PlannerLanguage.values[r.nextInt(PlannerLanguage.values.length)],
        ),
      ),
      (plan) {
        final days = [
          for (var x = plan.start; x.isBefore(plan.end); x = PlannerDates.addDays(x, 1)) x,
        ];
        final ws = plan.calendar.weekStart;

        // Daily: each day once, in order; the page for a day is the one at its index.
        final daily = plan.papersFor(PaperStyle.dailyPlanner);
        expect([for (final p in daily) p.date], days);
        for (final (i, x) in days.indexed) {
          expect(
            daily.indexOf(Paper.planner(PaperStyle.dailyPlanner, x, calendar: plan.calendar)),
            i,
          );
        }

        // Weekly: consecutive weeks of 7 days covering each day once.
        final weekly = plan.papersFor(PaperStyle.weeklyPlanner);
        final covered = [
          for (final p in weekly)
            for (var i = 0; i < 7; i++) PlannerDates.addDays(p.date!, i),
        ];
        expect(covered.toSet(), hasLength(covered.length));
        expect(covered.toSet().containsAll(days), isTrue);
        expect(covered.where((x) => !days.contains(x)).length, lessThan(14));
        for (final p in weekly) {
          expect(p.date!.weekday, ws.weekday);
        }

        // Monthly: the months in order; linked, every day and week of the
        // range has its page, once, each day after its week.
        final monthly = plan.papersFor(PaperStyle.monthlyCalendar);
        final months = [
          for (final p in monthly)
            if (p.style == PaperStyle.monthlyCalendar) p.date,
        ];
        expect(months, [
          for (var i = 0; i < plan.months; i++) PlannerDates.addMonths(plan.start, i),
        ]);
        final overviews = monthly.where((p) => p.style == PaperStyle.yearlyOverview).toList();
        if (plan.yearOverview) {
          expect(monthly.first.style, PaperStyle.yearlyOverview);
          expect(overviews.map((p) => p.date).toSet(), hasLength(overviews.length));
        } else {
          expect(overviews, isEmpty);
        }
        if (plan.linked) {
          final dayPages = [
            for (final p in monthly)
              if (p.style == PaperStyle.dailyPlanner) p.date!,
          ];
          expect(dayPages.toSet(), hasLength(dayPages.length), reason: 'no day twice');
          expect(dayPages.toSet().containsAll(days), isTrue);
          for (final (i, p) in monthly.indexed) {
            if (p.style != PaperStyle.dailyPlanner) continue;
            final week = monthly.lastIndexWhere((q) => q.style == PaperStyle.weeklyPlanner, i);
            expect(
              monthly[week].date,
              PlannerDates.weekStart(p.date!, ws),
              reason: 'after its week',
            );
          }
        }

        // Pages survive storage.
        for (final p in [daily.first, weekly.last, monthly.last]) {
          expect(Paper.fromData(p.style, p.toData()), p);
        }
      },
      runs: 150,
      seed: 6,
    );
  });
}
