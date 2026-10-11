import 'paper.dart';
import 'paper_style.dart';
import 'planner_dates.dart';

/// Which pages to generate for a planner template: [months] months from
/// the month of [start].
class PlannerPlan {
  PlannerPlan({required DateTime start, this.months = 1, this.linked = false})
    : assert(months >= 1 && months <= maxMonths),
      start = PlannerDates.monthStart(start);

  static const int maxMonths = 12;

  /// The first month (UTC, day 1).
  final DateTime start;

  /// How many months the planner covers.
  final int months;

  /// Monthly calendars only: also add a page per week and per day after
  /// each month, so the calendar's links lead somewhere.
  final bool linked;

  /// The day after the last day covered.
  DateTime get end => PlannerDates.addMonths(start, months);

  PlannerPlan copyWith({DateTime? start, int? months, bool? linked}) => PlannerPlan(
    start: start ?? this.start,
    months: months ?? this.months,
    linked: linked ?? this.linked,
  );

  /// The pages for planner [style], in notebook order:
  ///
  /// * daily: one page per day of the range;
  /// * weekly: one page per week overlapping the range;
  /// * monthly: one page per month — when [linked], each followed by the
  ///   weeks starting in it (the first month also gets the week holding its
  ///   1st), each week followed by its seven days.
  List<Paper> papersFor(PaperStyle style) {
    final period = style.period;
    assert(period != null, '$style is not a planner');
    switch (period) {
      case PlannerPeriod.day:
        return [
          for (var d = start; d.isBefore(end); d = PlannerDates.addDays(d, 1))
            Paper.planner(style, d),
        ];
      case PlannerPeriod.week:
        return [for (final w in _weeks()) Paper.planner(style, w)];
      case PlannerPeriod.month:
        if (!linked) {
          return [
            for (var m = 0; m < months; m++) Paper.planner(style, PlannerDates.addMonths(start, m)),
          ];
        }
        return _linked(style);
      case null:
        return const [];
    }
  }

  /// Mondays of the weeks overlapping the range.
  Iterable<DateTime> _weeks() sync* {
    for (var w = PlannerDates.weekStart(start); w.isBefore(end); w = PlannerDates.addDays(w, 7)) {
      yield w;
    }
  }

  List<Paper> _linked(PaperStyle monthly) {
    final result = <Paper>[];
    var nextMonth = 0; // Index of the next month page to emit.
    void emitMonthsUpTo(DateTime monday) {
      while (nextMonth < months) {
        final month = PlannerDates.addMonths(start, nextMonth);
        if (nextMonth > 0 && month.isAfter(monday)) return;
        result.add(Paper.planner(monthly, month));
        nextMonth++;
      }
    }

    for (final monday in _weeks()) {
      emitMonthsUpTo(monday);
      result.add(Paper.planner(PaperStyle.weeklyPlanner, monday));
      for (var i = 0; i < 7; i++) {
        result.add(Paper.planner(PaperStyle.dailyPlanner, PlannerDates.addDays(monday, i)));
      }
    }
    emitMonthsUpTo(end);
    return result;
  }
}
