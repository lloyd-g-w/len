import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/input/ink_input_controller.dart';
import 'package:len/ink/input/live_ink.dart';
import 'package:len/ink/input/wet_ink.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ink/viewport.dart';

/// Pen options that change input: highlighter straight lines and eraser
/// auto-deselect.
void main() {
  late AppDatabase db;
  late SurfaceModel model;
  late ToolSettings tools;
  late LiveInk live;
  late InkInputController input;

  setUp(() {
    db = AppDatabase.inMemory();
    model = SurfaceModel(
      surfaceId: 's',
      repository: StrokeRepository(db, deviceId: 'd'),
    );
    tools = ToolSettings(stylusOnly: true);
    live = LiveInk();
    input = InkInputController(
      model: model,
      viewport: ViewportController()..setSize(const Size(800, 600)),
      tools: tools,
      live: live,
    );
  });

  tearDown(() {
    model.dispose();
    db.close();
  });

  PointerDownEvent down(
    Offset at, {
    PointerDeviceKind kind = PointerDeviceKind.stylus,
    int b = 0,
  }) => PointerDownEvent(pointer: 1, kind: kind, position: at, pressure: 0.5, buttons: b | 1);
  PointerMoveEvent move(
    Offset at, {
    PointerDeviceKind kind = PointerDeviceKind.stylus,
    int b = 0,
  }) => PointerMoveEvent(pointer: 1, kind: kind, position: at, pressure: 0.5, buttons: b | 1);
  PointerUpEvent up(Offset at, {PointerDeviceKind kind = PointerDeviceKind.stylus}) =>
      PointerUpEvent(pointer: 1, kind: kind, position: at);

  /// A wavy stroke through [points].
  void draw(List<Offset> points, {PointerDeviceKind kind = PointerDeviceKind.stylus, int b = 0}) {
    input.handleDown(down(points.first, kind: kind, b: b));
    for (final p in points.skip(1)) {
      input.handleMove(move(p, kind: kind, b: b));
    }
    input.handleUp(up(points.last, kind: kind));
  }

  const wavy = [Offset(100, 100), Offset(150, 140), Offset(200, 80), Offset(260, 130)];

  group('highlighter straight lines', () {
    setUp(() {
      tools
        ..tool = EditorTool.highlighter
        ..updateConfig(InkTool.highlighter, (c) => c.copyWith(straight: true));
    });

    test('the live stroke is the line from pen-down to the pen', () {
      input
        ..handleDown(down(wavy[0]))
        ..handleMove(move(wavy[1]));
      expect(live.straightened, isTrue);
      expect(WetInkStyle.of(live, 1), isNull, reason: 'drawn by Flutter, not the overlay');
      input.handleMove(move(wavy[2]));
      expect(live.points.first.offset, wavy[0]);
      expect(live.points.last.offset, wavy[2]);
      for (final p in live.points) {
        expect(p.y, closeTo(100 + (p.x - 100) * -20 / 100, 1e-6), reason: 'on the line');
      }
      input.handleUp(up(wavy[2]));
    });

    test('commits a straight stroke without stabiliser', () {
      draw(wavy);
      final stroke = model.history.takeUndo()!.added.single;
      expect(stroke.tool, InkTool.highlighter);
      expect(stroke.points.first.offset, wavy.first);
      expect(stroke.points.last.offset, wavy.last);
      final slope = (wavy.last.dy - wavy.first.dy) / (wavy.last.dx - wavy.first.dx);
      for (final p in stroke.points) {
        expect(p.y - wavy.first.dy, closeTo((p.x - wavy.first.dx) * slope, 1e-6));
      }
      expect(stroke.style.streamline, 0);
    });

    test('the pen still draws freehand', () {
      tools.tool = EditorTool.pen;
      draw(wavy);
      final stroke = model.history.takeUndo()!.added.single;
      expect(stroke.points.map((p) => p.offset), containsAll(wavy));
    });
  });

  group('eraser auto-deselect', () {
    setUp(() {
      draw([const Offset(10, 300), const Offset(400, 300)]); // Something to erase.
      tools
        ..tool = EditorTool.highlighter
        ..tool = EditorTool.eraser
        ..eraser = tools.eraser.copyWith(autoDeselect: true);
    });

    const across = [Offset(200, 250), Offset(200, 300), Offset(200, 350)];

    test('an erase stroke with the eraser tool goes back to the previous ink', () {
      draw(across);
      expect(model.loadedStrokeCount, 0);
      expect(tools.tool, EditorTool.highlighter);
      expect(live.eraserCenter, isNull, reason: 'no eraser cursor left behind');
    });

    test('also for the mouse', () {
      draw(across, kind: PointerDeviceKind.mouse);
      expect(tools.tool, EditorTool.highlighter);
    });

    test('the side button and the eraser end leave the tool alone', () {
      draw(across, b: kPrimaryStylusButton);
      expect(model.loadedStrokeCount, 0, reason: 'the side button erased');
      draw(across, kind: PointerDeviceKind.invertedStylus);
      expect(tools.tool, EditorTool.eraser);
    });

    test('off: the eraser stays', () {
      tools.eraser = tools.eraser.copyWith(autoDeselect: false);
      draw(across);
      expect(tools.tool, EditorTool.eraser);
    });
  });
}
