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

    test('a circle by its centre and radius, an ellipse by its centre and two radii', () {
      final circle = ShapeBuilder.dragged(ShapeKind.ellipse, Offset.zero, const Offset(100, 100));
      expect(circle.kind, ShapeKind.circle);
      expect(
        [for (final h in ShapeHandles.of(circle)) h.role],
        [HandleRole.centre, HandleRole.radius],
      );
      // The centre moves it; the radius sizes it about the centre.
      final moved = ShapeHandles.drag(circle, 0, const Offset(70, 50));
      expect(moved.points, const [Offset(70, 50), Offset(120, 50)]);
      final bigger = ShapeHandles.drag(circle, 1, const Offset(50, 130));
      expect(bigger.points[0], const Offset(50, 50));
      expect((bigger.points[1] - bigger.points[0]).distance, 80);
      // Shift: along the radius only.
      final along = ShapeHandles.drag(circle, 1, const Offset(150, 70), shift: true);
      expect(along.points[1], const Offset(150, 50));

      final ellipse = ShapeBuilder.dragged(ShapeKind.ellipse, Offset.zero, const Offset(100, 60));
      final handles = ShapeHandles.of(ellipse);
      expect(
        [for (final h in handles) h.at],
        const [Offset(50, 30), Offset(100, 30), Offset(50, 60)],
      );
      // A radius changes one axis about the fixed centre, wherever the
      // pointer goes sideways.
      final wide = ShapeHandles.drag(ellipse, 1, const Offset(150, 45));
      expect(wide.points, const [Offset(50, 30), Offset(150, 30), Offset(50, 60)]);
      // Shift keeps the proportions.
      final both = ShapeHandles.drag(ellipse, 1, const Offset(150, 30), shift: true);
      expect(both.points, const [Offset(50, 30), Offset(150, 30), Offset(50, 90)]);
      // Nearly equal radii snap equal.
      final round = ShapeHandles.drag(ellipse, 1, const Offset(81, 30), snap: 8);
      expect(round.points[1], const Offset(80, 30));
      expect(ShapeHandles.drag(ellipse, 1, const Offset(81, 30)).points[1], const Offset(81, 30));
    });

    test('a star sizes and turns by its point, its inner radius by the dot', () {
      final star = ShapeBuilder.dragged(ShapeKind.star, Offset.zero, const Offset(100, 100));
      final handles = ShapeHandles.of(star);
      expect(
        [for (final h in handles) h.role],
        [HandleRole.centre, HandleRole.radius, HandleRole.inner],
      );
      final c = star.points[0];
      final top = handles[1].at;
      // Drag the top point to the right of the centre, twice as far.
      final turned = ShapeHandles.drag(star, 1, c + Offset((top - c).distance * 2, 0));
      expect(
        ShapeHandles.of(turned)[1].at,
        offsetMoreOrLessEquals(c + Offset((top - c).distance * 2, 0)),
      );
      expect(turned.inner, star.inner);
      expect(turned.points[0], c);
      // Turns near 15° steps snap; Shift keeps to them.
      final near = c + Offset.fromDirection(-math.pi / 2 + 0.27, 50);
      final snapped = ShapeHandles.of(ShapeHandles.drag(star, 1, near, snap: 4))[1].at - c;
      expect(snapped.direction, closeTo(-math.pi / 2 + math.pi / 12, 1e-9));
      final free = ShapeHandles.of(ShapeHandles.drag(star, 1, near))[1].at - c;
      expect(free.direction, closeTo(-math.pi / 2 + 0.27, 1e-9));
      // The inner dot pulled out to 70 % of the outer radius.
      final fat = ShapeHandles.drag(star, 2, Offset.lerp(c, handles[2].at, 0.7 / star.inner)!);
      expect(fat.inner, closeTo(0.7, 1e-9));
      expect(ShapeHandles.drag(star, 2, c).inner, ShapeGeometry.minInner);
      // Near a regular star's, it snaps to it.
      final regular = ShapeHandles.drag(
        star,
        2,
        Offset.lerp(c, handles[2].at, 0.39 / star.inner)!,
        snap: 4,
      );
      expect(regular.inner, closeTo(math.cos(0.4 * math.pi) / math.cos(0.2 * math.pi), 1e-9));
      // The centre moves it.
      expect(
        ShapeHandles.drag(star, 0, c + const Offset(5, 5)),
        star.map((p) => p + const Offset(5, 5)),
      );
    });

    test('a star of other points', () {
      final star = ShapeBuilder.dragged(
        ShapeKind.star,
        Offset.zero,
        const Offset(100, 100),
      ).withStar(tips: 7);
      expect(ShapeBuilder.starVertices(star), hasLength(14));
      expect(ShapeBuilder.outline(star), hasLength(15));
    });

    test('a rectangle side moves that side; Shift keeps proportions', () {
      final rect = ShapeBuilder.dragged(ShapeKind.rectangle, Offset.zero, const Offset(100, 60));
      final handles = ShapeHandles.of(rect);
      expect(
        [for (final h in handles.skip(4)) h.at],
        const [Offset(50, 0), Offset(100, 30), Offset(50, 60), Offset(0, 30)],
      );
      expect(
        [for (final h in handles) h.role],
        [
          for (var i = 0; i < 4; i++) HandleRole.vertex,
          for (var i = 0; i < 4; i++) HandleRole.edge,
        ],
      );
      // The right side, dragged out (and a bit down: only across counts).
      expect(ShapeHandles.drag(rect, 5, const Offset(140, 50)).points, const [
        Offset(0, 0),
        Offset(140, 0),
        Offset(140, 60),
        Offset(0, 60),
      ]);
      // Nearly square snaps square.
      expect(
        ShapeHandles.drag(rect, 5, const Offset(62, 30), snap: 8).points[1],
        const Offset(60, 0),
      );
      // Shift: twice as wide, twice as tall about the left side's middle.
      expect(ShapeHandles.drag(rect, 5, const Offset(200, 30), shift: true).points, const [
        Offset(0, -30),
        Offset(200, -30),
        Offset(200, 90),
        Offset(0, 90),
      ]);
    });

    test('a diamond keeps its axes: vertices along them, sides size it', () {
      final diamond = ShapeBuilder.dragged(ShapeKind.diamond, Offset.zero, const Offset(100, 60));
      // The top vertex up: the bottom one stays, the sides follow.
      expect(ShapeHandles.drag(diamond, 0, const Offset(60, -40)).points, const [
        Offset(50, -40),
        Offset(100, 10),
        Offset(50, 60),
        Offset(0, 10),
      ]);
      // The middle of the top-right side out: the bottom-left side stays.
      final mid = ShapeHandles.of(diamond)[4].at;
      expect(mid, const Offset(75, 15));
      final grown = ShapeHandles.drag(diamond, 4, mid + const Offset(30, -15));
      expect(ShapeHandles.of(grown)[4].at, offsetMoreOrLessEquals(mid + const Offset(30, -15)));
      expect(grown.points[2].dy, closeTo(60, 1e-9));
      expect(grown.points[3].dx, closeTo(0, 1e-9));
    });

    test('a line bends by its middle, straight again near it, Shift: a symmetric arc', () {
      final line = ShapeGeometry(ShapeKind.line, const [Offset.zero, Offset(100, 0)]);
      expect(ShapeHandles.of(line)[2].at, const Offset(50, 0));
      final bent = ShapeHandles.drag(line, 2, const Offset(60, 30));
      expect(bent.isBent, isTrue);
      expect(bent.points[2], const Offset(60, 30));
      expect(
        ShapeHandles.drag(line, 2, const Offset(60, 30), shift: true).points[2],
        const Offset(50, 30),
      );
      expect(ShapeHandles.drag(bent, 2, const Offset(53, 4), snap: 8).isBent, isFalse);
      // The outline passes through the bend.
      final outline = ShapeBuilder.outline(bent);
      expect(outline.any((p) => (p - const Offset(60, 30)).distance < 1), isTrue);
      // Moving an end keeps the bend where it was on the curve.
      final longer = ShapeHandles.drag(bent, 1, const Offset(200, 0));
      expect(longer.points[2], offsetMoreOrLessEquals(const Offset(120, 60)));
      // An end near a 15° step snaps there.
      final end = ShapeHandles.drag(line, 1, Offset.fromDirection(0.27, 100), snap: 8).points[1];
      expect(end.direction, closeTo(math.pi / 12, 1e-9));
    });

    test('vertices line up with the others; Shift keeps one to an axis', () {
      final tri = ShapeGeometry(ShapeKind.triangle, const [
        Offset(0, 0),
        Offset(100, 10),
        Offset(30, 80),
      ]);
      expect(
        ShapeHandles.drag(tri, 2, const Offset(97, 83), snap: 5).points[2],
        const Offset(100, 83),
      );
      expect(
        ShapeHandles.drag(tri, 1, const Offset(150, 14), shift: true).points[1],
        offsetMoreOrLessEquals(const Offset(150, 10)),
      );
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
    final dot = ShapeHandles.of(star.shape!)[2].at;
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
    // Style sets its points: one undoable edit each.
    await tester.tap(find.byTooltip('Style'));
    await tester.pumpAndSettle();
    expect(find.text('Points'), findsOneWidget);
    await tester.tap(find.byTooltip('More points'));
    await tester.pumpAndSettle();
    final six = liveStrokes(services, nb.id).singleWhere((s) => s.shape?.kind == ShapeKind.star);
    expect(six.shape!.tips, 6);
    expect(six.shape!.inner, thin.shape!.inner);
    expect(ShapeBuilder.starVertices(six.shape!), hasLength(12));
  });
}
