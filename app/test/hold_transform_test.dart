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
import 'package:len/ink/shapes/held_shape.dart';
import 'package:len/ink/shapes/polyline.dart';
import 'package:len/ink/shapes/shape_builder.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ink/viewport.dart';

import 'support/hand_shapes.dart';

/// Hold to snap, then (the pen still down) turning and scaling the shape
/// with the pen, as simulated pointer sequences: the stroke, the snap and
/// the transform are one stroke and one undo step.
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

  PointerMoveEvent at(Offset p) =>
      PointerMoveEvent(pointer: 1, kind: PointerDeviceKind.stylus, position: p, pressure: 0.5);

  /// Draws [pts], rests the pen until the stroke snaps, then moves the pen
  /// through [then] (screen) and lifts it. Returns the committed stroke.
  Future<Stroke> drawHoldMove(WidgetTester tester, List<Offset> pts, List<Offset> then) async {
    input.handleDown(
      PointerDownEvent(
        pointer: 1,
        kind: PointerDeviceKind.stylus,
        position: pts.first,
        pressure: 0.5,
      ),
    );
    for (final p in pts.skip(1)) {
      input.handleMove(at(p));
    }
    await tester.pump(HoldToStraighten.holdDuration + const Duration(milliseconds: 50));
    expect(live.shape, isNotNull, reason: 'snapped');
    for (final p in then) {
      input.handleMove(at(p));
    }
    input.handleUp(const PointerUpEvent(pointer: 1, kind: PointerDeviceKind.stylus));
    final edit = model.history.takeUndo()!;
    // One step: the stroke as finally transformed, nothing before it.
    expect(model.history.takeUndo(), isNull);
    return edit.added.single;
  }

  /// The pen's path from [from] turning by [turn] about [centre] and
  /// ending [scale] times as far from it, in small steps.
  List<Offset> swing(Offset from, Offset centre, double turn, double scale) => [
    for (var i = 1; i <= 24; i++)
      () {
        final f = i / 24, d = from - centre, a = turn * f, s = 1 + (scale - 1) * f;
        return centre +
            Offset(
                  d.dx * math.cos(a) - d.dy * math.sin(a),
                  d.dx * math.sin(a) + d.dy * math.cos(a),
                ) *
                s;
      }(),
  ];

  testWidgets('a held circle scales with the pen and stays a circle, centred', (tester) async {
    const c = Offset(300, 300);
    for (var seed = 0; seed < 4; seed++) {
      final pts = HandShapes(seed).ellipse(c, 80, 78);
      final stroke = await drawHoldMove(tester, pts, swing(pts.last, c, 0.6, 1.5));
      final shape = stroke.shape!;
      expect(shape.kind, ShapeKind.circle, reason: 'seed $seed');
      final [centre, rim] = shape.points;
      expect((centre - c).distance, lessThan(6));
      expect((rim - centre).distance, closeTo(1.5 * 79, 10), reason: 'seed $seed');
      // Its points are its outline, as shown live.
      expect(stroke.points.first.offset, ShapeBuilder.outline(shape).first);
    }
  });

  testWidgets('a held rectangle turns with the pen about its centre, size kept', (tester) async {
    const corners = [Offset(200, 220), Offset(400, 220), Offset(400, 360), Offset(200, 360)];
    final pts = HandShapes(1).polygon(corners);
    final stroke = await drawHoldMove(tester, pts, swing(pts.last, const Offset(300, 290), 0.5, 1));
    final p = stroke.shape!.points;
    expect(stroke.shape!.kind, ShapeKind.rectangle);
    final side = p[1] - p[0];
    final angle = side.direction % (math.pi / 2);
    expect(angle, closeTo(0.5, 0.05));
    expect(side.distance, closeTo(200, 14));
    expect(((p[0] + p[2]) / 2 - const Offset(300, 290)).distance, lessThan(8));
  });

  testWidgets('turned nearly a quarter, a rectangle snaps upright exactly', (tester) async {
    const corners = [Offset(200, 220), Offset(400, 220), Offset(400, 360), Offset(200, 360)];
    final pts = HandShapes(2).polygon(corners, angle: 0.02);
    final turn = math.pi / 2 - 3 * math.pi / 180;
    final stroke = await drawHoldMove(
      tester,
      pts,
      swing(pts.last, const Offset(300, 290), turn, 1),
    );
    final p = stroke.shape!.points;
    for (var i = 0; i < 4; i++) {
      final d = p[(i + 1) % 4] - p[i];
      expect(d.dx == 0 || d.dy == 0, isTrue, reason: 'side $i: $d');
    }
    // Upright: the long sides now run down.
    final long = (p[1] - p[0]).distance > (p[2] - p[1]).distance ? p[1] - p[0] : p[2] - p[1];
    expect(long.dx, 0);
  });

  testWidgets('a pen resting after the snap, or barely moving, changes nothing', (tester) async {
    const corners = [Offset(200, 220), Offset(400, 220), Offset(400, 360), Offset(200, 360)];
    final pts = HandShapes(3).polygon(corners);
    input.handleDown(
      PointerDownEvent(pointer: 1, kind: PointerDeviceKind.stylus, position: pts[0]),
    );
    for (final p in pts.skip(1)) {
      input.handleMove(at(p));
    }
    await tester.pump(HoldToStraighten.holdDuration + const Duration(milliseconds: 50));
    final snapped = live.shape;
    input.handleMove(at(pts.last + const Offset(2, -2)));
    expect(live.shape, snapped);
    // A small turn or resize (the pen sliding a little) keeps it too.
    final c = HeldShape(snapped!, viewport.toWorld(pts.last)).centre;
    final d = pts.last - c;
    final a = 1.2 * math.pi / 180;
    input.handleMove(
      at(
        c +
            Offset(
                  d.dx * math.cos(a) - d.dy * math.sin(a),
                  d.dx * math.sin(a) + d.dy * math.cos(a),
                ) *
                1.02,
      ),
    );
    expect(live.shape, snapped);
    input.handleUp(const PointerUpEvent(pointer: 1, kind: PointerDeviceKind.stylus));
    expect(model.history.takeUndo()!.added.single.shape, snapped);
  });

  testWidgets('a held arrow keeps its tail; its tip follows the pen', (tester) async {
    final pts = HandShapes(4).arrow(const Offset(100, 400), const Offset(400, 250));
    input.handleDown(
      PointerDownEvent(pointer: 1, kind: PointerDeviceKind.stylus, position: pts[0]),
    );
    for (final p in pts.skip(1)) {
      input.handleMove(at(p));
    }
    await tester.pump(HoldToStraighten.holdDuration + const Duration(milliseconds: 50));
    final snapped = live.shape!;
    expect(snapped.kind, ShapeKind.arrow);
    const by = Offset(60, 90);
    for (var i = 1; i <= 10; i++) {
      input.handleMove(at(pts.last + by * (i / 10)));
    }
    input.handleUp(const PointerUpEvent(pointer: 1, kind: PointerDeviceKind.stylus));
    final arrow = model.history.takeUndo()!.added.single.shape!;
    expect(arrow.kind, ShapeKind.arrow);
    expect(arrow.points[0], snapped.points[0]);
    expect((arrow.points[1] - (snapped.points[1] + by)).distance, lessThan(1e-6));
  });

  testWidgets('the live outline is the whole transformed shape at every move', (tester) async {
    const c = Offset(300, 300);
    final pts = HandShapes(5).ellipse(c, 100, 60, angle: 0.3);
    input.handleDown(
      PointerDownEvent(pointer: 1, kind: PointerDeviceKind.stylus, position: pts[0]),
    );
    for (final p in pts.skip(1)) {
      input.handleMove(at(p));
    }
    await tester.pump(HoldToStraighten.holdDuration + const Duration(milliseconds: 50));
    expect(live.shape!.kind, ShapeKind.ellipse);
    LiveStrokeBuilder.livePath(live);
    for (final p in swing(pts.last, c, 1.0, 0.7)) {
      input.handleMove(at(p));
      final outline = Polyline.bounds(ShapeBuilder.outline(live.shape!));
      final shown = LiveStrokeBuilder.livePath(live).combined.getBounds();
      // The outline as built, widened by the pen and nothing else.
      expect((shown.center - outline.center).distance, lessThan(1.5));
      expect((shown.width - outline.width).abs(), lessThan(live.width + 1.5));
      expect((shown.height - outline.height).abs(), lessThan(live.width + 1.5));
    }
    input.handleUp(const PointerUpEvent(pointer: 1, kind: PointerDeviceKind.stylus));
    final shape = model.history.takeUndo()!.added.single.shape!;
    expect(shape.kind, ShapeKind.ellipse);
    // Scaled to 0.7: semi-axes of about 70 and 42.
    final [e, u, v] = shape.points;
    final axes = [(u - e).distance, (v - e).distance]..sort();
    expect(axes[1], closeTo(70, 8));
    expect(axes[0], closeTo(42, 6));
  });

  group('HeldShape', () {
    test('turns snap level within 5°, and to 15° steps within 2°', () {
      final square = ShapeGeometry(ShapeKind.rectangle, const [
        Offset(0, 0),
        Offset(100, 0),
        Offset(100, 100),
        Offset(0, 100),
      ]);
      final held = HeldShape(square, const Offset(150, 50));
      Offset pen(double degrees) =>
          held.centre + Offset.fromDirection(degrees * math.pi / 180, 100);
      double angleOf(ShapeGeometry s) => (s.points[1] - s.points[0]).direction * 180 / math.pi;
      expect(angleOf(held.at(pen(43))), closeTo(45, 1e-9));
      expect(angleOf(held.at(pen(31))), closeTo(30, 1e-9));
      expect(angleOf(held.at(pen(27))), closeTo(27, 1e-9));
      expect(held.at(pen(88)).points[0].dx, held.at(pen(88)).points[1].dx);
    });

    test('a circle turned and scaled is still exactly a circle', () {
      final circle = ShapeGeometry(ShapeKind.circle, const [Offset(10, 10), Offset(60, 10)]);
      final s = HeldShape(circle, const Offset(60, 10)).at(const Offset(10, 90));
      expect(s.kind, ShapeKind.circle);
      expect(s.points[0], const Offset(10, 10));
      expect((s.points[1] - s.points[0]).distance, closeTo(80, 1e-9));
    });
  });
}
