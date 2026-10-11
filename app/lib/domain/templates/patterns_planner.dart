import 'dart:math' as math;
import 'dart:ui';

import '../paper_pattern.dart';
import 'paper.dart';
import 'paper_style.dart';
import 'pattern_builder.dart';
import 'planner_dates.dart';

/// Date-aware planner pages. Each page prints its dates and links to the
/// pages of the periods around it: month → weeks and days, week → days and
/// month, day → week and month. Without a date the layout is drawn blank.
extension PlannerPatterns on PatternBuilder {
  /// A day: date header, hourly schedule, priorities, to-dos and notes.
  void daily(Rect page, DateTime? date) {
    final c = content(page);
    final header = c.top + 3.2 * s;
    if (date != null) {
      label('${date.day}', Rect.fromLTWH(c.left, c.top, 80, 64), size: 46, bold: true);
      final x = c.left + (date.day >= 10 ? 74.0 : 44.0);
      label(
        PlannerDates.weekdayNames[date.weekday - 1],
        Rect.fromLTWH(x, c.top + 8, 260, 24),
        size: 19,
        bold: true,
      );
      final month = Rect.fromLTWH(x, c.top + 34, 260, 22);
      label(PlannerDates.monthYear(date), month, size: 13.5, muted: true);
      link(month, Paper.planner(PaperStyle.monthlyCalendar, date));
      final week = Rect.fromLTWH(c.right - 120, c.top + 8, 120, 24);
      label(
        'Week ${PlannerDates.isoWeek(date)}',
        week,
        size: 13,
        align: LabelAlign.end,
        muted: true,
      );
      link(week, Paper.planner(PaperStyle.weeklyPlanner, date));
    }
    h(header, c.left, c.right, PatternWeight.heavy);

    final top = header + 1.6 * s;
    final split = c.left + c.width * 0.42;
    // Schedule: one line per hour, 7:00 to 21:00.
    heading('Schedule', c.left, top - 0.4 * s);
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
    for (final (name, count) in const [('Priorities', 3), ('To do', 7)]) {
      heading(name, x0, y, width: c.right - x0);
      final box = s * 0.45;
      for (final ly in rules(y + s * 0.9, y + (count - 0.1) * s, x0 + box + s * 0.4, c.right)) {
        checkbox(x0, ly, box);
      }
      y += (count + 1.6) * s;
    }
    heading('Notes', x0, y, width: c.right - x0);
    rules(y + s * 0.9, c.bottom, x0, c.right);
  }

  /// A week (from Monday): a box per day, plus one for notes.
  void weekly(Rect page, DateTime? monday) {
    final c = content(page);
    final header = c.top + 2.8 * s;
    if (monday != null) {
      final title = Rect.fromLTWH(c.left, c.top, 220, 34);
      label('Week ${PlannerDates.isoWeek(monday)}', title, size: 24, bold: true);
      label(
        PlannerDates.weekRange(monday),
        Rect.fromLTWH(c.left, c.top + 36, c.width * 0.75, 20),
        size: 13,
        muted: true,
      );
      final month = Rect.fromLTWH(c.right - 160, c.top + 6, 160, 24);
      // The month most of the week is in (that of its Thursday).
      final thursday = PlannerDates.addDays(monday, 3);
      label(
        PlannerDates.monthNames[thursday.month - 1],
        month,
        size: 13,
        align: LabelAlign.end,
        muted: true,
      );
      link(month, Paper.planner(PaperStyle.monthlyCalendar, thursday));
    }
    h(header, c.left, c.right, PatternWeight.heavy);

    final landscape = page.width > page.height;
    final cols = landscape ? 4 : 2, rows = landscape ? 2 : 4;
    const gap = 14.0;
    final grid = Rect.fromLTRB(c.left, header + s * 0.8, c.right, c.bottom);
    final cw = (grid.width - gap * (cols - 1)) / cols;
    final ch = (grid.height - gap * (rows - 1)) / rows;
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
        if (i >= 5) fill(strip, 0.35); // The weekend.
        label(PlannerDates.weekdayNames[i].toUpperCase(), inner, size: 10.5, bold: true);
        if (monday != null) {
          final day = PlannerDates.addDays(monday, i);
          label('${day.day}', inner, size: 15, bold: true, align: LabelAlign.end);
          link(strip, Paper.planner(PaperStyle.dailyPlanner, day));
        }
      } else {
        label('NOTES', inner, size: 10.5, bold: true);
      }
      rules(strip.bottom + s, cell.bottom - s * 0.3, cell.left + 8, cell.right - 8);
    }
  }

  /// A month calendar: weekday heads, week numbers and one cell per day.
  void monthly(Rect page, DateTime? first) {
    final c = content(page);
    final header = c.top + 2.6 * s;
    final weeks = first == null
        ? [for (var i = 0; i < 5; i++) DateTime.utc(2001, 1, 1 + 7 * i)] // Undated: 5 rows.
        : PlannerDates.weeksOfMonth(first.year, first.month);
    if (first != null) {
      label(
        PlannerDates.monthNames[first.month - 1],
        Rect.fromLTWH(c.left, c.top, c.width * 0.7, 46),
        size: 32,
        bold: true,
      );
      label(
        '${first.year}',
        Rect.fromLTWH(c.right - 140, c.top, 140, 46),
        size: 24,
        align: LabelAlign.end,
        muted: true,
      );
    }
    const weekColumn = 30.0;
    final grid = Rect.fromLTRB(c.left + weekColumn, header + 1.2 * s, c.right, c.bottom);
    final cw = grid.width / 7, rh = grid.height / weeks.length;
    for (var d = 0; d < 7; d++) {
      label(
        PlannerDates.weekdayNames[d].substring(0, 3).toUpperCase(),
        Rect.fromLTWH(grid.left + d * cw, header, cw, 1.2 * s),
        size: 10.5,
        bold: true,
        align: LabelAlign.center,
        muted: d >= 5,
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
      final monday = weeks[r];
      final number = Rect.fromLTWH(c.left, grid.top + r * rh, weekColumn - 4, rh);
      label(
        '${PlannerDates.isoWeek(monday)}',
        Rect.fromLTWH(number.left, number.top + 4, number.width, 16),
        size: 10,
        align: LabelAlign.center,
        muted: true,
      );
      link(number, Paper.planner(PaperStyle.weeklyPlanner, monday));
      for (var d = 0; d < 7; d++) {
        final day = PlannerDates.addDays(monday, d);
        final cell = Rect.fromLTWH(grid.left + d * cw, grid.top + r * rh, cw, rh);
        final inMonth = day.month == first.month;
        if (!inMonth) fill(cell, 0.3);
        label(
          '${day.day}',
          Rect.fromLTWH(cell.left + 7, cell.top + 5, cell.width - 14, 18),
          size: 13,
          bold: inMonth,
          muted: !inMonth || d >= 5,
        );
        link(cell, Paper.planner(PaperStyle.dailyPlanner, day));
      }
    }
  }
}
