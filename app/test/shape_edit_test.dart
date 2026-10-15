import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/input/ink_input_controller.dart';
import 'package:len/ink/input/live_ink.dart';
import 'package:len/ink/selection/ink_clipboard.dart';
import 'package:len/ink/selection/selection_chrome.dart';
import 'package:len/ink/shapes/shape_builder.dart';
import 'package:len/ink/shapes/shape_handles.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ink/tools/content_tools.dart';
import 'package:len/ink/viewport.dart';

import 'content_golden_test.dart' show seededCanvas;
import 'content_tools_ui_test.dart' show key, liveStrokes;
import 'shape_geometry_test.dart' show shapeStroke;

double _cos(Offset a, Offset b) => (a.dx * b.dx + a.dy * b.dy) / (a.distance * b.distance);

void main() {
  group('ShapeHandles', () {
    test('a rectangle corner moves with the opposite one fixed, square corners kept', () {
      final rect = ShapeBuilder.dragged(ShapeKind.rectangle, Offset.zero, const Offset(100, 60));
      // Rotated by 30°, to check the sides keep their directions.
      final turned = rect.map(
        (p) => Offset(
          p.dx * math.cos(0.5) - p.dy * math.sin(0.5),
          p.dx * math.sin(0.5) + p.dy * math.cos(0.5),
        ),
      );
      for (final shape in [rect, turned]) {
        final moved = ShapeHandles.drag(shape, 2, shape.points[2] + const Offset(30, 25));
        expect(moved.points[0], shape.points[0]);
        expect(moved.points[2], shape.points[2] + const Offset(30, 25));
        for (var i = 0; i < 4; i++) {
          final a = moved.points[(i + 3) % 4] - moved.points[i];
          final b = moved.points[(i + 1) % 4] - moved.points[i];
          expect(_cos(a, b).abs(), lessThan(1e-9));
        }
        expect(
          _cos(moved.points[1] - moved.points[0], shape.points[1] - shape.points[0]),
          closeTo(1, 1e-9),
        );
      }
      // Dragged past the opposite corner, it flips; collapsed, it recovers.
      final flat = ShapeHandles.drag(rect, 2, const Offset(100, 0));
      final back = ShapeHandles.drag(flat, 2, const Offset(100, 60));
      expect(back, rect);
    });

    test('an ellipse is sized by its bounding corners', () {
      final ellipse = ShapeBuilder.dragged(ShapeKind.ellipse, Offset.zero, const Offset(100, 60));
      final handles = ShapeHandles.of(ellipse);
      expect(handles, const [Offset(0, 0), Offset(100, 0), Offset(100, 60), Offset(0, 60)]);
      final bigger = ShapeHandles.drag(ellipse, 2, const Offset(200, 100));
      expect(bigger, ShapeBuilder.dragged(ShapeKind.ellipse, Offset.zero, const Offset(200, 100)));
    });

    test('a star turns and sizes by its points, and its inner radius by the dot', () {
      final star = ShapeBuilder.dragged(ShapeKind.star, Offset.zero, const Offset(100, 100));
      final handles = ShapeHandles.of(star);
      expect(handles, hasLength(6));
      expect(ShapeHandles.isInner(star, 1), isTrue);
      final c = star.points[0];
      final top = handles[0];
      // Drag the top point to the right of the centre, twice as far.
      final turned = ShapeHandles.drag(star, 0, c + Offset((top - c).distance * 2, 0));
      expect(
        ShapeHandles.of(turned)[0],
        offsetMoreOrLessEquals(c + Offset((top - c).distance * 2, 0)),
      );
      expect(turned.inner, star.inner);
      expect(turned.points[0], c);
      // The inner dot pulled out to 70 % of the outer radius.
      final fat = ShapeHandles.drag(star, 1, Offset.lerp(c, handles[1], 0.7 / star.inner)!);
      expect(fat.inner, closeTo(0.7, 1e-9));
      expect(ShapeHandles.drag(star, 1, c).inner, ShapeGeometry.minInner);
    });

    test('line ends and polygon vertices move freely', () {
      final line = ShapeGeometry(ShapeKind.arrow, const [Offset.zero, Offset(100, 0)]);
      expect(ShapeHandles.drag(line, 1, const Offset(50, 50)).points, const [
        Offset.zero,
        Offset(50, 50),
      ]);
      final tri = ShapeBuilder.dragged(ShapeKind.triangle, Offset.zero, const Offset(100, 100));
      expect(ShapeHandles.drag(tri, 0, const Offset(0, -20)).points[0], const Offset(0, -20));
      expect(ShapeHandles.drag(tri, 0, const Offset(0, -20)).points[1], tri.points[1]);
    });
  });

  group('dragging a selected shape\'s points', () {
    late AppDatabase db;
    late SurfaceModel model;
    late ViewportController viewport;
    late ToolSettings tools;
    late ContentTools content;
    late InkInputController input;
    const k = PointerDeviceKind.stylus;
    var pointer = 0;

    setUp(() {
      db = AppDatabase.inMemory();
      model = SurfaceModel(
        surfaceId: 's',
        repository: StrokeRepository(db, deviceId: 'd'),
      );
      viewport = ViewportController()..setSize(const Size(800, 600));
      tools = ToolSettings(stylusOnly: true)..tool = EditorTool.lasso;
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

    void drag(List<Offset> path) {
      final id = ++pointer;
      input.handleDown(PointerDownEvent(pointer: id, kind: k, position: path.first));
      for (final p in path.skip(1)) {
        input.handleMove(PointerMoveEvent(pointer: id, kind: k, position: p));
      }
      input.handleUp(PointerUpEvent(pointer: id, kind: k, position: path.last));
    }

    for (final scale in [1.0, 2.0]) {
      test('reshape live, one undo step, fill kept, still selected (${scale}x)', () {
        viewport.setView(scale: scale, offset: const Offset(20, 10));
        final rect = shapeStroke(
          ShapeBuilder.dragged(ShapeKind.rectangle, const Offset(50, 50), const Offset(150, 110)),
          fill: 0x401C7ED6,
        );
        model.addStroke(rect);
        model.history.takeUndo(); // seeded, not an edit
        Offset screen(Offset world) => viewport.toScreen(world);
        drag([screen(const Offset(50, 80))]); // a tap on its left side selects it
        expect(content.selection.shape, rect.shape);
        final corner = screen(const Offset(150, 110));
        // Grabbed a little off the handle: the corner doesn't jump to the pointer.
        final id = ++pointer;
        input.handleDown(
          PointerDownEvent(pointer: id, kind: k, position: corner + const Offset(3, 2)),
        );
        input.handleMove(
          PointerMoveEvent(pointer: id, kind: k, position: corner + const Offset(43, 32)),
        );
        final live = content.selection.shape!;
        expect(
          live.points[2],
          offsetMoreOrLessEquals(const Offset(150, 110) + const Offset(40, 30) / scale),
        );
        expect(model.strokesNear(const Rect.fromLTWH(0, 0, 400, 400)).single.id, rect.id);
        input.handleMove(
          PointerMoveEvent(pointer: id, kind: k, position: corner + const Offset(83, 62)),
        );
        input.handleUp(
          PointerUpEvent(pointer: id, kind: k, position: corner + const Offset(83, 62)),
        );
        final edit = model.history.takeUndo()!;
        expect(edit.removed.single.id, rect.id);
        final reshaped = edit.added.single;
        expect(
          reshaped.shape!.points[2],
          offsetMoreOrLessEquals(const Offset(150, 110) + const Offset(80, 60) / scale),
        );
        expect(reshaped.shape!.points[0], const Offset(50, 50));
        expect(reshaped.fill, 0x401C7ED6);
        expect(reshaped.points, ShapeBuilder.pointsOf(reshaped.shape!, spacing: 2));
        expect(content.selection.strokes.single.id, reshaped.id);
        expect(model.history.canUndo, isFalse);
      });
    }

    test('arrow keys wait while a handle or the selection is dragged', () {
      final rect = shapeStroke(
        ShapeBuilder.dragged(ShapeKind.rectangle, const Offset(50, 50), const Offset(150, 110)),
      );
      model.addStroke(rect);
      model.history.takeUndo();
      drag([const Offset(50, 80)]);
      final id = ++pointer;
      input.handleDown(PointerDownEvent(pointer: id, kind: k, position: const Offset(150, 110)));
      input.handleMove(PointerMoveEvent(pointer: id, kind: k, position: const Offset(170, 120)));
      content.selection.nudge(const Offset(1, 0)); // An arrow key mid-drag.
      input.handleMove(PointerMoveEvent(pointer: id, kind: k, position: const Offset(190, 130)));
      input.handleUp(PointerUpEvent(pointer: id, kind: k, position: const Offset(190, 130)));
      final shape = model.strokesNear(const Rect.fromLTWH(0, 0, 400, 400)).single.shape!;
      expect(shape.points[0], const Offset(50, 50));
      expect(shape.points[2], const Offset(190, 130));
      expect(content.selection.shape, shape);
      expect(model.history.takeUndo(), isNotNull);
      expect(model.history.canUndo, isFalse, reason: 'the drag is one step, no nudge');
    });

    test('a press on a handle without moving changes nothing', () {
      final line = shapeStroke(
        ShapeGeometry(ShapeKind.line, const [Offset(100, 100), Offset(300, 100)]),
      );
      model.addStroke(line);
      model.history.takeUndo();
      drag([const Offset(200, 100)]);
      drag([const Offset(300, 100)]);
      expect(model.history.canUndo, isFalse);
      expect(content.selection.shape, line.shape);
      // A line has no frame handles: the ends do it all.
      final frame = content.selection.frame!;
      expect(SelectionChrome.handles(frame, viewport, shape: line.shape), isEmpty);
    });

    testWidgets('Shift keeps a line end on 15° steps', (tester) async {
      final line = shapeStroke(
        ShapeGeometry(ShapeKind.line, const [Offset(100, 100), Offset(300, 100)]),
      );
      model.addStroke(line);
      drag([const Offset(200, 100)]);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      drag([const Offset(300, 100), const Offset(310, 140), const Offset(300, 112)]);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      final end = content.selection.shape!.points[1];
      expect(end.dy, closeTo(100, 1e-9)); // 3.4° → 0°
      expect(end.dx, closeTo(100 + (const Offset(200, 12)).distance, 1e-9));
    });

    test('moving and rotating a shape keeps it editable', () {
      final tri = shapeStroke(
        ShapeBuilder.dragged(ShapeKind.triangle, const Offset(100, 100), const Offset(200, 200)),
      );
      model.addStroke(tri);
      drag([const Offset(150, 200)]);
      drag([const Offset(150, 180), const Offset(200, 200), const Offset(250, 230)]);
      final moved = content.selection.strokes.single;
      expect(moved.shape, tri.shape!.map((p) => p + const Offset(100, 50)));
      expect(content.selection.shape, moved.shape);
    });
  });

  testWidgets('a selected shape shows calm handles on its points', (tester) async {
    final (services, nb) = await seededCanvas(tester);
    await key(tester, LogicalKeyboardKey.keyL);
    // A tap on the star's top point selects it.
    final gesture = await tester.startGesture(
      const Offset(1000, 172),
      kind: PointerDeviceKind.mouse,
    );
    await gesture.up();
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(Directionality).first,
      matchesGoldenFile('goldens/content_shape_handles.png'),
    );
    // Its inner radius, dragged in: one synced edit with the fill kept.
    final star = liveStrokes(services, nb.id).singleWhere((s) => s.shape?.kind == ShapeKind.star);
    final dot = ShapeHandles.of(star.shape!)[1];
    final drag = await tester.startGesture(dot, kind: PointerDeviceKind.mouse);
    await drag.moveTo(Offset.lerp(dot, star.shape!.points[0], 0.5)!);
    await drag.up();
    await tester.pump();
    final thin = liveStrokes(services, nb.id).singleWhere((s) => s.shape?.kind == ShapeKind.star);
    expect(thin.id, isNot(star.id));
    expect(thin.shape!.inner, lessThan(star.shape!.inner * 0.6));
    expect(thin.fill, star.fill);
    final pushed = services.strokes.dirtyRecords(100).where((r) => r.id == thin.id).single;
    expect((pushed.data!['style'] as Map)['sh'], thin.shape!.toJson());
  });
}
