import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/paper_pattern.dart';
import 'package:len/features/documents/templates/paper_options.dart';
import 'package:len/ink/render/paper_painter.dart';
import 'package:len/ui/app_theme.dart';

import 'content_golden_test.dart' show loadFonts;

const _page = Rect.fromLTWH(0, 0, 559, 794); // A5

/// Pages with customised looks, side by side.
const _samples = [
  (Paper(PaperStyle.dotted), PaperColor.white),
  (
    Paper(PaperStyle.dotted, look: PaperLook(spacing: 5, dotSize: 2, header: true)),
    PaperColor.cream,
  ),
  (
    Paper(
      PaperStyle.collegeRuled,
      look: PaperLook(patternColor: 0xFF8FB3E8, lineWeight: 1.5, margin: false, header: true),
    ),
    PaperColor.white,
  ),
  (Paper(PaperStyle.gridSmall, look: PaperLook(spacing: 10, patternOpacity: 0.5)), PaperColor.dark),
];

void main() {
  group('PaperLook', () {
    test('round-trips and validates its JSON', () {
      const look = PaperLook(spacing: 6.5, lineWeight: 2, patternColor: 0xFF112233, header: true);
      expect(PaperLook.fromJson(look.toJson()), look);
      expect(PaperLook.fromJson({...look.toJson()}..remove('margin')), isNull);
      expect(PaperLook.fromJson({...look.toJson(), 'spacing': '6'}), isNull);
      expect(PaperLook.fromJson({...look.toJson(), 'lineWeight': 99})!.lineWeight, 3);
    });

    test('spacing sets the pitch of adjustable templates only', () {
      const look = PaperLook(spacing: 10);
      expect(const Paper(PaperStyle.dotted, look: look).pitch, closeTo(37.8, 0.01));
      expect(const Paper(PaperStyle.graph, look: look).pitch, PaperStyle.graph.spacing);
      expect(const Paper(PaperStyle.dotted).pitch, PaperStyle.dotted.spacing);
    });

    test('the header rules off the top; the pattern starts below it', () {
      const paper = Paper(PaperStyle.gridLarge, look: PaperLook(header: true));
      final pattern = PaperPattern.of(paper, _page, page: _page);
      final header = _page.top + _page.height * 0.09;
      final heavy = pattern.lines.where((l) => l.weight == PatternWeight.heavy);
      expect(heavy.single.a.dy, closeTo(header, 1e-6));
      expect(pattern.lines.every((l) => l.a.dy >= header - 1e-6), isTrue);
      // Blank paper gets just the header line.
      final blank = PaperPattern.of(
        const Paper(PaperStyle.blank, look: PaperLook(header: true)),
        _page,
        page: _page,
      );
      expect(blank.lines, hasLength(1));
    });

    test('the margin line can be turned off; dots are centred on the page', () {
      bool hasMargin(PaperLook look) => PaperPattern.of(
        Paper(PaperStyle.wideRuled, look: look),
        _page,
        page: _page,
      ).lines.any((l) => l.weight == PatternWeight.margin);
      expect(hasMargin(PaperLook.standard), isTrue);
      expect(hasMargin(const PaperLook(margin: false)), isFalse);
      final dots = PaperPattern.of(const Paper(PaperStyle.dotted), _page, page: _page).dots;
      final xs = dots.map((d) => d.dx);
      final left = xs.reduce((a, b) => a < b ? a : b), right = xs.reduce((a, b) => a > b ? a : b);
      expect(left, closeTo(_page.right - right, 1e-6));
      expect(left, greaterThan(0));
    });

    test('custom paper colours derive their pattern and text colours', () {
      final mint = PaperColor.custom(0xFFDFF5E8);
      expect(mint.name, '#DFF5E8');
      expect(mint.isDark, isFalse);
      expect(PaperColor.tryParse('#DFF5E8'), mint);
      expect(PaperColor.custom(PaperColor.cream.paper.toARGB32()), PaperColor.cream);
      final navy = PaperColor.custom(0xFF14213D);
      expect(navy.isDark, isTrue);
      expect(navy.pattern.computeLuminance(), greaterThan(navy.paper.computeLuminance()));
      expect(PaperColor.tryParse('#14213d'), isNull, reason: 'upper case only');
    });
  });

  testWidgets('customised paper and the Paper options (golden)', (tester) async {
    await loadFonts();
    tester.view
      ..physicalSize = const Size(1240, 900)
      ..devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var template = PageTemplate(
      paper: _samples[1].$1,
      color: _samples[1].$2,
      format: PageFormat.a5,
    );
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light(),
        home: Material(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(width: 900, height: 900, child: CustomPaint(painter: _Pages())),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: StatefulBuilder(
                    builder: (context, setState) => PaperOptions(
                      template: template,
                      onChanged: (t) => setState(() => template = t),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    await expectLater(find.byType(MaterialApp), matchesGoldenFile('goldens/paper_looks.png'));
  });
}

class _Pages extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFE9EAEE));
    const scale = 0.5;
    for (final (i, (paper, color)) in _samples.indexed) {
      canvas
        ..save()
        ..translate(20 + (i % 2) * 300.0, 20 + (i ~/ 2) * 430.0)
        ..scale(scale);
      PaperRenderer.paintSheet(canvas, _page, color, scale: scale);
      PaperRenderer.paintPattern(canvas, paper, color, _page, page: _page, scale: scale);
      canvas.restore();
    }
    // Actual size crop of the second sample.
    canvas
      ..save()
      ..translate(620, 20)
      ..clipRect(const Rect.fromLTWH(0, 0, 260, 400));
    PaperRenderer.paintSheet(canvas, _page, _samples[1].$2, scale: 1);
    PaperRenderer.paintPattern(
      canvas,
      _samples[1].$1,
      _samples[1].$2,
      _page,
      page: _page,
      scale: 1,
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(_Pages old) => false;
}
