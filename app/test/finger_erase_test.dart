import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/ink/input/ink_input_controller.dart';
import 'package:len/ink/input/live_ink.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ink/viewport.dart';

/// Pointer events of one pointer; [at] is the event time in seconds (the
/// pen's palm window counts from it).
PointerDownEvent _down(int id, PointerDeviceKind kind, Offset at, int s) => PointerDownEvent(
  pointer: id,
  kind: kind,
  position: at,
  buttons: kPrimaryButton,
  pressure: 0.5,
  timeStamp: Duration(seconds: s),
);

PointerMoveEvent _move(int id, PointerDeviceKind kind, Offset at, int s) => PointerMoveEvent(
  pointer: id,
  kind: kind,
  position: at,
  buttons: kPrimaryButton,
  pressure: 0.5,
  timeStamp: Duration(seconds: s),
);

PointerUpEvent _up(int id, PointerDeviceKind kind, Offset at, int s) => PointerUpEvent(
  pointer: id,
  kind: kind,
  position: at,
  timeStamp: Duration(seconds: s),
);

const _stylus = PointerDeviceKind.stylus;
const _touch = PointerDeviceKind.touch;

void main() {
  late AppDatabase db;
  late SurfaceModel model;
  late ToolSettings tools;
  late InkInputController input;

  setUp(() {
    db = AppDatabase.inMemory();
    model = SurfaceModel(
      surfaceId: 's',
      repository: StrokeRepository(db, deviceId: 'd'),
    );
    tools = ToolSettings(stylusOnly: false);
    input = InkInputController(
      model: model,
      viewport: ViewportController()..setSize(const Size(800, 600)),
      tools: tools,
      live: LiveInk(),
    );
    // A line along y = 100, then the eraser.
    input
      ..handleDown(_down(1, _stylus, const Offset(10, 100), 0))
      ..handleMove(_move(1, _stylus, const Offset(100, 100), 0))
      ..handleMove(_move(1, _stylus, const Offset(200, 100), 0))
      ..handleUp(_up(1, _stylus, const Offset(200, 100), 0));
    tools.tool = EditorTool.eraser;
    expect(model.loadedStrokeCount, 1);
  });

  tearDown(() {
    model.dispose();
    db.close();
  });

  test('a palm resting on ink erases nothing when the pen lands', () {
    input
      ..handleDown(_down(2, _touch, const Offset(100, 100), 10))
      ..handleMove(_move(2, _touch, const Offset(102, 101), 10))
      ..handleDown(_down(3, _stylus, const Offset(400, 400), 10));
    expect(model.loadedStrokeCount, 1);
    expect(model.history.canUndo, isTrue); // Only the line.
  });

  test('a palm resting on ink erases nothing when the pen hovers over the page', () {
    input
      ..handleDown(_down(2, _touch, const Offset(100, 100), 10))
      ..handleMove(_move(2, _touch, const Offset(102, 101), 10))
      ..handleHover(
        const PointerHoverEvent(
          kind: _stylus,
          position: Offset(400, 400),
          timeStamp: Duration(seconds: 10),
        ),
      )
      ..handleUp(_up(2, _touch, const Offset(102, 101), 11));
    expect(model.loadedStrokeCount, 1);
  });

  test('a finger on ink that becomes a pinch erases nothing', () {
    input
      ..handleDown(_down(2, _touch, const Offset(100, 100), 10))
      ..handleMove(_move(2, _touch, const Offset(103, 100), 10))
      ..handleDown(_down(3, _touch, const Offset(300, 300), 10))
      ..handleMove(_move(3, _touch, const Offset(350, 350), 10))
      ..handleUp(_up(2, _touch, const Offset(103, 100), 10))
      ..handleUp(_up(3, _touch, const Offset(350, 350), 10));
    expect(model.loadedStrokeCount, 1);
  });

  test('a finger erases once it moves, from where it landed', () {
    input
      ..handleDown(_down(2, _touch, const Offset(100, 100), 10))
      ..handleMove(_move(2, _touch, const Offset(100, 105), 10));
    expect(model.loadedStrokeCount, 1, reason: 'within the touch slop');
    input.handleMove(_move(2, _touch, const Offset(100, 160), 10));
    expect(model.loadedStrokeCount, 0);
    input.handleUp(_up(2, _touch, const Offset(100, 160), 10));
    expect(model.loadedStrokeCount, 0);
  });

  test('a finger tap erases at the lift', () {
    input.handleDown(_down(2, _touch, const Offset(100, 100), 10));
    expect(model.loadedStrokeCount, 1);
    input.handleUp(_up(2, _touch, const Offset(100, 100), 10));
    expect(model.loadedStrokeCount, 0);
  });

  test('the pen erases as soon as it lands', () {
    input.handleDown(_down(2, _stylus, const Offset(100, 100), 10));
    expect(model.loadedStrokeCount, 0);
  });
}
