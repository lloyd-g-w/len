import 'dart:math' as math;
import 'dart:ui';

import '../paper_pattern.dart';
import 'paper.dart';
import 'paper_style.dart';
import 'pattern_builder.dart';
import 'planner_calendar.dart';
import 'planner_dates.dart';

/// Date-aware planner pages, printed in the paper's language with weeks
/// from its week start. Each page prints its dates and links to the pages
/// of the periods around it (in the same calendar): month → weeks, days
/// and year, week → days and month, day → week and month. Without a date
/// the layout is drawn blank.
extension PlannerPatterns on PatternBuilder {
  /// A day: date header, hourly schedule, priorities, to-dos and notes.
  void daily(Rect page, Paper paper) {
    final date = paper.date;
    final labels = paper.labels, words = labels.words;
    final c = content(page);
    final header = c.top + 3.2 * s;
    if (date != null) {
      final weekStart = _weekStart(paper);
      label('${date.day}', Rect.fromLTWH(c.left, c.top, 80, 64), size: 46, bold: true);
      final x = c.left + (date.day >= 10 ? 74.0 : 44.0);
      final width = c.right - 130 - x;
      label(
        labels.weekdayName(date.weekday),
        Rect.fromLTWH(x, c.top + 8, width, 24),
        size: 19,
        bold: true,
      );
      final month = Rect.fromLTWH(x, c.top + 34, width, 22);
      label(labels.monthYear(date), month, size: 13.5, muted: true);
      link(month, paper.sibling(PaperStyle.monthlyCalendar, date));
      final week = Rect.fromLTWH(c.right - 120, c.top + 8, 120, 24);
      label(
        labels.week(PlannerDates.weekNumber(date, weekStart)),
        week,
        size: 13,
        align: LabelAlign.end,
        muted: true,
      );
      link(week, paper.sibling(PaperStyle.weeklyPlanner, date));
    }
    h(header, c.left, c.right, PatternWeight.heavy);

    void title(String text, double x, double y, {double width = 300}) =>
        _heading(labels.upper(text), x, y, width);
    final top = header + 1.6 * s;
    final split = c.left + c.width * 0.42;
    // Schedule: one line per hour, 7:00 to 21:00.
    title(words.schedule, c.left, top - 0.4 * s);
    const first = 7, hours = 15;
    final pitch = math.max(s, (c.bottom - top - 0.4 * s) / hours);
    for (var i = 0; i < hours; i++) {
      final y = top + 0.4 * s + i * pitch;
      if (y > c.bottom) break;
      h(y, c.left, split - 12);
      label('${first + i}:00', Rect.fromLTWH(c.left, y + 2, 48, 14), size: 9.5, muted: true);
    }
    v(split + 12, header, c.bottom, PatternWeight.heavy);

    // Priorities, to-dos and notes.
    final x0 = split + 32;
    var y = top - 0.4 * s;
    for (final (name, count) in [(words.priorities, 3), (words.toDo, 7)]) {
      title(name, x0, y, width: c.right - x0);
      final box = s * 0.45;
      for (final ly in rules(y + s * 0.9, y + (count - 0.1) * s, x0 + box + s * 0.4, c.right)) {
        checkbox(x0, ly, box);
      }
      y += (count + 1.6) * s;
    }
    title(words.notes, x0, y, width: c.right - x0);
    rules(y + s * 0.9, c.bottom, x0, c.right);
  }

  /// A week (from the calendar's week start): a box per day, plus one for
  /// notes.
  void weekly(Rect page, Paper paper) {
    final first = paper.date;
    final weekStart = _weekStart(paper);
    final labels = paper.labels;
    final c = content(page);
    final header = c.top + 2.8 * s;
    if (first != null) {
      final title = Rect.fromLTWH(c.left, c.top, 220, 34);
      label(labels.week(PlannerDates.weekNumber(first, weekStart)), title, size: 24, bold: true);
      label(
        labels.weekRange(first),
        Rect.fromLTWH(c.left, c.top + 36, c.width * 0.75, 20),
        size: 13,
        muted: true,
      );
      final month = Rect.fromLTWH(c.right - 160, c.top + 6, 160, 24);
      // Its month or months ("Dec – Jan"); links to the month most of the
      // week is in (that of its middle day).
      final middle = PlannerDates.addDays(first, 3);
      label(labels.weekMonths(first), month, size: 13, align: LabelAlign.end, muted: true);
      link(month, paper.sibling(PaperStyle.monthlyCalendar, middle));
    }
    h(header, c.left, c.right, PatternWeight.heavy);

    final landscape = page.width > page.height;
    final cols = landscape ? 4 : 2, rows = landscape ? 2 : 4;
    const gap = 14.0;
    final grid = Rect.fromLTRB(c.left, header + s * 0.8, c.right, c.bottom);
    final cw = (grid.width - gap * (cols - 1)) / cols;
    final ch = (grid.height - gap * (rows - 1)) / rows;
    final weekdays = PlannerDates.weekdays(weekStart);
    for (var i = 0; i < cols * rows; i++) {
      final cell = Rect.fromLTWH(
        grid.left + (i % cols) * (cw + gap),
        grid.top + (i ~/ cols) * (ch + gap),
        cw,
        ch,
      );
      final strip = Rect.fromLTWH(cell.left, cell.top, cell.width, 1.3 * s);
      box(cell);
      h(strip.bottom, cell.left, cell.right, PatternWeight.heavy);
      final inner = strip.deflate(8);
      if (i < 7) {
        final weekday = weekdays[i];
        if (weekday >= DateTime.saturday) fill(strip, 0.35); // The weekend.
        label(labels.upper(labels.weekdayName(weekday)), inner, size: _headingSize, bold: true);
        if (first != null) {
          final day = PlannerDates.addDays(first, i);
          label('${day.day}', inner, size: 15, bold: true, align: LabelAlign.end);
          link(strip, paper.sibling(PaperStyle.dailyPlanner, day));
        }
      } else {
        label(labels.upper(labels.words.notes), inner, size: _headingSize, bold: true);
      }
      rules(strip.bottom + s, cell.bottom - s * 0.3, cell.left + 8, cell.right - 8);
    }
  }

