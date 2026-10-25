import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/core/clock.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/input/hold_to_straighten.dart';
import 'package:len/ink/input/live_ink.dart';
import 'package:len/ink/render/stroke_renderer.dart';
import 'package:len/ink/shapes/shape_builder.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/tools/curve_drawing.dart';
import 'package:len/ink/tools/pointer_tool.dart';
import 'package:len/ink/viewport.dart';

import 'support/hand_shapes.dart';

/// How snapped shapes, circles and curves look: each hand-drawn stroke
/// (grey) under what hold to snap makes of it (ink), at 1× and zoomed in,
/// and curves placed tap by tap with the Shape tool.

int _ids = 0;

const _ink = 0xFF1A2233, _pencil = 0x553A4A6A;

Stroke _stroke(
  List<StrokePoint> points, {
  int color = _ink,
  double width = 2,
  StrokeStyle? style,
}) => Stroke(
  id: 's${_ids++}',
  surfaceId: 's',
  tool: InkTool.ballpoint,
  color: color,
  width: width,
  points: points,
  createdAt: 0,
  style: style ?? const StrokeStyle(thinning: 0, unit: 1),
);

/// A stroke for shape [shape] as hold to snap commits it at [scale].
Stroke _shape(ShapeGeometry shape, {double scale = 1, double width = 2}) {
  final style = ShapeBuilder.styleFor(StrokeStyle(unit: 1 / scale));
  return Stroke(
    id: 's${_ids++}',
    surfaceId: 's',
    tool: InkTool.ballpoint,
    color: _ink,
    width: width,
    points: ShapeBuilder.pointsOf(shape, spacing: 2 / scale),
    createdAt: 0,
    style: style,
    shape: shape,
  );
}

/// The hand-drawn [pts] (grey) and, if it snaps, its shape.
List<Stroke> _snapped(List<Offset> pts) {
  final points = [for (final p in pts) StrokePoint(p.dx, p.dy, 0.5)];
  final shape = HoldToStraighten.snapOf(points, 1);
  return [_stroke(points, color: _pencil, width: 1.5), if (shape != null) _shape(shape)];
}

/// Hand-drawn shapes of every kind hold to snap makes.
List<Stroke> _shapes() {
  final h = HandShapes(3);
  Offset at(int col, int row) => Offset(70 + col * 140.0, 70 + row * 140.0);
  final cases = [
    h.ellipse(at(0, 0), 55, 50),
    h.ellipse(at(1, 0), 50, 56, angle: 0.7),
    h.ellipse(at(2, 0), 62, 38, angle: 0.4),
    h.ellipse(at(3, 0), 60, 40, angle: 0.06),
    h.polygon([
      at(0, 1) - const Offset(55, 40),
      at(0, 1) + const Offset(55, -40),
      at(0, 1) + const Offset(55, 40),
      at(0, 1) + const Offset(-55, 40),
    ]),
    h.polygon([
      at(1, 1) - const Offset(50, 35),
      at(1, 1) + const Offset(50, -35),
      at(1, 1) + const Offset(50, 35),
      at(1, 1) + const Offset(-50, 35),
    ], angle: 0.5),
    h.polygon([
      at(2, 1) + const Offset(0, -55),
      at(2, 1) + const Offset(55, 45),
      at(2, 1) + const Offset(-55, 45),
    ]),
    h.polygon([
      at(3, 1) + const Offset(0, -58),
      at(3, 1) + const Offset(50, 0),
      at(3, 1) + const Offset(0, 58),
      at(3, 1) + const Offset(-50, 0),
    ]),
    h.polygon([
      for (var i = 0; i < 5; i++)
        at(0, 2) + Offset.fromDirection(-math.pi / 2 + i * 2 * math.pi / 5, 58),
    ]),
    h.line(at(1, 2) + const Offset(-55, 40), at(1, 2) + const Offset(55, -40)),
    h.arrow(at(2, 2) + const Offset(-55, 30), at(2, 2) + const Offset(55, -30)),
    h.curve([
      at(3, 2) + const Offset(-60, 30),
      at(3, 2) + const Offset(-10, -50),
      at(3, 2) + const Offset(20, 40),
      at(3, 2) + const Offset(60, -30),
    ]),
  ];
  return [for (final c in cases) ..._snapped(c)];
}

