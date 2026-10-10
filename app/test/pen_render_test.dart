import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/pen/pen_config.dart';
import 'package:len/ink/render/stroke_renderer.dart';

/// Handwriting-like loops ("llll") with natural pressure swell, sampled
/// like a stylus (~1.5 units apart).
List<StrokePoint> loops(Offset origin, {double scale = 1}) {
  final pts = <StrokePoint>[];
  for (var t = 0.0; t <= 4 * 2 * math.pi; t += 0.06) {
    final x = 9 * t - 14 * math.sin(t);
    final y = -22 * math.cos(t) + 10;
    final p = 0.35 + 0.55 * math.pow(math.sin(t / 2).abs(), 1.5);
    pts.add(StrokePoint(origin.dx + x * scale, origin.dy + y * scale, p.toDouble()));
  }
  return pts;
}

/// A quick flick: pressure rises then falls, like a brush stroke.
List<StrokePoint> flick(Offset origin, double length) => [
  for (var i = 0; i <= 60; i++)
    StrokePoint(
      origin.dx + length * i / 60,
      origin.dy + 18 * math.sin(i / 60 * math.pi) - 9,
      0.2 + 0.8 * math.sin(i / 60 * math.pi),
    ),
];

/// A clockwise circle at constant pressure: shows direction-dependent
/// width (the fountain nib) on its own.
List<StrokePoint> circle(Offset c, double r) => [
  for (var i = 0; i <= 72; i++)
    StrokePoint(
      c.dx + r * math.cos(i / 72 * 2 * math.pi),
      c.dy + r * math.sin(i / 72 * 2 * math.pi),
      0.6,
    ),
];

Stroke make(InkTool tool, List<StrokePoint> points, {int? color, double? width}) {
  final config = PenConfig.defaultsFor(tool);
  final w = width ?? config.current.width;
  return Stroke(
    id: '${tool.name}-${points.first.x}-${points.first.y}',
    surfaceId: 's',
    tool: tool,
    color: color ?? config.current.color,
    width: w,
    points: points,
    createdAt: 0,
    style: config.styleFor(tool, w),
  );
}

/// One row per pen type (loops, then a flick), drawn through a recorded
/// picture exactly as the chunk cache does; a highlighter crosses the
/// third row and must sit beneath its ink.
List<Stroke> specimen() {
  final strokes = <Stroke>[];
  const tools = InkTool.pens;
  for (var r = 0; r < tools.length; r++) {
    final y = 40.0 + r * 64;
    strokes
      ..add(make(tools[r], loops(Offset(16, y))))
      ..add(make(tools[r], flick(Offset(250, y), 130)))
      ..add(make(tools[r], circle(Offset(430, y), 22)));
  }
  strokes.add(
    make(InkTool.highlighter, [
      for (var i = 0; i <= 50; i++) StrokePoint(10 + i * 7.0, 172 + math.sin(i / 7) * 2, 0.5),
    ]),
  );
  return strokes;
}

class _SpecimenPainter extends CustomPainter {
  _SpecimenPainter({required this.scale, this.origin = Offset.zero});

  final double scale;
  final Offset origin;

  @override
  void paint(Canvas canvas, Size size) {
    canvas
      ..drawRect(Offset.zero & size, Paint()..color = const Color(0xFFFCFCFA))
      ..scale(scale)
      ..translate(-origin.dx, -origin.dy)
      ..drawPicture(_record(specimen()));
  }

  ui.Picture _record(List<Stroke> strokes) {
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

  @override
  bool shouldRepaint(_SpecimenPainter old) => false;
}

Future<void> _golden(WidgetTester tester, String name, Size size, _SpecimenPainter painter) async {
  await tester.binding.setSurfaceSize(size);
  await tester.pumpWidget(
    RepaintBoundary(
      child: CustomPaint(painter: painter, size: size),
    ),
  );
  await expectLater(find.byType(RepaintBoundary).first, matchesGoldenFile('goldens/$name.png'));
}

void main() {
  testWidgets('pen specimen sheet', (tester) async {
    await _golden(tester, 'pens', const Size(960, 700), _SpecimenPainter(scale: 2));
  });

  testWidgets('pen specimen sheet at 1:1', (tester) async {
    await _golden(tester, 'pens_1x', const Size(480, 350), _SpecimenPainter(scale: 1));
  });

  testWidgets('pen specimen sheet, zoomed in', (tester) async {
    await _golden(
      tester,
      'pens_zoom',
      const Size(800, 800),
      _SpecimenPainter(scale: 5, origin: const Offset(10, 150)),
    );
  });
}
