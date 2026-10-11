import 'paper_style.dart';
import 'planner_calendar.dart';

/// Calendar arithmetic for planner templates (labels: `PlannerLabels`).
///
/// Dates are UTC midnights (no time zones or daylight saving to trip
/// over). Weeks start on a [WeekStart]; Monday weeks are numbered as in
/// ISO 8601, Sunday weeks as is usual in the US (see [weekNumber]).
abstract final class PlannerDates {
  /// The calendar day of [d] (its local date) as a UTC midnight.
  static DateTime day(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  /// The first day of [d]'s week.
  static DateTime weekStart(DateTime d, [WeekStart start = WeekStart.monday]) {
    final day = PlannerDates.day(d);
    return addDays(day, -((day.weekday - start.weekday) % 7));
  }

  static DateTime monthStart(DateTime d) => DateTime.utc(d.year, d.month);

  static DateTime yearStart(DateTime d) => DateTime.utc(d.year);

  /// Days in [month] (1–12) of [year], leap years included.
  static int daysInMonth(int year, int month) => DateTime.utc(year, month + 1, 0).day;

  /// [d] moved by [days] calendar days.
  static DateTime addDays(DateTime d, int days) => DateTime.utc(d.year, d.month, d.day + days);

  /// [d] moved by [months] (to the first of that month).
  static DateTime addMonths(DateTime d, int months) => DateTime.utc(d.year, d.month + months);

  /// The first day of the period of [period] containing [d].
  static DateTime periodStart(
    PlannerPeriod period,
    DateTime d, [
    WeekStart start = WeekStart.monday,
  ]) => switch (period) {
    PlannerPeriod.day => day(d),
    PlannerPeriod.week => weekStart(d, start),
    PlannerPeriod.month => monthStart(d),
    PlannerPeriod.year => yearStart(d),
  };

  /// The start of the period after the one starting at [start].
  static DateTime next(PlannerPeriod period, DateTime start) => step(period, start, 1);

  /// The start of the period [count] periods after (or before, when
  /// negative) the one starting at [start].
  static DateTime step(PlannerPeriod period, DateTime start, int count) => switch (period) {
    PlannerPeriod.day => addDays(start, count),
    PlannerPeriod.week => addDays(start, 7 * count),
    PlannerPeriod.month => addMonths(start, count),
    PlannerPeriod.year => DateTime.utc(start.year + count),
  };

  /// The number of [d]'s week (1–53) for weeks starting on [start]:
  ///
  /// * Monday: ISO 8601 — week 1 holds the year's first Thursday, so a
  ///   week belongs to the year of its Thursday;
  /// * Sunday: the common US rule — week 1 is the week holding 1 January,
  ///   so the last days of December may be in week 1 of the next year.
  static int weekNumber(DateTime d, WeekStart start) =>
      start == WeekStart.monday ? isoWeek(d) : sundayWeek(d);

  /// ISO 8601 week number of [d] (1–53).
  static int isoWeek(DateTime d) {
    final day = PlannerDates.day(d);
    // The week belongs to the year of its Thursday.
    final thursday = addDays(day, DateTime.thursday - day.weekday);
    final firstThursday = DateTime.utc(thursday.year, 1, 1);
    return thursday.difference(firstThursday).inDays ~/ 7 + 1;
  }

  /// US week number of [d] (1–53): weeks run Sunday to Saturday, and
  /// week 1 is the one holding 1 January.
  static int sundayWeek(DateTime d) {
    final sunday = weekStart(d, WeekStart.sunday);
    // A week holding 1 January is week 1 of that (its Saturday's) year.
    final year = addDays(sunday, 6).year;
    final first = weekStart(DateTime.utc(year), WeekStart.sunday);
    return sunday.difference(first).inDays ~/ 7 + 1;
  }

  /// The first days of the weeks overlapping [month] of [year], in order
  /// (four to six of them): the rows of a month calendar.
  static List<DateTime> weeksOfMonth(int year, int month, [WeekStart start = WeekStart.monday]) {
    final last = DateTime.utc(year, month, daysInMonth(year, month));
    return [
      for (var w = weekStart(DateTime.utc(year, month), start); !w.isAfter(last); w = addDays(w, 7))
        w,
    ];
  }

  /// Whether [d] falls on a Saturday or Sunday (shaded on planners).
  static bool isWeekend(DateTime d) => d.weekday >= DateTime.saturday;

  /// The weekdays ([DateTime.weekday]) of a week starting on [start], in
  /// order.
  static List<int> weekdays(WeekStart start) => [
    for (var i = 0; i < 7; i++) (start.weekday - 1 + i) % 7 + 1,
  ];

  /// `2026-10-05`: how dates are stored.
  static String encode(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${_two(d.month)}-${_two(d.day)}';

  /// Parses [encode]'s format strictly; null when malformed.
  static DateTime? decode(String value) {
    final m = RegExp(r'^(\d{4})-(\d{2})-(\d{2})$').firstMatch(value);
    if (m == null) return null;
    final y = int.parse(m[1]!), mo = int.parse(m[2]!), d = int.parse(m[3]!);
    if (mo < 1 || mo > 12 || d < 1 || d > daysInMonth(y, mo)) return null;
    return DateTime.utc(y, mo, d);
  }

  static String _two(int n) => n.toString().padLeft(2, '0');
}
