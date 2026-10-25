import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/input/ink_input_controller.dart';
import 'package:len/ink/input/live_ink.dart';
import 'package:len/ink/selection/ink_clipboard.dart';
import 'package:len/ink/selection/selection_chrome.dart';
import 'package:len/ink/selection/selection_cursors.dart';
import 'package:len/ink/selection/selection_frame.dart';
import 'package:len/ink/selection/selection_painter.dart';
import 'package:len/ink/shapes/shape_builder.dart';
import 'package:len/ink/shapes/shape_handles.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ink/tools/content_tools.dart';
import 'package:len/ink/viewport.dart';
import 'package:len/ui/design_tokens.dart';

import 'content_golden_test.dart' show seededCanvas;
import 'content_tools_ui_test.dart' show key;
import 'shape_geometry_test.dart' show shapeStroke;

/// The feel of shape handles: spread on tiny shapes, larger on touch,
/// mouse cursors saying what a press does, and a curve's anchors shown
/// while it is drawn.
void main() {
  late AppDatabase db;
  late SurfaceModel model;
  late ViewportController viewport;
  late ToolSettings tools;
  late ContentTools content;
  late InkInputController input;
  var pointer = 0;

  setUp(() {
    db = AppDatabase.inMemory();
    model = SurfaceModel(
      surfaceId: 's',
      repository: StrokeRepository(db, deviceId: 'd'),
    );
    viewport = ViewportController()..setSize(const Size(800, 600));
    tools = ToolSettings(stylusOnly: false)..tool = EditorTool.lasso;
    final live = LiveInk();
    content = ContentTools(
      model: model,
      viewport: viewport,
      tools: tools,
      live: live,
      clipboard: InkClipboard(),
    );
    input = InkInputController(
      model: model,
      viewport: viewport,
      tools: tools,
      live: live,
      content: content,
    );
  });

  tearDown(() {
    content.dispose();
    model.dispose();
    db.close();
  });

  void drag(List<Offset> path, {PointerDeviceKind kind = PointerDeviceKind.mouse}) {
    final id = ++pointer;
    input.handleDown(PointerDownEvent(pointer: id, kind: kind, position: path.first));
    for (final p in path.skip(1)) {
      input.handleMove(PointerMoveEvent(pointer: id, kind: kind, position: p));
    }
    input.handleUp(PointerUpEvent(pointer: id, kind: kind, position: path.last));
  }

  Stroke seed(ShapeGeometry shape) {
    final stroke = shapeStroke(shape, id: 'shape$pointer');
    model.addStroke(stroke);
    model.history.takeUndo();
    return stroke;
  }

  group('tiny shapes', () {
    test('their corners spread apart (alone), and pull their true corner without a jump', () {
      final rect = seed(
        ShapeBuilder.dragged(ShapeKind.rectangle, const Offset(100, 100), const Offset(124, 116)),
      );
      drag([const Offset(100, 108)]);
      expect(content.selection.shape, rect.shape);
      final shown = SelectionChrome.shapeHandles(rect.shape!, viewport);
      expect([for (final h in shown) h.index], [0, 1, 2, 3], reason: 'no sides');
      for (final a in shown) {
        for (final b in shown) {
          if (a != b) {
            expect((a.at - b.at).distance, greaterThanOrEqualTo(SelectionChrome.apart - 1e-9));
          }
        }
      }
      // Out from the middle, the way each corner lies.
      final top = shown[0].at;
      expect(top.dx, lessThan(100));
      expect(top.dy, lessThan(100));
      // Its middle still moves it.
      expect(
        SelectionChrome.shapeHandleAt(
          rect.shape!,
          viewport,
          const Offset(112, 108),
          frame: content.selection.frame,
          kind: PointerDeviceKind.mouse,
        ),
        isNull,
      );
      // The corner shown top left, dragged by (−20, −10): the true corner
      // moves as far.
      drag([top, top + const Offset(-10, -5), top + const Offset(-20, -10)]);
      final p = content.selection.shape!.points;
      expect(p[0], const Offset(80, 90));
      expect(p[2], const Offset(124, 116));
    });

    test('shapes large enough, and lines, keep their handles on their points', () {
      for (final shape in [
        ShapeBuilder.dragged(ShapeKind.rectangle, const Offset(100, 100), const Offset(200, 200)),
        ShapeBuilder.dragged(ShapeKind.arrow, const Offset(100, 100), const Offset(140, 100)),
        // Two anchors close together on a large curve.
        ShapeGeometry(ShapeKind.curve, const [
          Offset(100, 100),
          Offset(100, 100),
          Offset(110, 100),
          Offset(110, 100),
          Offset(300, 300),
          Offset(300, 300),
          Offset(400, 100),
        ]),
      ]) {
        final all = ShapeHandles.of(shape);
        for (final h in SelectionChrome.shapeHandles(shape, viewport)) {
          if (all[h.index].role.isPrimary) {
            expect(h.at, viewport.toScreen(all[h.index].at), reason: shape.kind.name);
          }
        }
      }
    });

    test('a short line\'s ends spread along it', () {
      final line = ShapeGeometry(ShapeKind.line, const [Offset(100, 100), Offset(110, 100)]);
      final shown = SelectionChrome.shapeHandles(line, viewport);
      expect(shown.map((h) => h.index), [0, 1]);
      expect(shown[0].at, const Offset(105 - SelectionChrome.apart / 2, 100));
      expect(shown[1].at, const Offset(105 + SelectionChrome.apart / 2, 100));
    });
  });

  group('mouse cursors', () {
    test('resize cursors follow the handle\'s direction, turned with the frame', () {
      expect(SelectionCursors.resize(SelectionHandle.right, 0), SystemMouseCursors.resizeLeftRight);
      expect(SelectionCursors.resize(SelectionHandle.top, 0), SystemMouseCursors.resizeUpDown);
      expect(
        SelectionCursors.resize(SelectionHandle.bottomRight, 0),
        SystemMouseCursors.resizeUpLeftDownRight,
      );
      expect(
        SelectionCursors.resize(SelectionHandle.topRight, 0),
        SystemMouseCursors.resizeUpRightDownLeft,
      );
      expect(
        SelectionCursors.resize(SelectionHandle.right, math.pi / 4),
        SystemMouseCursors.resizeUpLeftDownRight,
      );
      expect(
        SelectionCursors.resize(SelectionHandle.left, math.pi / 2),
        SystemMouseCursors.resizeUpDown,
      );
    });

    test('a shape\'s handles grab, its body moves, elsewhere draws; a press grabs on', () {
      final rect = seed(
        ShapeBuilder.dragged(ShapeKind.rectangle, const Offset(100, 100), const Offset(300, 200)),
      );
      void hover(Offset at) =>
          input.handleHover(PointerHoverEvent(kind: PointerDeviceKind.mouse, position: at));
      hover(const Offset(100, 100));
      expect(input.cursor.value, SystemMouseCursors.precise, reason: 'nothing selected');
      drag([const Offset(100, 150)]);
      expect(content.selection.shape, rect.shape);
      hover(const Offset(102, 101));
      expect(input.cursor.value, SystemMouseCursors.grab);
      hover(const Offset(200, 150));
      expect(input.cursor.value, SystemMouseCursors.move);
      final rotate = SelectionChrome.handles(
        content.selection.frame!,
        viewport,
        shape: rect.shape,
      )[SelectionHandle.rotate]!;
      hover(rotate);
      expect(input.cursor.value, SystemMouseCursors.grab);
      hover(const Offset(500, 400));
      expect(input.cursor.value, SystemMouseCursors.precise);
      // Grabbing while dragged, then over what is under the pointer.
      hover(const Offset(300, 200));
      input.handleDown(
        const PointerDownEvent(
          pointer: 99,
          kind: PointerDeviceKind.mouse,
          position: Offset(300, 200),
          buttons: kPrimaryMouseButton,
        ),
      );
      expect(input.cursor.value, SystemMouseCursors.grabbing);
      input.handleMove(
        const PointerMoveEvent(
          pointer: 99,
          kind: PointerDeviceKind.mouse,
          position: Offset(340, 230),
          buttons: kPrimaryMouseButton,
        ),
      );
      expect(input.cursor.value, SystemMouseCursors.grabbing);
      input.handleUp(
        const PointerUpEvent(
          pointer: 99,
          kind: PointerDeviceKind.mouse,
          position: Offset(340, 230),
        ),
      );
      expect(content.selection.shape!.points[2], const Offset(340, 230));
      expect(input.cursor.value, SystemMouseCursors.grab);
    });

    test('ink selected: its frame\'s handles resize; a curve\'s first anchor closes it', () {
      model.addStroke(
        Stroke(
          id: 'ink',
          surfaceId: 's',
          tool: InkTool.ballpoint,
          color: 0xFF000000,
          width: 3,
          points: [for (var x = 100.0; x <= 300; x += 5) StrokePoint(x, 200 + x / 4, 0.5)],
          createdAt: 1,
        ),
      );
      drag([const Offset(200, 250)]);
      final frame = content.selection.frame!;
      final handles = SelectionChrome.handles(frame, viewport);
      expect(
        content.cursorAt(EditorTool.lasso, handles[SelectionHandle.bottomRight]!),
        SystemMouseCursors.resizeUpLeftDownRight,
      );
      expect(
        content.cursorAt(EditorTool.lasso, handles[SelectionHandle.right]!),
        SystemMouseCursors.resizeLeftRight,
      );
      content.selection.clear();

      tools
        ..tool = EditorTool.shape
        ..shape = ShapeKind.curve;
      drag([const Offset(400, 400)]);
      expect(content.cursorAt(EditorTool.shape, const Offset(402, 401)), isNull, reason: 'one');
      drag([const Offset(600, 400)]);
      expect(content.cursorAt(EditorTool.shape, const Offset(402, 401)), isNull, reason: 'two');
      drag([const Offset(500, 500)]);
      expect(content.cursorAt(EditorTool.shape, const Offset(402, 401)), SystemMouseCursors.click);
      expect(content.cursorAt(EditorTool.shape, const Offset(500, 300)), isNull);
    });

    testWidgets('in the editor, the canvas shows them', (tester) async {
      await seededCanvas(tester);
      await key(tester, LogicalKeyboardKey.keyL);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      addTearDown(mouse.removePointer);
      await mouse.addPointer(location: const Offset(1200, 700));
      await tester.pump();
      MouseCursor cursor() => RendererBinding.instance.mouseTracker.debugDeviceActiveCursor(1)!;
      expect(cursor(), SystemMouseCursors.precise);
      await mouse.down(const Offset(1000, 172)); // the star's top point
      await mouse.up();
      await tester.pumpAndSettle();
      await mouse.moveTo(const Offset(1000, 250)); // its middle
      await tester.pump();
      expect(cursor(), SystemMouseCursors.grab, reason: 'its centre handle');
      await mouse.moveTo(const Offset(960, 300));
      await tester.pump();
      expect(cursor(), SystemMouseCursors.move);
    });
  });

  group('touch', () {
    testWidgets('handles are drawn larger on touch-first devices', (tester) async {
      SelectionPainter painter() => tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((p) => p.painter)
          .whereType<SelectionPainter>()
          .single;
      // Tests run as Android: touch-first unless told otherwise.
      Targets.debugTouchFirst = false;
      addTearDown(() => Targets.debugTouchFirst = null);
      await seededCanvas(tester);
      expect(painter().handleScale, 1);
      Targets.debugTouchFirst = true;
      // Rebuilt (a tool change rebuilds the content layer's painters).
      await key(tester, LogicalKeyboardKey.keyL);
      await tester.pumpAndSettle();
      expect(painter().handleScale, SelectionPainter.touchScale);
    });
  });

  group('drawing a curve', () {
    test('its points, the close target and its corners show; gone when done', () {
      tools
        ..tool = EditorTool.shape
        ..shape = ShapeKind.curve;
      final guide = content.shape.curve.guide;
      drag([const Offset(100, 300)]);
      expect(guide.value!.anchors, const [Offset(100, 300)]);
      expect(guide.value!.closes, isFalse);
      expect(guide.value!.tangents, isEmpty);
      // A press-drag places a point where it ends; the guide follows.
      final id = ++pointer;
      const k = PointerDeviceKind.mouse;
      input.handleDown(PointerDownEvent(pointer: id, kind: k, position: const Offset(300, 200)));
      input.handleMove(PointerMoveEvent(pointer: id, kind: k, position: const Offset(340, 200)));
      final dragged = guide.value!;
      expect(dragged.anchors, const [Offset(100, 300), Offset(340, 200)]);
      expect(dragged.closes, isFalse, reason: 'two points close nothing');
      input.handleUp(PointerUpEvent(pointer: id, kind: k, position: const Offset(340, 200)));
      drag([const Offset(341, 201)]); // the last point again: a corner
      expect(guide.value!.corners, [1]);
      drag([const Offset(500, 300)]);
      expect(guide.value!.closes, isTrue);
      expect(guide.value!.tangents, isEmpty);
      expect(content.shape.finishCurve(), isTrue);
      expect(guide.value, isNull);
    });
  });
}
