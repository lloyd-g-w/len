import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/ink/input/ink_input_controller.dart';
import 'package:len/ink/input/live_ink.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ink/viewport.dart';

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
    tools = ToolSettings(stylusOnly: true);
    input = InkInputController(
      model: model,
      viewport: ViewportController()..setSize(const Size(800, 600)),
      tools: tools,
      live: LiveInk(),
    );
  });

  tearDown(() {
    model.dispose();
    db.close();
  });

  var clockMs = 0;

  /// Draws a pen stroke through [points], [stepMs] apart, then lifts.
  void draw(List<Offset> points, {int stepMs = 8}) {
    Duration t() => Duration(milliseconds: clockMs += stepMs);
    const kind = PointerDeviceKind.stylus;
    input.handleDown(
      PointerDownEvent(
        pointer: 1,
        kind: kind,
        position: points.first,
        pressure: .5,
        timeStamp: t(),
      ),
    );
    for (final p in points.skip(1)) {
      input.handleMove(
        PointerMoveEvent(pointer: 1, kind: kind, position: p, pressure: .5, timeStamp: t()),
      );
    }
    input.handleUp(PointerUpEvent(pointer: 1, kind: kind, position: points.last, timeStamp: t()));
    clockMs += 500;
  }

  /// A straight line from [a] to [b] in 4 px steps.
  List<Offset> line(Offset a, Offset b) {
    final n = ((b - a).distance / 4).ceil();
    return [for (var i = 0; i <= n; i++) Offset.lerp(a, b, i / n)!];
  }

  /// Eight quick passes between x = [x0] and [x1], drifting down from [y].
  List<Offset> scribble(double x0, double x1, double y) => [
    for (var k = 0; k < 8; k++)
      ...line(
        Offset(k.isEven ? x0 : x1, y + k * 2),
        Offset(k.isEven ? x1 : x0, y + k * 2 + 2),
      ).skip(k == 0 ? 0 : 1),
  ];

  testWidgets('a scribble over ink erases it, not kept itself, one undo step', (tester) async {
    draw(line(const Offset(100, 105), const Offset(160, 110)));
    draw(line(const Offset(300, 105), const Offset(360, 110)));
    expect(model.loadedStrokeCount, 2);
    draw(scribble(90, 170, 100), stepMs: 4);
    expect(model.loadedStrokeCount, 1, reason: 'the word under it went, the other stayed');
    model.undo();
    expect(model.loadedStrokeCount, 2);
  });

  testWidgets('a long line under a scribbled word stays', (tester) async {
    draw(line(const Offset(100, 105), const Offset(160, 105)));
    draw(line(const Offset(20, 112), const Offset(600, 112)));
    draw(scribble(90, 170, 100), stepMs: 4);
    expect(model.loadedStrokeCount, 1);
  });

  testWidgets('over nothing, or switched off, a scribble is ink', (tester) async {
    draw(scribble(90, 170, 100), stepMs: 4);
    expect(model.loadedStrokeCount, 1, reason: 'shading over blank paper');
    tools.scribbleToErase = false;
    draw(scribble(90, 170, 100), stepMs: 4);
    expect(model.loadedStrokeCount, 2);
  });

  testWidgets('a slow back and forth is ink', (tester) async {
    draw(line(const Offset(100, 105), const Offset(160, 110)));
    draw(scribble(90, 170, 100), stepMs: 40);
    expect(model.loadedStrokeCount, 2);
  });
}
