import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/input/ink_input_controller.dart';
import 'package:len/ink/input/live_ink.dart';
import 'package:len/ink/selection/ink_clipboard.dart';
import 'package:len/ink/shapes/shape_builder.dart';
import 'package:len/ink/shapes/shape_handles.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ink/tools/content_tools.dart';
import 'package:len/ink/viewport.dart';

import 'shape_geometry_test.dart' show shapeStroke;

// Dragging a selected shape's handles on turned and zoomed shapes, with
// undo / redo, and what a press near them grabs.

double _cos(Offset a, Offset b) => (a.dx * b.dx + a.dy * b.dy) / (a.distance * b.distance);

Offset _turn(Offset p, Offset c, double a) {
  final d = p - c;
  return c +
      Offset(d.dx * math.cos(a) - d.dy * math.sin(a), d.dx * math.sin(a) + d.dy * math.cos(a));
}

void main() {
  late AppDatabase db;
  late StrokeRepository repository;
  late SurfaceModel model;
  late ViewportController viewport;
  late ContentTools content;
  late InkInputController input;
  var pointer = 0;

  setUp(() {
    db = AppDatabase.inMemory();
    repository = StrokeRepository(db, deviceId: 'd');
    model = SurfaceModel(surfaceId: 's', repository: repository);
    viewport = ViewportController()..setSize(const Size(800, 600));
    final tools = ToolSettings(stylusOnly: false)..tool = EditorTool.lasso;
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

  void drag(List<Offset> path, {PointerDeviceKind kind = PointerDeviceKind.stylus}) {
    final id = ++pointer;
    input.handleDown(PointerDownEvent(pointer: id, kind: kind, position: path.first));
    for (final p in path.skip(1)) {
      input.handleMove(PointerMoveEvent(pointer: id, kind: kind, position: p));
    }
    input.handleUp(PointerUpEvent(pointer: id, kind: kind, position: path.last));
  }

  var seeded = 0;
  Stroke seed(ShapeGeometry shape) {
    final stroke = shapeStroke(shape, id: 'shape${seeded++}', fill: 0x401C7ED6);
    model.addStroke(stroke);
    model.history.takeUndo(); // seeded, not an edit
    return stroke;
  }

  Offset screen(Offset world) => viewport.toScreen(world);

  test('a turned rectangle stays a rectangle at any zoom; undo and redo follow', () {
    viewport.setView(scale: 1.5, offset: const Offset(-40, 30));
    const c = Offset(200, 150);
    final rect = seed(
      ShapeBuilder.dragged(
        ShapeKind.rectangle,
        const Offset(120, 100),
        const Offset(280, 200),
      ).map((p) => _turn(p, c, 0.5)),
    );
    final corners = rect.shape!.points;
    drag([screen(Offset.lerp(corners[0], corners[1], 0.5)!)]); // selects it
    // Its frame turns with it: the corners (handles) sit just inside the frame's.
    final frame = content.selection.frame!;
    expect(frame.angle, closeTo(0.5, 1e-6));
    for (final (i, c) in frame.corners.indexed) {
      expect((c - corners[i]).distance, lessThan(20));
    }
    final corner = screen(corners[2]);
    drag([corner, corner + const Offset(20, 5), corner + const Offset(60, 10)]);
    final reshaped = content.selection.strokes.single;
    final p = reshaped.shape!.points;
    for (var i = 0; i < 4; i++) {
      expect(_cos(p[(i + 1) % 4] - p[i], p[(i + 3) % 4] - p[i]), closeTo(0, 1e-9));
    }
    expect(p[0], offsetMoreOrLessEquals(corners[0])); // the opposite corner stays
    expect(_cos(p[1] - p[0], corners[1] - corners[0]), closeTo(1, 1e-9)); // still turned
    expect(reshaped.fill, rect.fill);
    // One undo step back to the rectangle as it was; redo brings the new one.
    model.undo();
    final undone = model.strokesNear(const Rect.fromLTWH(0, 0, 600, 600)).single;
    expect(undone.shape, rect.shape);
    expect(content.selection.isEmpty, isTrue);
    model.redo();
    expect(model.strokesNear(const Rect.fromLTWH(0, 0, 600, 600)).single.shape, reshaped.shape);
    // The edit is pushed: the old stroke a tombstone, the new one with its geometry.
    final dirty = {for (final r in repository.dirtyRecords(10)) r.id: r};
    expect(dirty[rect.id]!.deleted, isTrue);
    expect((dirty[reshaped.id]!.data!['style'] as Map)['sh'], reshaped.shape!.toJson());
  });

  testWidgets('Shift keeps a corner on the diagonal: proportions kept', (tester) async {
    final ellipse = seed(
      ShapeBuilder.dragged(ShapeKind.ellipse, const Offset(100, 100), const Offset(300, 200)),
    );
    drag([const Offset(100, 150)]);
    final box = ShapeHandles.of(ellipse.shape!);
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    drag([box[2], box[2] + const Offset(10, 40), box[2] + const Offset(90, 70)]);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    final shape = content.selection.shape!;
    final u = shape.points[1] - shape.points[0], v = shape.points[2] - shape.points[0];
    expect(u.distance / v.distance, closeTo(2, 1e-9));
    expect(ShapeHandles.of(shape)[0], offsetMoreOrLessEquals(box[0]));
  });

  test('a finger reaches a handle from a fingertip away; small shapes still move', () {
    seed(ShapeBuilder.dragged(ShapeKind.triangle, const Offset(100, 100), const Offset(300, 300)));
    drag([const Offset(200, 300)], kind: PointerDeviceKind.touch);
    // 22 px off its bottom-right corner, outside the shape.
    drag([const Offset(322, 300), const Offset(362, 300)], kind: PointerDeviceKind.touch);
    expect(content.selection.shape!.points[1], const Offset(340, 300));
    model.undo();
    final small = seed(
      ShapeBuilder.dragged(ShapeKind.rectangle, const Offset(500, 100), const Offset(540, 130)),
    );
    expect(model.strokesNear(const Rect.fromLTWH(0, 0, 800, 600)).length, 2);
    drag([const Offset(500, 115)]);
    expect(content.selection.strokes.single.id, small.id);
    // A press 12 px in from a corner moves the small rectangle, not that corner.
    drag([const Offset(512, 112), const Offset(532, 112), const Offset(552, 112)]);
    expect(content.selection.shape, small.shape!.map((p) => p + const Offset(40, 0)));
  });

  test('a line moves from near it only; elsewhere in its box a press lassos', () {
    final line = seed(ShapeGeometry(ShapeKind.line, const [Offset(100, 100), Offset(500, 400)]));
    drag([const Offset(300, 250)]);
    expect(content.selection.strokes.single.id, line.id);
    expect(content.holds(const Offset(140, 360)), isFalse); // in its box, far from it
    expect(content.holds(const Offset(305, 245)), isTrue);
    drag([const Offset(305, 245), const Offset(325, 245), const Offset(345, 245)]);
    expect(content.selection.shape, line.shape!.map((p) => p + const Offset(40, 0)));
  });
}
