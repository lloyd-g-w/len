import 'paper_style.dart';

/// Calendar arithmetic for planner templates.
///
/// Dates are UTC midnights (no time zones or daylight saving to trip over);
/// weeks start on Monday and are numbered as in ISO 8601.
abstract final class PlannerDates {
  static const List<String> monthNames = [
    'January',
    'February',
    'March',
    'April',
    'May',
    'June',
    'July',
    'August',
    'September',
    'October',
    'November',
    'December',
  ];

  static const List<String> weekdayNames = [
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
    'Sunday',
  ];

  /// The calendar day of [d] (its local date) as a UTC midnight.
  static DateTime day(DateTime d) => DateTime.utc(d.year, d.month, d.day);

  /// The Monday of [d]'s week.
  static DateTime weekStart(DateTime d) {
    final day = PlannerDates.day(d);
    return day.subtract(Duration(days: day.weekday - DateTime.monday));
  }

  static DateTime monthStart(DateTime d) => DateTime.utc(d.year, d.month);

  /// Days in [month] (1–12) of [year], leap years included.
  static int daysInMonth(int year, int month) => DateTime.utc(year, month + 1, 0).day;

  /// [d] moved by [days] calendar days.
  static DateTime addDays(DateTime d, int days) => DateTime.utc(d.year, d.month, d.day + days);

  /// [d] moved by [months] (to the first of that month).
  static DateTime addMonths(DateTime d, int months) => DateTime.utc(d.year, d.month + months);

  /// The first day of the period of [period] containing [d].
  static DateTime periodStart(PlannerPeriod period, DateTime d) => switch (period) {
    PlannerPeriod.day => day(d),
    PlannerPeriod.week => weekStart(d),
    PlannerPeriod.month => monthStart(d),
  };

  /// The start of the period after the one starting at [start].
  static DateTime next(PlannerPeriod period, DateTime start) => switch (period) {
    PlannerPeriod.day => addDays(start, 1),
    PlannerPeriod.week => addDays(start, 7),
    PlannerPeriod.month => addMonths(start, 1),
  };

  /// ISO 8601 week number of [d] (1–53).
  static int isoWeek(DateTime d) {
    final day = PlannerDates.day(d);
    // The week belongs to the year of its Thursday.
    final thursday = addDays(day, DateTime.thursday - day.weekday);
    final firstThursday = DateTime.utc(thursday.year, 1, 1);
    return thursday.difference(firstThursday).inDays ~/ 7 + 1;
  }

  /// The Mondays of the weeks overlapping [month] of [year], in order
  /// (four to six of them): the rows of a month calendar.
  static List<DateTime> weeksOfMonth(int year, int month) {
    final last = DateTime.utc(year, month, daysInMonth(year, month));
    return [
      for (var w = weekStart(DateTime.utc(year, month)); !w.isAfter(last); w = addDays(w, 7)) w,
    ];
  }

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

  /// `5 October 2026`.
  static String longDate(DateTime d) => '${d.day} ${monthNames[d.month - 1]} ${d.year}';

  /// `October 2026`.
  static String monthYear(DateTime d) => '${monthNames[d.month - 1]} ${d.year}';

  /// `5 – 11 October 2026`, `28 September – 4 October 2026`, across years
  /// `29 December 2025 – 4 January 2026`.
  static String weekRange(DateTime monday) {
    final sunday = addDays(monday, 6);
    final end = longDate(sunday);
    if (monday.year != sunday.year) return '${longDate(monday)} – $end';
    if (monday.month != sunday.month) {
      return '${monday.day} ${monthNames[monday.month - 1]} – $end';
    }
    return '${monday.day} – $end';
  }

  /// A short label of the period starting at [start], e.g. `Mon 5 Oct`,
  /// `Week 41, 2026`, `October 2026`.
  static String describe(PlannerPeriod period, DateTime start) => switch (period) {
    PlannerPeriod.day =>
      '${weekdayNames[start.weekday - 1].substring(0, 3)} ${start.day} '
          '${monthNames[start.month - 1].substring(0, 3)} ${start.year}',
    PlannerPeriod.week => 'Week ${isoWeek(start)} · ${weekRange(start)}',
    PlannerPeriod.month => monthYear(start),
  };

  static String _two(int n) => n.toString().padLeft(2, '0');
}
