import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/element_repository.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/ink/input/ink_input_controller.dart';
import 'package:len/ink/input/live_ink.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ink/undo_history.dart';
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
      elementRepository: ElementRepository(db, deviceId: 'd'),
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

  /// Draws a pen stroke through [points], [stepMs] apart, then lifts
  /// (unless [lift] is false).
  void draw(List<Offset> points, {int stepMs = 8, bool lift = true}) {
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
    if (!lift) return;
    input.handleUp(PointerUpEvent(pointer: 1, kind: kind, position: points.last, timeStamp: t()));
    clockMs += 500;
  }

  /// A straight line from [a] to [b] in 4 px steps.
  List<Offset> line(Offset a, Offset b) {
    final n = ((b - a).distance / 4).ceil();
    return [for (var i = 0; i <= n; i++) Offset.lerp(a, b, i / n)!];
  }

  /// [passes] quick passes between x = [x0] and [x1], drifting down
  /// from [y].
  List<Offset> scribble(double x0, double x1, double y, {int passes = 8}) => [
    for (var k = 0; k < passes; k++)
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

  testWidgets('with the stabiliser on a scribble still erases (it reads the pen)', (tester) async {
    // (At 100 % it does not yet: the detector hears the pen only when the
    // ink moves, and an 80 px string holds the ink still on the turns.)
    for (final (setting, x0, x1) in [(0.4, 90.0, 170.0), (0.6, 90.0, 170.0)]) {
      tools.updateConfig(tools.activeInk, (c) => c.copyWith(streamline: 0));
      draw(line(const Offset(100, 105), const Offset(160, 110)));
      draw(line(const Offset(400, 105), const Offset(460, 110)));
      final before = model.loadedStrokeCount;
      tools.updateConfig(tools.activeInk, (c) => c.copyWith(streamline: setting));
      draw(scribble(x0, x1, 100), stepMs: 4);
      expect(model.loadedStrokeCount, before - 1, reason: 'at $setting');
    }
  });

  testWidgets('three passes (there, back, there) erase at pen-up', (tester) async {
    draw(line(const Offset(100, 105), const Offset(160, 110)));
    draw(scribble(90, 170, 100, passes: 3), stepMs: 4, lift: false);
    expect(model.loadedStrokeCount, 1);
    input.handleUp(
      PointerUpEvent(
        pointer: 1,
        kind: PointerDeviceKind.stylus,
        timeStamp: Duration(milliseconds: clockMs += 4),
      ),
    );
    expect(model.loadedStrokeCount, 0);
    draw(line(const Offset(100, 105), const Offset(160, 110)));
    draw(scribble(90, 170, 100, passes: 2), stepMs: 4);
    expect(model.loadedStrokeCount, 2, reason: 'one back and forth is ink');
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

  testWidgets('while scribbling, what will go dims; cancelled, it comes back', (tester) async {
    draw(line(const Offset(100, 105), const Offset(160, 110)));
    draw(line(const Offset(300, 105), const Offset(360, 110)));
    final word = model.strokesNear(Rect.largest).singleWhere((s) => s.bounds.left < 200);
    final other = model.strokesNear(Rect.largest).singleWhere((s) => s.bounds.left > 200);
    draw(scribble(90, 170, 100), stepMs: 4, lift: false);
    expect(model.isHidden(word.id), isTrue, reason: 'drawn dimmed instead');
    expect(model.isHidden(other.id), isFalse);
    expect(model.hasLiftedExcept(const {}), isTrue);
    input.handleCancel(const PointerCancelEvent(pointer: 1, kind: PointerDeviceKind.stylus));
    expect(model.isHidden(word.id), isFalse);
    expect(model.hasLiftedExcept(const {}), isFalse);
    expect(model.loadedStrokeCount, 2);

    // Finished, it erases the word: one undo step brings it back.
    draw(scribble(90, 170, 100), stepMs: 4);
    expect(model.strokeById(word.id), isNull);
    expect(model.hasLiftedExcept(const {}), isFalse);
    model.undo();
    expect(model.strokeById(word.id), isNotNull);
    expect(model.isHidden(word.id), isFalse);
  });

  testWidgets('only the part that zigzags erases, not a lead-in (R8-25)', (tester) async {
    draw(line(const Offset(100, 105), const Offset(140, 110)));
    draw(line(const Offset(300, 105), const Offset(360, 110)));
    final word = model.strokesNear(Rect.largest).singleWhere((s) => s.bounds.left > 200);
    // From the first word, across to the second and scribbling there.
    draw([...line(const Offset(80, 104), const Offset(290, 100)), ...scribble(290, 370, 100)]);
    expect(model.loadedStrokeCount, 1, reason: 'the first word stays');
    expect(model.strokeById(word.id), isNull);

    // Running on after the zigzag doesn't count either.
    draw(line(const Offset(300, 205), const Offset(360, 210)));
    draw(line(const Offset(500, 210), const Offset(560, 212)));
    final after = model.strokesNear(Rect.largest).singleWhere((s) => s.bounds.left > 450);
    draw([...scribble(290, 370, 200), ...line(const Offset(290, 214), const Offset(600, 214))]);
    expect(model.strokeById(after.id), isNotNull);
    expect(model.loadedStrokeCount, 2);
  });

  testWidgets('filling in a small outline quickly keeps the outline (R8-25)', (tester) async {
    // A checkbox, then a quick fill that overshoots it a little.
    draw([
      ...line(const Offset(100, 100), const Offset(140, 100)),
      ...line(const Offset(140, 100), const Offset(140, 140)).skip(1),
      ...line(const Offset(140, 140), const Offset(100, 140)).skip(1),
      ...line(const Offset(100, 140), const Offset(100, 101)).skip(1),
    ]);
    final box = model.strokesNear(Rect.largest).single;
    draw([
      for (var k = 0; k < 10; k++)
        ...line(
          Offset(k.isEven ? 97 : 143, 102 + k * 3.6),
          Offset(k.isEven ? 143 : 97, 102 + (k + 1) * 3.6),
        ).skip(k == 0 ? 0 : 1),
    ], stepMs: 4);
    expect(model.strokeById(box.id), isNotNull, reason: 'the outline stays');
    expect(model.loadedStrokeCount, 2, reason: 'the fill is ink');

    // A word in a box scribbled out goes; the box stays.
    draw(line(const Offset(300, 118), const Offset(330, 122)));
    final word = model.strokesNear(Rect.largest).singleWhere((s) => s.bounds.left > 250);
    draw([
      ...line(const Offset(280, 100), const Offset(350, 100)),
      ...line(const Offset(350, 100), const Offset(350, 140)).skip(1),
      ...line(const Offset(350, 140), const Offset(280, 140)).skip(1),
      ...line(const Offset(280, 140), const Offset(280, 101)).skip(1),
    ]);
    draw(scribble(295, 335, 112), stepMs: 4);
    expect(model.strokeById(word.id), isNull);
    expect(model.loadedStrokeCount, 3, reason: 'both outlines and the first fill');
  });

  testWidgets('a scribble snapped to a line by holding is no scribble (R8-28)', (tester) async {
    draw(line(const Offset(100, 105), const Offset(160, 110)));
    draw(scribble(90, 170, 100), stepMs: 4, lift: false);
    // Hold still: hold to snap makes it a line.
    await tester.pump(const Duration(milliseconds: 700));
    input.handleUp(
      PointerUpEvent(
        pointer: 1,
        kind: PointerDeviceKind.stylus,
        position: const Offset(90, 116),
        timeStamp: Duration(milliseconds: clockMs += 700),
      ),
    );
    expect(model.loadedStrokeCount, 2, reason: 'the word stays; the line is ink');
  });

  testWidgets('a scribble over a text box only is dropped, and says so (R8-29)', (tester) async {
    var missed = 0;
    input.events.scribbleMissed = () => missed++;
    model.commit(
      InkEdit(
        addedElements: [
          SurfaceElement(
            id: 't',
            surfaceId: 's',
            type: ElementType.text.name,
            rect: const Rect.fromLTWH(80, 90, 120, 40),
            z: 1,
            createdAt: 0,
            data: const TextData(text: 'Mitosis').toJson(),
          ),
        ],
      ),
    );
    draw(scribble(90, 170, 100), stepMs: 4);
    expect(model.loadedStrokeCount, 0, reason: 'not left as a zigzag');
    expect(missed, 1);
    expect(model.elementById('t'), isNotNull);
    // Over blank paper it is ink, as before.
    draw(scribble(390, 470, 300), stepMs: 4);
    expect(model.loadedStrokeCount, 1);
    expect(missed, 1);
  });
}
