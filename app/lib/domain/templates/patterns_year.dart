import 'dart:math' as math;
import 'dart:ui';

import '../paper_pattern.dart';
import 'paper.dart';
import 'paper_style.dart';
import 'pattern_builder.dart';
import 'planner_calendar.dart';
import 'planner_dates.dart';

/// The year overview planner page.
extension YearPatterns on PatternBuilder {
  /// The twelve months of a year as small calendars (3 × 4 on portrait
  /// pages, 4 × 3 on landscape ones), weeks from the calendar's week
  /// start. Month titles link to the monthly calendars, days to the daily
  /// pages. Undated: month names and weekday heads only.
  void yearly(Rect page, Paper paper) {
    final first = paper.date;
    final weekStart = (paper.calendar ?? PlannerCalendar.standard).weekStart;
    final labels = paper.labels;
    final c = content(page);
    final header = c.top + 2.6 * s;
    if (first != null) {
      label('${first.year}', Rect.fromLTWH(c.left, c.top, c.width * 0.6, 46), size: 32, bold: true);
    }
    h(header, c.left, c.right, PatternWeight.heavy);

    final landscape = page.width > page.height;
    final cols = landscape ? 4 : 3, rows = landscape ? 3 : 4;
    final gapX = 0.9 * s, gapY = 0.6 * s;
    final grid = Rect.fromLTRB(c.left, header + 0.8 * s, c.right, c.bottom);
    final cw = (grid.width - gapX * (cols - 1)) / cols;
    final ch = (grid.height - gapY * (rows - 1)) / rows;
    final titleHeight = math.min(30.0, ch * 0.2);
    final rowHeight = (ch - titleHeight) / 7; // Weekday heads + six weeks.
    final dayWidth = cw / 7;
    final daySize = math.min(11.0, rowHeight * 0.55);
    final weekdays = PlannerDates.weekdays(weekStart);
    for (var m = 0; m < 12; m++) {
      final cell = Rect.fromLTWH(
        grid.left + (m % cols) * (cw + gapX),
        grid.top + (m ~/ cols) * (ch + gapY),
        cw,
        ch,
      );
      final title = Rect.fromLTWH(cell.left, cell.top, cw, titleHeight);
      label(
        labels.monthName(m + 1),
        title.deflate(2),
        size: math.min(15.0, titleHeight * 0.55),
        bold: true,
      );
      h(title.bottom, cell.left, cell.right);
      for (var d = 0; d < 7; d++) {
        label(
          labels.weekdayNarrow(weekdays[d]),
          Rect.fromLTWH(cell.left + d * dayWidth, title.bottom, dayWidth, rowHeight),
          size: daySize * 0.85,
          bold: true,
          align: LabelAlign.center,
          muted: weekdays[d] >= DateTime.saturday,
        );
      }
      if (first == null) continue;
      final month = DateTime.utc(first.year, m + 1);
      link(title, paper.sibling(PaperStyle.monthlyCalendar, month));
      final weeks = PlannerDates.weeksOfMonth(month.year, month.month, weekStart);
      for (var r = 0; r < weeks.length; r++) {
        for (var d = 0; d < 7; d++) {
          final day = PlannerDates.addDays(weeks[r], d);
          if (day.month != month.month) continue;
          final box = Rect.fromLTWH(
            cell.left + d * dayWidth,
            title.bottom + (r + 1) * rowHeight,
            dayWidth,
            rowHeight,
          );
          label(
            '${day.day}',
            box,
            size: daySize,
            align: LabelAlign.center,
            muted: PlannerDates.isWeekend(day),
          );
          link(box, paper.sibling(PaperStyle.dailyPlanner, day));
        }
      }
    }
  }
}
