import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/input/hold_to_straighten.dart';
import 'package:len/ink/input/ink_input_controller.dart';
import 'package:len/ink/input/live_ink.dart';
import 'package:len/ink/render/live_stroke.dart';
import 'package:len/ink/shapes/polyline.dart';
import 'package:len/ink/shapes/shape_builder.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ink/viewport.dart';

import 'shapes_test.dart' show loop, sketch;
import 'support/hand_shapes.dart';

void main() {
  late AppDatabase db;
  late SurfaceModel model;
  late InkInputController input;
  late LiveInk live;
  late ViewportController viewport;

  setUp(() {
    db = AppDatabase.inMemory();
    model = SurfaceModel(
      surfaceId: 's',
      repository: StrokeRepository(db, deviceId: 'd'),
    );
    viewport = ViewportController()..setSize(const Size(800, 600));
    live = LiveInk();
    input = InkInputController(
      model: model,
      viewport: viewport,
      tools: ToolSettings(stylusOnly: true),
      live: live,
    );
  });

  tearDown(() {
    model.dispose();
    db.close();
  });

  /// Draws [pts] (screen positions), rests the pen, optionally moves on,
  /// lifts it.
  Future<void> drawAndHold(WidgetTester tester, List<Offset> pts, {bool moveAfter = false}) async {
    PointerEvent at<T>(Offset p) =>
        PointerMoveEvent(pointer: 1, kind: PointerDeviceKind.stylus, position: p, pressure: 0.5);
    input.handleDown(
      PointerDownEvent(
        pointer: 1,
        kind: PointerDeviceKind.stylus,
        position: pts.first,
        pressure: 0.5,
      ),
    );
    for (final p in pts.skip(1)) {
      input.handleMove(at(p) as PointerMoveEvent);
    }
    await tester.pump(HoldToStraighten.holdDuration + const Duration(milliseconds: 50));
    if (moveAfter) input.handleMove(at(pts.last + const Offset(80, 80)) as PointerMoveEvent);
    input.handleUp(const PointerUpEvent(pointer: 1, kind: PointerDeviceKind.stylus));
  }

  testWidgets('a held rough rectangle commits a clean rectangle', (tester) async {
    const box = [Offset(100, 100), Offset(300, 100), Offset(300, 220), Offset(100, 220)];
    await drawAndHold(tester, sketch(loop(box)), moveAfter: true);
    final stroke = model.history.takeUndo()!.added.single;
    // Moving on after the snap turned and scaled it: still a rectangle.
    final shape = stroke.shape!;
    expect(shape.kind, ShapeKind.rectangle);
    final c = shape.points;
    for (var i = 0; i < 4; i++) {
      final a = c[(i + 3) % 4] - c[i], b = c[(i + 1) % 4] - c[i];
      expect((a.dx * b.dx + a.dy * b.dy).abs(), lessThan(1e-6 * a.distance * b.distance));
    }
    // Every point lies on one of its sides.
    for (final p in stroke.points) {
      final onSide = [
        for (var i = 0; i < 4; i++) Polyline.distanceToSegment(p.offset, c[i], c[(i + 1) % 4]),
      ].reduce(math.min);
      expect(onSide, lessThan(1e-6));
    }
    expect(stroke.style.streamline, 0);
  });

  testWidgets('a held scribble stays freehand', (tester) async {
    final pts = [
      for (var i = 0; i < 120; i++)
        Offset(200 + 60 * math.cos(i * 0.9) + i % 7 * 9, 200 + 50 * math.sin(i * 1.7)),
      const Offset(262, 201),
    ];
    await drawAndHold(tester, pts);
    final stroke = model.history.takeUndo()!.added.single;
    expect(stroke.points.length, greaterThan(100));
  });

  /// The stroke the last contact committed.
  Stroke committed() => model.history.takeUndo()!.added.single;

  for (final scale in [1.0, 2.0]) {
    testWidgets('hand-drawn shapes snap in place at ${scale}x, editable', (tester) async {
      viewport.setView(scale: scale, offset: const Offset(-40, 25));
      Offset world(Offset p) => viewport.toWorld(p);
      for (var seed = 0; seed < 6; seed++) {
        final h = HandShapes(seed);
        final cases = <(ShapeKind, List<Offset>)>[
          (ShapeKind.ellipse, h.ellipse(const Offset(300, 300), 110, 70, angle: 0.3)),
          (
            ShapeKind.rectangle,
            h.polygon(const [
              Offset(180, 220),
              Offset(420, 220),
              Offset(420, 380),
              Offset(180, 380),
            ]),
          ),
          (
            ShapeKind.triangle,
            h.polygon(const [Offset(300, 180), Offset(420, 400), Offset(180, 400)], angle: 0.2),
          ),
          (ShapeKind.line, h.line(const Offset(100, 200), const Offset(500, 300))),
          (ShapeKind.arrow, h.arrow(const Offset(100, 450), const Offset(480, 220))),
        ];
        for (final (kind, pts) in cases) {
          await drawAndHold(tester, pts);
          final stroke = committed();
          final shape = stroke.shape;
          expect(shape?.kind, kind, reason: '$kind seed $seed');
          // Built from its geometry, in world coordinates where it was drawn.
          expect(stroke.points.first.offset, ShapeBuilder.outline(shape!).first);
          final drawn = Polyline.bounds([for (final p in pts) world(p)]);
          final snapped = Polyline.bounds(ShapeBuilder.outline(shape));
          final size = drawn.longestSide;
          expect((snapped.center - drawn.center).distance, lessThan(0.08 * size), reason: '$kind');
          expect((snapped.longestSide - size).abs(), lessThan(0.1 * size), reason: '$kind');
          expect(stroke.style.thinning, 0);
        }
      }
    });
  }

  testWidgets('handwriting held mid-word never snaps', (tester) async {
    for (var seed = 0; seed < 4; seed++) {
      for (final word in HandShapes.writing(const Offset(200, 200), seed: seed)) {
        await drawAndHold(tester, word);
        expect(committed().shape, isNull, reason: 'seed $seed');
      }
    }
  });

  testWidgets('a snapped line follows the pen, preview and geometry alike', (tester) async {
    final pts = HandShapes(1).line(const Offset(100, 200), const Offset(400, 230));
    input.handleDown(
      PointerDownEvent(pointer: 1, kind: PointerDeviceKind.stylus, position: pts.first),
    );
    for (final p in pts.skip(1)) {
      input.handleMove(PointerMoveEvent(pointer: 1, kind: PointerDeviceKind.stylus, position: p));
    }
    await tester.pump(HoldToStraighten.holdDuration + const Duration(milliseconds: 50));
    expect(live.shape?.kind, ShapeKind.line);
    LiveStrokeBuilder.livePath(live);
    for (final to in const [Offset(500, 300), Offset(600, 380), Offset(560, 340)]) {
      input.handleMove(PointerMoveEvent(pointer: 1, kind: PointerDeviceKind.stylus, position: to));
      expect(live.shape!.points.last, to);
      final bounds = LiveStrokeBuilder.livePath(live).combined.getBounds();
      // The whole line, from the start to the pen, and nothing else.
      expect(bounds.right, closeTo(to.dx, 3));
      expect(bounds.bottom, closeTo(to.dy, 3));
      expect(bounds.left, closeTo(pts.first.dx, 3));
    }
    input.handleUp(const PointerUpEvent(pointer: 1, kind: PointerDeviceKind.stylus));
    expect(committed().shape!.points, [pts.first, const Offset(560, 340)]);
  });

  testWidgets('a held line nearly level commits level, and stays level as the pen moves on', (
    tester,
  ) async {
    // 2° off level: a graph's axis drawn by hand.
    final pts = HandShapes(2).line(const Offset(100, 300), const Offset(400, 310));
    await drawAndHold(tester, pts);
    final line = committed().shape!.points;
    expect(line.first, pts.first);
    expect(line.last.dy, pts.first.dy);
    // A clearly sloped line stays as drawn.
    final sloped = HandShapes(3).line(const Offset(100, 300), const Offset(400, 360));
    await drawAndHold(tester, sloped);
    expect(committed().shape!.points.last.dy, isNot(300));
  });

  /// Draws [pts] 4 ms apart, then rests the pen at their end the way a
  /// real S Pen rests: it slows down, then drifts a pixel or so either
  /// way while the samples keep coming; lifts it after [restMs].
  Future<void> drawAndRest(WidgetTester tester, List<Offset> pts, {int restMs = 700}) async {
    var ms = 0;
    PointerMoveEvent at(Offset p) => PointerMoveEvent(
      pointer: 1,
      kind: PointerDeviceKind.stylus,
      position: p,
      pressure: 0.5,
      timeStamp: Duration(milliseconds: ms),
    );
    input.handleDown(
      PointerDownEvent(pointer: 1, kind: PointerDeviceKind.stylus, position: pts.first),
    );
    for (final p in pts.skip(1)) {
      ms += 4;
      await tester.pump(const Duration(milliseconds: 4));
      input.handleMove(at(p));
    }
    final end = pts.last, d = pts.last - pts[pts.length - 2];
    final ahead = d / d.distance;
    // Slowing down: 3 px more over 60 ms, then drifting.
    for (var t = 4; t <= restMs; t += 4) {
      ms += 4;
      await tester.pump(const Duration(milliseconds: 4));
      final drift = Offset(1.4 * math.sin(t / 37), 1.2 * math.cos(t / 23));
      input.handleMove(at(end + ahead * 3 * math.min(1, t / 60) + drift));
    }
    input.handleUp(const PointerUpEvent(pointer: 1, kind: PointerDeviceKind.stylus));
  }

  testWidgets('a pen resting as a real one does (drift) still snaps, as drawn', (tester) async {
    await drawAndRest(tester, HandShapes(2).line(const Offset(100, 200), const Offset(220, 210)));
    expect(committed().shape?.kind, ShapeKind.line);
    // A short stroke ending in a slight hook: the drift makes no arrow head.
    await drawAndRest(tester, HandShapes(3).line(const Offset(100, 300), const Offset(160, 330)));
    expect(committed().shape?.kind, ShapeKind.line);
    final h = HandShapes(4);
    await drawAndRest(tester, h.ellipse(const Offset(300, 300), 80, 50));
    expect(committed().shape?.kind, ShapeKind.ellipse);
  });

  testWidgets('a letter-sized straight stroke held stays as written', (tester) async {
    await drawAndRest(tester, HandShapes(2).line(const Offset(100, 200), const Offset(110, 240)));
    expect(committed().shape, isNull);
  });

  testWidgets('a mouse resting with a hairline pen snaps all it drew, to its end', (tester) async {
    // Zoomed out the pen is a hairline on screen: the mouse's ink is
    // levelled and trails it by a few pixels, until the hold flushes them.
    viewport.setView(scale: 0.25, offset: Offset.zero);
    const from = Offset(100, 200), to = Offset(400, 200);
    PointerMoveEvent at(Offset p, int ms) => PointerMoveEvent(
      pointer: 1,
      kind: PointerDeviceKind.mouse,
      buttons: kPrimaryMouseButton,
      position: p,
      timeStamp: Duration(milliseconds: ms),
    );
    input.handleDown(
      const PointerDownEvent(
        pointer: 1,
        kind: PointerDeviceKind.mouse,
        buttons: kPrimaryMouseButton,
        position: from,
      ),
    );
    for (var i = 1; i <= 100; i++) {
      await tester.pump(const Duration(milliseconds: 4));
      input.handleMove(at(Offset.lerp(from, to, i / 100)!, i * 4));
    }
    await tester.pump(HoldToStraighten.holdDuration + const Duration(milliseconds: 50));
    expect(live.shape?.kind, ShapeKind.line);
    final end = viewport.toWorld(to);
    expect((live.shape!.points.last - end).distance, lessThan(1 / viewport.scale));
    input.handleUp(const PointerUpEvent(pointer: 1, kind: PointerDeviceKind.mouse));
    expect((committed().shape!.points.last - end).distance, lessThan(1 / viewport.scale));
  });
}