  /// A month calendar: weekday heads, week numbers and one cell per day.
  void monthly(Rect page, Paper paper) {
    final first = paper.date;
    final weekStart = _weekStart(paper);
    final labels = paper.labels;
    final c = content(page);
    final header = c.top + 2.6 * s;
    final weeks = first == null
        ? [
            for (var i = 0; i < 5; i++)
              PlannerDates.addDays(PlannerDates.weekStart(DateTime.utc(2001), weekStart), 7 * i),
          ] // Undated: 5 rows.
        : PlannerDates.weeksOfMonth(first.year, first.month, weekStart);
    if (first != null) {
      label(
        labels.monthName(first.month),
        Rect.fromLTWH(c.left, c.top, c.width * 0.7, 46),
        size: 32,
        bold: true,
      );
      final year = Rect.fromLTWH(c.right - 140, c.top, 140, 46);
      label('${first.year}', year, size: 24, align: LabelAlign.end, muted: true);
      link(year, paper.sibling(PaperStyle.yearlyOverview, first));
    }
    const weekColumn = 30.0;
    final grid = Rect.fromLTRB(c.left + weekColumn, header + 1.2 * s, c.right, c.bottom);
    final cw = grid.width / 7, rh = grid.height / weeks.length;
    final weekdays = PlannerDates.weekdays(weekStart);
    for (var d = 0; d < 7; d++) {
      label(
        labels.weekdayShort(weekdays[d]),
        Rect.fromLTWH(grid.left + d * cw, header, cw, 1.2 * s),
        size: 10.5,
        bold: true,
        align: LabelAlign.center,
        muted: weekdays[d] >= DateTime.saturday,
      );
    }
    box(grid);
    for (var r = 1; r < weeks.length; r++) {
      h(grid.top + r * rh, grid.left, grid.right);
    }
    for (var d = 1; d < 7; d++) {
      v(grid.left + d * cw, grid.top, grid.bottom);
    }
    if (first == null) return;
    for (var r = 0; r < weeks.length; r++) {
      final week = weeks[r];
      final number = Rect.fromLTWH(c.left, grid.top + r * rh, weekColumn - 4, rh);
      label(
        '${PlannerDates.weekNumber(week, weekStart)}',
        Rect.fromLTWH(number.left, number.top + 4, number.width, 16),
        size: 10,
        align: LabelAlign.center,
        muted: true,
      );
      link(number, paper.sibling(PaperStyle.weeklyPlanner, week));
      for (var d = 0; d < 7; d++) {
        final day = PlannerDates.addDays(week, d);
        final cell = Rect.fromLTWH(grid.left + d * cw, grid.top + r * rh, cw, rh);
        final inMonth = day.month == first.month;
        if (!inMonth) fill(cell, 0.3);
        label(
          '${day.day}',
          Rect.fromLTWH(cell.left + 7, cell.top + 5, cell.width - 14, 18),
          size: 13,
          bold: inMonth,
          muted: !inMonth || PlannerDates.isWeekend(day),
        );
        link(cell, paper.sibling(PaperStyle.dailyPlanner, day));
      }
    }
  }

  /// Planner headings are a touch larger than other templates' (they
  /// print in the paper's text colour; small caps read faint otherwise).
  static const double _headingSize = 11.5;

  /// A capitalised heading ([text] already in capitals) ending at [y].
  void _heading(String text, double x, double y, double width) =>
      label(text, Rect.fromLTWH(x, y - 19, width, 17), size: _headingSize, bold: true);

  static WeekStart _weekStart(Paper paper) =>
      (paper.calendar ?? PlannerCalendar.standard).weekStart;
}
