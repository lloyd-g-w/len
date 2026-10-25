import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/core/clock.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/editor/document/undo_target.dart';
import 'package:len/ink/input/ink_input_controller.dart';
import 'package:len/ink/input/live_ink.dart';
import 'package:len/ink/selection/ink_clipboard.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ink/tools/content_tools.dart';
import 'package:len/ink/viewport.dart';

/// Drawing a curve with the Shape tool: the editor's undo and redo step
/// through its anchors while it is drawn, and taps on shapes select them.
class _Clock extends Clock {
  int now = 1000000;
  int _ids = 0;

  @override
  int nowMs() => now;

  @override
  String newId() => 'id${_ids++}';
}

void main() {
  late AppDatabase db;
  late SurfaceModel model;
  late ViewportController viewport;
  late ToolSettings tools;
  late LiveInk live;
  late ContentTools content;
  late InkInputController input;
  late EditingUndo undo;
  late _Clock clock;
  var pointer = 0;

  setUp(() {
    db = AppDatabase.inMemory();
    model = SurfaceModel(
      surfaceId: 's',
      repository: StrokeRepository(db, deviceId: 'd'),
    );
    viewport = ViewportController()..setSize(const Size(800, 600));
    tools = ToolSettings(stylusOnly: false)
      ..tool = EditorTool.shape
      ..shape = ShapeKind.curve;
    live = LiveInk();
    clock = _Clock();
    content = ContentTools(
      model: model,
      viewport: viewport,
      tools: tools,
      live: live,
      clipboard: InkClipboard(),
      clock: clock,
    );
    input = InkInputController(
      model: model,
      viewport: viewport,
      tools: tools,
      live: live,
      content: content,
    );
    undo = EditingUndo(SurfaceUndo(model), content.text, curve: content.shape.curve);
  });

  tearDown(() {
    undo.dispose();
    content.dispose();
    model.dispose();
    db.close();
  });

  void drag(List<Offset> path) {
    final id = ++pointer;
    const kind = PointerDeviceKind.mouse;
    input.handleDown(PointerDownEvent(pointer: id, kind: kind, position: path.first));
    for (final p in path.skip(1)) {
      input.handleMove(PointerMoveEvent(pointer: id, kind: kind, position: p));
    }
    input.handleUp(PointerUpEvent(pointer: id, kind: kind, position: path.last));
    clock.now += 1000; // taps apart, not double taps
  }

  List<Stroke> strokes() => [...model.strokesNear(const Rect.fromLTWH(-1000, -1000, 3000, 3000))];

  /// A rectangle drawn first, with the Shape tool.
  Stroke rectangle() {
    tools.shape = ShapeKind.rectangle;
    drag(const [Offset(500, 400), Offset(600, 400), Offset(700, 500)]);
    tools.shape = ShapeKind.curve;
    return strokes().single;
  }

  test('undo takes back the last point while a curve is drawn; redo puts it back', () {
    final rect = rectangle();
    var notified = 0;
    undo.addListener(() => notified++);
    drag(const [Offset(100, 300)]);
    drag(const [Offset(250, 200), Offset(270, 200), Offset(300, 200)]);
    drag(const [Offset(400, 300)]);
    final three = live.shape!;
    expect(three.through, const [Offset(100, 300), Offset(300, 200), Offset(400, 300)]);
    expect(undo.canUndo, isTrue);
    expect(undo.canRedo, isFalse);
    expect(notified, greaterThan(0));

    undo.undo();
    expect(live.shape!.through, three.through!.sublist(0, 2));
    expect(strokes(), [rect], reason: 'earlier strokes are untouched');
    expect(undo.canRedo, isTrue);
    undo.redo();
    expect(live.shape, three);
    expect(undo.canRedo, isFalse);

    undo
      ..undo()
      ..undo();
    expect(live.shape, isNull, reason: 'one point: a dot');
    expect(live.isDrawing, isTrue);
    undo.redo();
    expect(live.shape!.through, three.through!.sublist(0, 2));

    // A new point drops what was undone.
    undo.undo();
    drag(const [Offset(200, 400)]);
    expect(undo.canRedo, isFalse);
    expect(live.shape!.through, const [Offset(100, 300), Offset(200, 400)]);

    // Making a point a corner is a step of its own.
    drag(const [Offset(201, 401)]);
    drag(const [Offset(300, 300)]);
    expect(live.shape!.corners, [1]);
    undo
      ..undo()
      ..undo();
    expect(live.shape!.corners, isEmpty);
    expect(live.shape!.through, hasLength(2));
  });

  test('undoing the first anchor drops the curve; redo brings it back until something else', () {
    final rect = rectangle();
    drag(const [Offset(100, 300)]);
    drag(const [Offset(300, 100)]);
    undo
      ..undo()
      ..undo();
    expect(live.isDrawing, isFalse);
    expect(content.shape.curve.active, isFalse);
    expect(strokes(), [rect]);
    expect(undo.canRedo, isTrue);
    undo.redo();
    expect(live.isDrawing, isTrue);
    expect(live.shape, isNull);
    undo.redo();
    expect(live.shape!.anchorCount, 2);
    // Finished: one stroke, one undo step, then the rectangle's.
    expect(content.shape.finishCurve(), isTrue);
    expect(strokes(), hasLength(2));
    undo.undo();
    expect(strokes(), [rect]);
    undo.undo();
    expect(strokes(), isEmpty);

    // Dropped, then something else drawn: redo is the stroke's again.
    undo.redo();
    drag(const [Offset(100, 300)]);
    undo.undo();
    expect(undo.canRedo, isTrue);
    tools.shape = ShapeKind.rectangle;
    drag(const [Offset(100, 100), Offset(150, 150), Offset(200, 200)]);
    expect(undo.canRedo, isFalse);
  });

  test('undo mid-gesture takes back the point being placed', () {
    drag(const [Offset(100, 300)]);
    drag(const [Offset(300, 100)]);
    final id = ++pointer;
    const kind = PointerDeviceKind.mouse;
    input.handleDown(PointerDownEvent(pointer: id, kind: kind, position: const Offset(500, 300)));
    input.handleMove(PointerMoveEvent(pointer: id, kind: kind, position: const Offset(540, 300)));
    expect(live.shape!.through, hasLength(3));
    expect(live.shape!.through!.last, const Offset(540, 300));
    undo.undo();
    expect(live.shape!.through, hasLength(2));
    input.handleMove(PointerMoveEvent(pointer: id, kind: kind, position: const Offset(580, 300)));
    input.handleUp(PointerUpEvent(pointer: id, kind: kind, position: const Offset(580, 300)));
    expect(live.shape!.through, hasLength(2));
    expect(undo.canRedo, isFalse);
  });

  test('a tap right after an undo on the last anchor places one, not a double tap', () {
    drag(const [Offset(100, 300)]);
    drag(const [Offset(300, 100)]);
    drag(const [Offset(500, 300)]);
    clock.now -= 900;
    undo.undo();
    drag(const [Offset(300, 100)]); // where the last anchor now is, quickly
    expect(content.shape.curve.active, isTrue);
    expect(strokes(), isEmpty);
  });

  test('with Curve picked a tap on a shape selects it; a drag from it starts a curve', () {
    final rect = rectangle();
    drag(const [Offset(600, 400)]); // on its top side
    expect(content.selection.strokes.single.id, rect.id);
    expect(content.shape.curve.active, isFalse);
    expect(live.isDrawing, isFalse);
    content.selection.clear();

    // A drag from the outline: the first point, where the drag ends.
    drag(const [Offset(700, 450), Offset(710, 450), Offset(740, 450)]);
    expect(content.selection.isEmpty, isTrue);
    expect(content.shape.curve.active, isTrue);
    // Mid-curve, taps on the shape place points.
    drag(const [Offset(600, 500)]);
    final shape = live.shape!;
    expect(shape.through, const [Offset(740, 450), Offset(600, 500)]);
    expect(content.selection.isEmpty, isTrue);
  });
}
