import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/paper_pattern.dart';
import 'package:len/ink/render/paper_painter.dart';

import 'content_golden_test.dart' show loadFonts;

DateTime d(int y, int m, int day) => DateTime.utc(y, m, day);

const _page = Rect.fromLTWH(0, 0, 794, 1123);
const _landscape = Rect.fromLTWH(0, 0, 1123, 794);

List<PatternLink> _links(Paper paper, [Rect page = _page]) =>
    PaperPattern.of(paper, page, page: page).links;

/// The links between planner levels: year ⇄ month ⇄ week ⇄ day.
void main() {
  final year = Paper.planner(PaperStyle.yearlyOverview, d(2026, 1, 1));

  test('the year overview links its month titles to months and its days to days', () {
    for (final page in [_page, _landscape]) {
      final links = _links(year, page);
      final months = [
        for (final l in links)
          if (l.target.style == PaperStyle.monthlyCalendar) l.target.date!,
      ];
      expect(months, [for (var m = 1; m <= 12; m++) d(2026, m, 1)]);
      final days = links.where((l) => l.target.style == PaperStyle.dailyPlanner);
      expect(days, hasLength(365));
      expect(days.map((l) => l.target.date).toSet(), hasLength(365));
      for (final l in links) {
        expect(page.contains(l.rect.center), isTrue);
      }
    }
  });

  test('a month links up to its year overview from the year label', () {
    final october = Paper.planner(PaperStyle.monthlyCalendar, d(2026, 10, 1));
    final up = _links(october).where((l) => l.target.style == PaperStyle.yearlyOverview).single;
    expect(up.target, year);
    // In the header, at the right: where "2026" is printed.
    final label = PaperPattern.of(
      october,
      _page,
      page: _page,
    ).labels.firstWhere((l) => l.text == '2026');
    expect(up.rect.overlaps(label.box), isTrue);
    expect(up.rect.center.dx, greaterThan(_page.width / 2));
  });

  test('weeks and days link back to their month', () {
    final week = Paper.planner(PaperStyle.weeklyPlanner, d(2026, 9, 28));
    expect(
      _links(week).where((l) => l.target.style == PaperStyle.monthlyCalendar).single.target,
      Paper.planner(PaperStyle.monthlyCalendar, d(2026, 10, 1)),
    );
    final day = Paper.planner(PaperStyle.dailyPlanner, d(2026, 9, 30));
    expect(
      _links(day).where((l) => l.target.style == PaperStyle.monthlyCalendar).single.target,
      Paper.planner(PaperStyle.monthlyCalendar, d(2026, 9, 1)),
    );
  });

  test('a linked year with its overview: every link inside the year resolves', () {
    final pages = PlannerPlan(
      start: d(2026, 1, 1),
      months: 12,
      linked: true,
      yearOverview: true,
    ).papersFor(PaperStyle.monthlyCalendar);
    expect(pages.first, year);
    final known = pages.toSet();
    var checked = 0;
    for (final paper in pages) {
      for (final link in _links(paper)) {
        final target = link.target;
        // The first and last weeks reach into December 2025 and January
        // 2027, whose month and year pages are not part of this planner
        // ("Add page" offers them).
        final outside = target.date!.year != 2026;
        if (outside && target.style != PaperStyle.dailyPlanner) continue;
        expect(known, contains(target), reason: '$paper → $target');
        checked++;
      }
    }
    expect(checked, greaterThan(365 * 2));
  });

  testWidgets('month header: the year label links to the overview (golden)', (tester) async {
    await tester.runAsync(loadFonts);
    tester.view.physicalSize = const Size(794, 240);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ColoredBox(
        color: const Color(0xFFE9EAEE),
        child: CustomPaint(painter: _MonthHeader(), size: Size.infinite),
      ),
    );
    await expectLater(
      find.byType(CustomPaint),
      matchesGoldenFile('goldens/planner_month_header.png'),
    );
  });
}

/// The top of an October 2026 month page with its link areas outlined:
/// the year link in red, the others (weeks, days) in blue.
class _MonthHeader extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paper = Paper.planner(PaperStyle.monthlyCalendar, d(2026, 10, 1));
    canvas.clipRect(Offset.zero & size);
    PaperRenderer.paintSheet(canvas, _page, PaperColor.white, scale: 1, shadow: false);
    PaperRenderer.paintPattern(canvas, paper, PaperColor.white, _page, page: _page, scale: 1);
    for (final link in _links(paper)) {
      final up = link.target.style == PaperStyle.yearlyOverview;
      canvas.drawRect(
        link.rect.deflate(1),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = up ? 2 : 1
          ..color = up ? const Color(0xFFD9480F) : const Color(0x801C7ED6),
      );
    }
  }

  @override
  bool shouldRepaint(_MonthHeader old) => false;
}
