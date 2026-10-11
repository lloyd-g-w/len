import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/paper_pattern.dart';
import 'package:len/ink/render/paper_painter.dart';

void main() {
  group('PaperStyle', () {
    test('stored names parse; unknown ones as blank', () {
      expect(PaperStyle.parse('hexagons-from-the-future'), PaperStyle.blank);
      expect(PaperStyle.parse('wideRuled'), PaperStyle.wideRuled);
      expect(PaperStyle.parse('gridLarge'), PaperStyle.gridLarge);
      expect(PaperColor.parse(null), PaperColor.white);
      expect(PaperColor.parse('ultraviolet'), PaperColor.white);
    });

    test('every style is offered once', () {
      expect(PaperStyle.ordered.toSet(), PaperStyle.values.toSet());
      expect(PaperStyle.ordered.length, PaperStyle.values.length);
    });

    test('page formats and orientation', () {
      const t = PageTemplate(format: PageFormat.letter, orientation: PageOrientation.landscape);
      expect(t.size, const Size(1056, 816));
      final match = PageFormat.match(const Size(559, 794))!;
      expect(match.format, PageFormat.a5);
      expect(match.orientation, PageOrientation.portrait);
      expect(PageFormat.match(const Size(612, 792)), isNull); // A PDF page.
    });
  });

  group('PaperPattern', () {
    const page = Rect.fromLTWH(0, 0, 794, 1123);

    test('blank has no geometry', () {
      expect(PaperPattern.of(PaperStyle.blank, page, page: page).isEmpty, isTrue);
    });

    test('ruled pages leave a header and draw a margin', () {
      final p = PaperPattern.of(PaperStyle.collegeRuled, page, page: page);
      final rules = p.lines.where((l) => l.weight == PatternWeight.normal);
      expect(rules.map((l) => l.a.dy).reduce((a, b) => a < b ? a : b), greaterThanOrEqualTo(81));
      expect(p.lines.where((l) => l.weight == PatternWeight.margin), hasLength(1));
      // Narrower ruling, more lines.
      final narrow = PaperPattern.of(PaperStyle.narrowRuled, page, page: page).lines.length;
      expect(narrow, greaterThan(p.lines.length));
    });

    test('lines are clipped to the requested area', () {
      const area = Rect.fromLTWH(100, 100, 50, 50);
      for (final style in PaperStyle.values) {
        final p = PaperPattern.of(style, area, page: page);
        for (final l in p.lines) {
          for (final o in [l.a, l.b]) {
            expect(area.inflate(1e-6).contains(o), isTrue, reason: '$style $o');
          }
        }
        for (final d in p.dots) {
          expect(area.inflate(1e-6).contains(d), isTrue);
        }
      }
    });

    test('cornell has heavy section lines; on a canvas it is ruled', () {
      final p = PaperPattern.of(PaperStyle.cornell, page, page: page);
      expect(p.lines.where((l) => l.weight == PatternWeight.heavy), hasLength(3));
      final canvas = PaperPattern.of(PaperStyle.cornell, page);
      expect(canvas.lines.where((l) => l.weight == PatternWeight.heavy), isEmpty);
    });

    test('music staves come in groups of five', () {
      final p = PaperPattern.of(PaperStyle.music, page, page: page);
      expect(p.lines.length % 5, 0);
      expect(p.lines, isNotEmpty);
    });

    test('infinite canvas tiles around negative coordinates', () {
      const area = Rect.fromLTWH(-5000, -5000, 300, 300);
      expect(PaperPattern.of(PaperStyle.isometric, area).lines, isNotEmpty);
      expect(PaperPattern.of(PaperStyle.dotted, area).dots, isNotEmpty);
    });
  });

  testWidgets('templates at real scale (golden)', (tester) async {
    tester.view.physicalSize = const Size(1180, 670);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ColoredBox(
        color: const Color(0xFFE9EAEE),
        child: CustomPaint(painter: _Sheets()),
      ),
    );
    await expectLater(find.byType(CustomPaint), matchesGoldenFile('goldens/paper_templates.png'));
  });
}

class _Sheets extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    const scale = 0.4;
    final page = Offset.zero & PageFormat.a5.sizeFor(PageOrientation.portrait);
    var i = 0;
    for (final style in PaperStyle.ordered) {
      final color = PaperColor.values[i % PaperColor.values.length];
      canvas
        ..save()
        ..translate(10 + (i % 5) * 235.0, 10 + (i ~/ 5) * 330.0)
        ..scale(scale);
      PaperRenderer.paintSheet(canvas, page, color, scale: scale);
      PaperRenderer.paintPattern(canvas, style, color, page, page: page, scale: scale);
      canvas.restore();
      i++;
    }
  }

  @override
  bool shouldRepaint(_Sheets old) => false;
}
