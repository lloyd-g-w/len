import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/ink/input/hold_to_straighten.dart';
import 'package:len/ink/input/ink_input_controller.dart';
import 'package:len/ink/input/live_ink.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ink/viewport.dart';

import 'shapes_test.dart' show loop, sketch;

void main() {
  late AppDatabase db;
  late SurfaceModel model;
  late InkInputController input;

  setUp(() {
    db = AppDatabase.inMemory();
    model = SurfaceModel(
      surfaceId: 's',
      repository: StrokeRepository(db, deviceId: 'd'),
    );
    input = InkInputController(
      model: model,
      viewport: ViewportController()..setSize(const Size(800, 600)),
      tools: ToolSettings(stylusOnly: true),
      live: LiveInk(),
    );
  });

  tearDown(() {
    model.dispose();
    db.close();
  });

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
    final xs = stroke.points.map((p) => p.x).toSet();
    // Every point lies on one of the rectangle's sides.
    final left = xs.reduce(math.min), right = xs.reduce(math.max);
    final ys = stroke.points.map((p) => p.y);
    final top = ys.reduce(math.min), bottom = ys.reduce(math.max);
    for (final p in stroke.points) {
      final onSide = [p.x - left, right - p.x, p.y - top, bottom - p.y].any((d) => d.abs() < 1e-3);
      expect(onSide, isTrue);
    }
    expect(stroke.style.streamline, 0);
    // Moving after the snap did not distort it.
    expect(right, lessThan(320));
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
}
