import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/pen/pen_config.dart';
import 'package:len/ink/render/stroke_renderer.dart';

import 'support/handwriting.dart';

int _ids = 0;

Stroke make(InkTool tool, List<StrokePoint> points, {required int color, required double width}) {
  final style = PenConfig.defaultsFor(tool).styleFor(tool, width);
  return Stroke(
    id: 's${_ids++}',
    surfaceId: 's',
    tool: tool,
    color: color,
    width: width,
    points: points,
    createdAt: 0,
    style: style,
  );
}

const ink = 0xFF1A2233;
const blue = 0xFF1C4ED8;

/// A line of handwriting with the pen at [width]: cursive "elle", "eue",
/// an "o", an "s" and a straight stroke.
List<Stroke> writingLine(Handwriting hw, double y, double width, int color) => [
  make(
    InkTool.ballpoint,
    hw.cursive(Offset(12, y), [e, l, l, e, u, e]),
    color: color,
    width: width,
  ),
  make(InkTool.ballpoint, hw.oval(Offset(70, y - 4.5), 4, 4.5), color: color, width: width),
  make(InkTool.ballpoint, hw.letterS(Offset(80, y), 9), color: color, width: width),
  make(InkTool.ballpoint, hw.cursive(Offset(94, y), [u, e, l, e]), color: color, width: width),
  make(InkTool.ballpoint, hw.line(Offset(135, y), Offset(175, y - 14)), color: color, width: width),
];

/// The specimen page: three pen widths and a highlighter behind the middle
/// line.
List<Stroke> specimen() {
  final hw = Handwriting();
  return [
    make(
      InkTool.highlighter,
      hw.line(const Offset(8, 52), const Offset(150, 53), seconds: 0.5),
      color: 0xFFFACC15,
      width: 14,
    ),
    ...writingLine(hw, 26, 1.5, ink),
    ...writingLine(hw, 58, 2.5, ink),
    ...writingLine(hw, 92, 4, blue),
  ];
}

class _SpecimenPainter extends CustomPainter {
  _SpecimenPainter(this.picture, {required this.scale, this.origin = Offset.zero});

  final ui.Picture picture;
  final double scale;
  final Offset origin;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..drawRect(Offset.zero & size, Paint()..color = const Color(0xFFFCFCFA))
      ..scale(scale)
      ..translate(-origin.dx, -origin.dy)
      ..drawPicture(picture);
  }

  @override
  bool shouldRepaint(_SpecimenPainter old) => false;
}

/// Records [strokes] exactly as the chunk cache does: highlighter first.
ui.Picture record(List<Stroke> strokes) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  for (final s in strokes.where((s) => s.tool.isHighlighter)) {
    StrokeRenderer.draw(canvas, s);
  }
  for (final s in strokes.where((s) => !s.tool.isHighlighter)) {
    StrokeRenderer.draw(canvas, s);
  }
  return recorder.endRecording();
}

Future<void> _golden(
  WidgetTester tester,
  String name,
  Size size, {
  required double scale,
  Offset origin = Offset.zero,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final painter = _SpecimenPainter(record(specimen()), scale: scale, origin: origin);
  await tester.pumpWidget(
    RepaintBoundary(
      child: CustomPaint(painter: painter, size: size),
    ),
  );
  await expectLater(find.byType(RepaintBoundary).first, matchesGoldenFile('goldens/$name.png'));
}

void main() {
  testWidgets('ink specimen at 1x', (tester) async {
    await _golden(tester, 'ink_1x', const Size(190, 140), scale: 1);
  });

  testWidgets('ink specimen at 3x (tablet density)', (tester) async {
    await _golden(tester, 'ink_3x', const Size(570, 420), scale: 3);
  });

  testWidgets('ink specimen at 4x', (tester) async {
    await _golden(tester, 'ink_4x', const Size(720, 360), scale: 4, origin: const Offset(5, 10));
  });

  testWidgets('ink specimen at 16x', (tester) async {
    await _golden(tester, 'ink_16x', const Size(800, 600), scale: 16, origin: const Offset(14, 30));
  });

  testWidgets('ink specimen at 16x, thin "o s" and caps', (tester) async {
    await _golden(
      tester,
      'ink_16x_thin',
      const Size(800, 400),
      scale: 16,
      origin: const Offset(64, 12),
    );
  });

  testWidgets('ink specimen at 16x, highlighter end', (tester) async {
    await _golden(
      tester,
      'ink_16x_highlighter',
      const Size(800, 400),
      scale: 16,
      origin: const Offset(126, 40),
    );
  });

  testWidgets('ink specimen at 16x, thick blue line', (tester) async {
    await _golden(
      tester,
      'ink_16x_thick',
      const Size(800, 600),
      scale: 16,
      origin: const Offset(64, 66),
    );
  });
}
