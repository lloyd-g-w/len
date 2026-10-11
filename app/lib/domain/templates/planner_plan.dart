import 'paper.dart';
import 'paper_style.dart';
import 'planner_calendar.dart';
import 'planner_dates.dart';

/// Which pages to generate for a planner template: [months] months from
/// the month of [start], in [calendar] (week start and language).
class PlannerPlan {
  PlannerPlan({
    required DateTime start,
    this.months = 1,
    this.linked = false,
    this.yearOverview = false,
    this.calendar = PlannerCalendar.standard,
  }) : assert(months >= 1 && months <= maxMonths),
       start = PlannerDates.monthStart(start);

  static const int maxMonths = 12;

  /// The first month (UTC, day 1).
  final DateTime start;

  /// How many months the planner covers.
  final int months;

  /// Monthly calendars only: also add a page per week and per day after
  /// each month, so the calendar's links lead somewhere.
  final bool linked;

  /// Monthly calendars only: put the year overview before the first month
  /// (and before each January).
  final bool yearOverview;

  final PlannerCalendar calendar;

  /// The day after the last day covered.
  DateTime get end => PlannerDates.addMonths(start, months);

  PlannerPlan copyWith({
    DateTime? start,
    int? months,
    bool? linked,
    bool? yearOverview,
    PlannerCalendar? calendar,
  }) => PlannerPlan(
    start: start ?? this.start,
    months: months ?? this.months,
    linked: linked ?? this.linked,
    yearOverview: yearOverview ?? this.yearOverview,
    calendar: calendar ?? this.calendar,
  );

  Paper _paper(PaperStyle style, DateTime date) => Paper.planner(style, date, calendar: calendar);

  /// The pages for planner [style], in notebook order:
  ///
  /// * daily: one page per day of the range;
  /// * weekly: one page per week overlapping the range;
  /// * monthly: one page per month — when [yearOverview], the year
  ///   overview comes first (and before each January); when [linked], each
  ///   month is followed by the weeks starting in it (the first month also
  ///   gets the week holding its 1st), each week by its seven days;
  /// * yearly: one page per year overlapping the range.
  List<Paper> papersFor(PaperStyle style) {
    final period = style.period;
    assert(period != null, '$style is not a planner');
    switch (period) {
      case PlannerPeriod.day:
        return [
          for (var d = start; d.isBefore(end); d = PlannerDates.addDays(d, 1)) _paper(style, d),
        ];
      case PlannerPeriod.week:
        return [for (final w in _weeks()) _paper(style, w)];
      case PlannerPeriod.month:
        return _monthly(style);
      case PlannerPeriod.year:
        final last = PlannerDates.addDays(end, -1).year;
        return [for (var y = start.year; y <= last; y++) _paper(style, DateTime.utc(y))];
      case null:
        return const [];
    }
  }

  /// First days of the weeks overlapping the range.
  Iterable<DateTime> _weeks() sync* {
    for (
      var w = PlannerDates.weekStart(start, calendar.weekStart);
      w.isBefore(end);
      w = PlannerDates.addDays(w, 7)
    ) {
      yield w;
    }
  }

  List<Paper> _monthly(PaperStyle monthly) {
    final result = <Paper>[];
    var nextMonth = 0; // Index of the next month page to emit.
    void emitMonth(DateTime month) {
      if (yearOverview && (nextMonth == 0 || month.month == DateTime.january)) {
        result.add(_paper(PaperStyle.yearlyOverview, month));
      }
      result.add(_paper(monthly, month));
      nextMonth++;
    }

    if (!linked) {
      while (nextMonth < months) {
        emitMonth(PlannerDates.addMonths(start, nextMonth));
      }
      return result;
    }

    void emitMonthsUpTo(DateTime weekStart) {
      while (nextMonth < months) {
        final month = PlannerDates.addMonths(start, nextMonth);
        if (nextMonth > 0 && month.isAfter(weekStart)) return;
        emitMonth(month);
      }
    }

    for (final week in _weeks()) {
      emitMonthsUpTo(week);
      result.add(_paper(PaperStyle.weeklyPlanner, week));
      for (var i = 0; i < 7; i++) {
        result.add(_paper(PaperStyle.dailyPlanner, PlannerDates.addDays(week, i)));
      }
    }
    emitMonthsUpTo(end);
    return result;
  }
}
