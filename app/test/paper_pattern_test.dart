import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/paper_pattern.dart';
import 'package:len/features/documents/templates/user_templates.dart';
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

    test('every built-in style is offered, the image style is not', () {
      expect(PaperStyle.builtIn, hasLength(PaperStyle.values.length - 1));
      expect(PaperStyle.builtIn, isNot(contains(PaperStyle.image)));
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
      expect(PaperPattern.of(Paper(PaperStyle.blank), page, page: page).isEmpty, isTrue);
    });

    test('ruled pages leave a header and draw a margin', () {
      final p = PaperPattern.of(Paper(PaperStyle.collegeRuled), page, page: page);
      final rules = p.lines.where((l) => l.weight == PatternWeight.normal);
      expect(rules.map((l) => l.a.dy).reduce((a, b) => a < b ? a : b), greaterThanOrEqualTo(81));
      expect(p.lines.where((l) => l.weight == PatternWeight.margin), hasLength(1));
      // Narrower ruling, more lines.
      final narrow = PaperPattern.of(Paper(PaperStyle.narrowRuled), page, page: page).lines.length;
      expect(narrow, greaterThan(p.lines.length));
    });

    test('lines are clipped to the requested area', () {
      const area = Rect.fromLTWH(100, 100, 50, 50);
      for (final style in PaperStyle.values) {
        final p = PaperPattern.of(Paper(style), area, page: page);
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
      final p = PaperPattern.of(Paper(PaperStyle.cornell), page, page: page);
      expect(p.lines.where((l) => l.weight == PatternWeight.heavy), hasLength(3));
      final canvas = PaperPattern.of(Paper(PaperStyle.cornell), page);
      expect(canvas.lines.where((l) => l.weight == PatternWeight.heavy), isEmpty);
    });

    test('music staves come in groups of five', () {
      final p = PaperPattern.of(Paper(PaperStyle.music), page, page: page);
      expect(p.lines.length % 5, 0);
      expect(p.lines, isNotEmpty);
    });

    test('infinite canvas tiles around negative coordinates', () {
      const area = Rect.fromLTWH(-5000, -5000, 300, 300);
      expect(PaperPattern.of(Paper(PaperStyle.isometric), area).lines, isNotEmpty);
      expect(PaperPattern.of(Paper(PaperStyle.dotted), area).dots, isNotEmpty);
    });
  });

  test('image templates are stretched over the page once decoded', () async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder)
        .drawRect(const Rect.fromLTWH(0, 0, 4, 4), Paint()..color = const Color(0xFF2B8A3E));
    final image = await recorder.endRecording().toImage(4, 4);
    const page = Rect.fromLTWH(0, 0, 20, 10);
    Future<Color> centre(ui.Image? decoded) async {
      final r = ui.PictureRecorder();
      final canvas = Canvas(r);
      PaperRenderer.paintSheet(canvas, page, PaperColor.white, scale: 1, shadow: false);
      PaperRenderer.paintPattern(
        canvas,
        Paper.image('a' * 64),
        PaperColor.white,
        page,
        page: page,
        scale: 1,
        images: (blob, width) => blob == 'a' * 64 ? decoded : null,
      );
      final out = await r.endRecording().toImage(20, 10);
      final bytes = (await out.toByteData(format: ui.ImageByteFormat.rawRgba))!;
      final i = (5 * 20 + 15) * 4;
      return Color.fromARGB(255, bytes.getUint8(i), bytes.getUint8(i + 1), bytes.getUint8(i + 2));
    }

    expect(await centre(image), const Color(0xFF2B8A3E));
    expect(await centre(null), PaperColor.white.paper, reason: 'plain paper while decoding');
  });

  test('imported templates get a page size from their aspect', () {
    expect(UserTemplates.pageSizeFor(1000, 1414), Size(794, 794 * 1.414));
    expect(UserTemplates.pageSizeFor(1600, 900), Size(794 * 16 / 9, 794));
  });

  testWidgets('templates at real scale (golden)', (tester) async {
    tester.view.physicalSize = const Size(1180, 1330);
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
    for (final style in PaperStyle.builtIn) {
      final color = PaperColor.presets[i % PaperColor.presets.length];
      canvas
        ..save()
        ..translate(10 + (i % 5) * 235.0, 10 + (i ~/ 5) * 330.0)
        ..scale(scale);
      PaperRenderer.paintSheet(canvas, page, color, scale: scale);
      final paper = Paper.defaultFor(style, today: DateTime.utc(2026, 10, 11))!;
      PaperRenderer.paintPattern(canvas, paper, color, page, page: page, scale: scale);
      canvas.restore();
      i++;
    }
  }

  @override
  bool shouldRepaint(_Sheets old) => false;
}