/// Curves hold to snap makes of smooth strokes.
List<Stroke> _curves() {
  final h = HandShapes(5);
  return [
    ..._snapped(
      h.curve(const [Offset(20, 120), Offset(90, 30), Offset(170, 110), Offset(260, 40)]),
    ),
    ..._snapped(h.curve(const [Offset(300, 40), Offset(400, 60), Offset(440, 140)])),
    ..._snapped(
      h.curve(const [
        Offset(40, 200),
        Offset(120, 170),
        Offset(200, 260),
        Offset(110, 300),
        Offset(60, 250),
      ]),
    ),
    ..._snapped(
      h.curve(const [
        Offset(300, 190),
        Offset(420, 200),
        Offset(400, 290),
        Offset(310, 280),
      ], closed: true),
    ),
  ];
}

class _Clock extends Clock {
  int now = 0;
  @override
  int nowMs() => now += 1000;
  @override
  String newId() => 'c${_ids++}';
}

/// The curve the Shape tool makes of taps at [taps] (a press-drag for a
/// tap given as a pair), closed on the first one when [closed].
Future<ShapeGeometry> _tapped(List<Object> taps, {bool closed = false}) async {
  final live = LiveInk();
  final viewport = ViewportController()..setSize(const Size(800, 600));
  final db = AppDatabase.inMemory();
  final model = SurfaceModel(
    surfaceId: 's',
    repository: StrokeRepository(db, deviceId: 'd'),
  );
  final curve = CurveDrawing(live: live, viewport: viewport, clock: _Clock());
  ShapeGeometry? shape;
  void begin() => live.begin(tool: InkTool.ballpoint, color: _ink, width: 2);
  ToolPointer at(Offset p) => ToolPointer(screen: p, world: p);
  for (final t in [...taps, if (closed) taps.first]) {
    final (from, to) = t is Offset ? (t, t) : t as (Offset, Offset);
    curve.down(at(from), model: model, begin: begin);
    if (from != to) {
      for (var k = 1; k <= 8; k++) {
        curve.move(at(Offset.lerp(from, to, k / 8)!));
      }
    }
    shape = live.shape ?? shape;
    curve.up();
  }
  shape = live.shape ?? shape;
  curve
    ..finish()
    ..dispose();
  model.dispose();
  db.close();
  return shape!;
}

Future<List<Stroke>> _toolCurves() async {
  final dots = <Stroke>[];
  Future<Stroke> curve(List<Object> taps, {bool closed = false}) async {
    for (final t in taps) {
      final p = t is Offset ? t : (t as (Offset, Offset)).$1;
      dots.add(_stroke([StrokePoint(p.dx, p.dy, 0.5)], color: 0xFFD03030, width: 6));
    }
    return _shape(await _tapped(taps, closed: closed));
  }

  return [
    await curve(const [Offset(30, 120), Offset(100, 40), Offset(180, 120), Offset(260, 40)]),
    await curve(const [Offset(300, 60), Offset(380, 50), Offset(440, 130), Offset(400, 160)]),
    await curve(const [
      Offset(60, 200),
      Offset(160, 190),
      Offset(200, 260),
      Offset(120, 300),
      Offset(50, 270),
    ], closed: true),
    await curve(const [
      (Offset(280, 280), Offset(320, 220)),
      Offset(380, 290),
      (Offset(440, 220), Offset(470, 280)),
    ]),
    ...dots,
  ];
}

class _Painter extends CustomPainter {
  _Painter(this.picture, {required this.scale, this.origin = Offset.zero});

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
  bool shouldRepaint(_Painter old) => false;
}

ui.Picture _record(List<Stroke> strokes) {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  for (final s in strokes) {
    StrokeRenderer.draw(canvas, s);
  }
  return recorder.endRecording();
}

Future<void> _golden(
  WidgetTester tester,
  String name,
  List<Stroke> strokes,
  Size size, {
  double scale = 1,
  Offset origin = Offset.zero,
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    RepaintBoundary(
      child: CustomPaint(
        painter: _Painter(_record(strokes), scale: scale, origin: origin),
        size: size,
      ),
    ),
  );
  await expectLater(find.byType(RepaintBoundary).first, matchesGoldenFile('goldens/$name.png'));
}

void main() {
  testWidgets('snapped shapes of every kind', (tester) async {
    await _golden(tester, 'shapes_snapped', _shapes(), const Size(560, 420));
  });

  testWidgets('a snapped circle and corners zoomed in', (tester) async {
    final strokes = _shapes();
    await _golden(
      tester,
      'shapes_snapped_4x',
      strokes,
      const Size(480, 480),
      scale: 4,
      origin: const Offset(10, 10),
    );
  });

  testWidgets('curves snapped from smooth strokes', (tester) async {
    await _golden(tester, 'curves_snapped', _curves(), const Size(480, 330));
  });

  testWidgets('curves placed tap by tap', (tester) async {
    final strokes = await tester.runAsync(_toolCurves);
    await _golden(tester, 'curves_tapped', strokes!, const Size(500, 330));
  });
}
