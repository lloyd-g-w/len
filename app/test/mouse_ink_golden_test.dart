// Mouse handwriting as the owner wrote it ("x∈ℝ → f(x)dx", a thick red
// pen on dark dotted paper), through the real input pipeline from
// whole-pixel mouse events: at stabiliser 0 and 30 %, from a 1000 Hz mouse
// (every pixel an event) and a 125 Hz one. See
// `mouse_ink_smoothness_test.dart` for the numbers.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/lab/replay_run.dart';
import 'package:len/ink/render/stroke_renderer.dart';

import 'support/mouse_writing.dart';

/// A row of the specimen: a label's settings and the strokes they left.
typedef _Row = ({String label, List<Stroke> strokes});

List<_Row> _rows(double speed) => [
  for (final (hz, delivery) in const [(1000.0, Delivery.raw), (125.0, Delivery.raw)])
    for (final stabiliser in const [0.0, 0.3])
      (
        label: '${hz.round()} Hz, ${(stabiliser * 100).round()} %',
        strokes: ReplayResult.run(
          mouseRecording(
            ownerFormula(),
            model: MouseModel(hz: hz, delivery: delivery),
            speed: speed,
            pen: penOf(4, stabiliser),
          ).recording,
        ).strokes,
      ),
];

class _Painter extends CustomPainter {
  _Painter(this.rows, {required this.scale, this.origin = Offset.zero});

  static const double rowHeight = 80;

  final List<_Row> rows;
  final double scale;
  final Offset origin;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..drawRect(Offset.zero & size, Paint()..color = const Color(0xFF26262B))
      ..scale(scale)
      ..translate(-origin.dx, -origin.dy);
    final dot = Paint()..color = const Color(0xFF55555C);
    for (var y = 0.0; y < 2000; y += 20) {
      for (var x = 0.0; x < 2000; x += 20) {
        canvas.drawCircle(Offset(x, y), 0.9, dot);
      }
    }
    for (final (i, row) in rows.indexed) {
      canvas
        ..save()
        ..translate(0, i * rowHeight - 40);
      final picture = ui.PictureRecorder();
      final c = Canvas(picture);
      for (final s in row.strokes) {
        StrokeRenderer.draw(c, s);
      }
      canvas
        ..drawPicture(picture.endRecording())
        ..restore();
    }
  }

  @override
  bool shouldRepaint(_Painter old) => false;
}

Future<void> _golden(
  WidgetTester tester,
  String name,
  List<_Row> rows,
  Size size, {
  required double scale,
  Offset origin = Offset.zero,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    RepaintBoundary(
      child: CustomPaint(
        painter: _Painter(rows, scale: scale, origin: origin),
        size: size,
      ),
    ),
  );
  await expectLater(find.byType(RepaintBoundary).first, matchesGoldenFile('goldens/$name.png'));
}

void main() {
  // Rows: 1000 Hz at 0 and 30 %, then 125 Hz at 0 and 30 %.
  final slow = _rows(150);
  final fast = _rows(600);

  testWidgets('mouse handwriting, slow, at 2x (a HiDPI screen)', (tester) async {
    await _golden(tester, 'mouse_ink_slow_2x', slow, const Size(700, 640), scale: 2);
  });

  testWidgets('mouse handwriting, fast, at 2x', (tester) async {
    await _golden(tester, 'mouse_ink_fast_2x', fast, const Size(700, 640), scale: 2);
  });

  testWidgets('mouse handwriting, slow, "x∈ℝ" at 6x', (tester) async {
    await _golden(
      tester,
      'mouse_ink_slow_6x',
      slow,
      const Size(1200, 1500),
      scale: 6,
      origin: const Offset(22, 2),
    );
  });
}
