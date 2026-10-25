import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/core/clock.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/input/hold_to_straighten.dart';
import 'package:len/ink/input/ink_input_controller.dart';
import 'package:len/ink/input/live_ink.dart';
import 'package:len/ink/selection/ink_clipboard.dart';
import 'package:len/ink/selection/selection_chrome.dart';
import 'package:len/ink/shapes/bezier.dart';
import 'package:len/ink/shapes/curve_recognizer.dart';
import 'package:len/ink/shapes/kappa_curve.dart';
import 'package:len/ink/shapes/polyline.dart';
import 'package:len/ink/shapes/shape_builder.dart';
import 'package:len/ink/shapes/shape_handles.dart';
import 'package:len/ink/shapes/shape_recognizer.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ink/tools/content_tools.dart';
import 'package:len/ink/viewport.dart';

import 'support/hand_shapes.dart';

/// Curves: Bézier maths, fitting, recognition from a held pen, the Shape
/// tool placing anchors, and editing anchors and tangents on selection.

class _Clock extends Clock {
  int now = 1000000;
  int _ids = 0;

  @override
  int nowMs() => now;

  @override
  String newId() => 'id${_ids++}';
}

/// The largest distance from any of [points] to polyline [line].
double _farthest(List<Offset> points, List<Offset> line) {
  var worst = 0.0;
  for (final p in points) {
    var near = double.infinity;
    for (var i = 1; i < line.length; i++) {
      near = math.min(near, Polyline.distanceToSegment(p, line[i - 1], line[i]));
    }
    worst = math.max(worst, near);
  }
  return worst;
}

final _open = ShapeGeometry(ShapeKind.curve, const [
  Offset(0, 0),
  Offset(50, -60),
  Offset(100, -60),
  Offset(150, 0),
  Offset(200, 60),
  Offset(250, 60),
  Offset(300, 0),
]);

void main() {
  group('Bezier', () {
    test('splitting adds an anchor and keeps the outline', () {
      final before = Bezier.flatten(_open.points, closed: false, spacing: 0.5);
      final split = Bezier.split(_open.points, 1, 0.3, closed: false);
      expect(split, hasLength(10));
      final after = Bezier.flatten(split, closed: false, spacing: 0.5);
      expect(_farthest(after, before), lessThan(0.2));
      expect(
        split[6],
        offsetMoreOrLessEquals(
          Bezier.cubicAt(_open.points[3], _open.points[4], _open.points[5], _open.points[6], 0.3),
        ),
      );
      // Closed: the last segment (back to the first anchor) splits too.
      final closed = [..._open.points, const Offset(300, 100), const Offset(0, 100)];
      final split2 = Bezier.split(closed, 2, 0.5, closed: true);
      expect(split2, hasLength(12));
      expect(ShapeGeometry(ShapeKind.curve, split2).isClosed, isTrue);
    });

    test('removing an anchor joins its neighbours', () {
      expect(Bezier.removeAnchor(_open.points, 1, closed: false), [
        _open.points[0],
        _open.points[1],
        _open.points[5],
        _open.points[6],
      ]);
      expect(Bezier.removeAnchor(_open.points, 0, closed: false), _open.points.sublist(3));
      expect(Bezier.removeAnchor(_open.points, 2, closed: false), _open.points.sublist(0, 4));
      final closed = [..._open.points, const Offset(300, 100), const Offset(0, 100)];
      final without = Bezier.removeAnchor(closed, 0, closed: true);
      expect(without, hasLength(6));
      expect(without.first, _open.points[3]);
    });

    test('the nearest point of a spline', () {
      const p = Offset(150, 3);
      final hit = Bezier.nearest(_open.points, p, closed: false);
      expect(hit.distance, lessThan(3));
      final q = _open.points.sublist(3 * hit.segment, 3 * hit.segment + 4);
      expect((Bezier.cubicAt(q[0], q[1], q[2], q[3], hit.t) - p).distance, hit.distance);
      // No point of the outline is nearer.
      final outline = Bezier.flatten(_open.points, closed: false, spacing: 0.25);
      expect(
        outline.map((o) => (o - p).distance).reduce(math.min),
        greaterThan(hit.distance - 0.01),
      );
    });
  });

  group('CurveRecognizer', () {
    List<Offset> scaled(List<Offset> p, double s) => [for (final q in p) q * s];

    test('smooth held strokes become curves near what was drawn', () {
      for (var seed = 0; seed < 6; seed++) {
        final h = HandShapes(seed);
        final cases = [
          h.curve(const [Offset(100, 300), Offset(250, 150), Offset(400, 300)]), // an arc
          h.curve(const [Offset(100, 300), Offset(200, 200), Offset(300, 300), Offset(400, 200)]),
          // An egg (closed: as a hold it is an ellipse first).
          h.curve([
            for (var i = 0; i < 16; i++)
              const Offset(300, 300) +
                  Offset.fromDirection(
                    i / 16 * 2 * math.pi,
                    150 *
                        (1 +
                            0.3 * math.cos(i / 16 * 2 * math.pi) +
                            0.15 * math.cos(2 * i / 16 * 2 * math.pi + 1)),
                  ),
          ], closed: true),
        ];
        for (final (i, pts) in cases.indexed) {
          if (i < 2) expect(ShapeRecognizer.recognize(pts), isNull, reason: 'case $i seed $seed');
          final curve = CurveRecognizer.recognize(pts);
          expect(curve?.kind, ShapeKind.curve, reason: 'case $i seed $seed');
          expect(curve!.isClosed, i == 2, reason: 'case $i seed $seed');
          final size = Polyline.bounds(pts).longestSide;
          final outline = ShapeBuilder.outline(curve);
          expect(_farthest(pts.sublist(3), outline), lessThan(0.05 * size), reason: '$i $seed');
          expect(_farthest(outline, pts), lessThan(0.05 * size), reason: '$i $seed');
        }
      }
    });

    test('corners, loops, zig-zags, spirals and scribbles are no curve', () {
      final h = HandShapes(1);
      final corner = h.curve(const [Offset(0, 0), Offset(100, 100)])
        ..addAll(h.curve(const [Offset(100, 100), Offset(200, 0)]).skip(1));
      expect(CurveRecognizer.recognize(corner), isNull);
      final loop = [
        for (var i = 0; i <= 120; i++)
          Offset(
            i * 2 + 60 * math.cos(i / 120 * 2 * math.pi),
            60 * math.sin(i / 120 * 2 * math.pi),
          ),
      ];
      expect(CurveRecognizer.recognize(loop), isNull);
      final zigzag = [
        for (var i = 0; i <= 120; i++) Offset(i * 2.0, 60 * (1 - ((i % 40) - 20).abs() / 20)),
      ];
      expect(CurveRecognizer.recognize(zigzag), isNull);
      final spiral = [
        for (var i = 0; i <= 200; i++) Offset.fromDirection(i / 200 * 5 * math.pi, 20 + i * 0.6),
      ];
      expect(CurveRecognizer.recognize(spiral), isNull);
      final wave = [
        for (var i = 0; i <= 200; i++) Offset(i * 2.0, 30 * math.sin(i / 200 * 8 * math.pi)),
      ];
      expect(CurveRecognizer.recognize(wave), isNull);
      final random = math.Random(3);
      var p = const Offset(200, 200);
      final scribble = [
        for (var i = 0; i < 200; i++)
          p += Offset(random.nextDouble() * 30 - 15, random.nextDouble() * 30 - 15),
      ];
      expect(CurveRecognizer.recognize(scribble), isNull);
    });

    test('handwriting held at any size never becomes a curve (only "o"s, a shape first)', () {
      for (var seed = 0; seed < 8; seed++) {
        for (final (i, word) in HandShapes.writing(Offset.zero, seed: seed).indexed) {
          for (final s in [1.0, 2.0, 4.0, 6.0]) {
            final pts = scaled(word, s);
            final shape = HoldToStraighten.snapOf([
              for (final q in pts) StrokePoint(q.dx, q.dy, 0.5),
            ], 1);
            expect(
              shape?.kind,
              anyOf(isNull, ShapeKind.circle, ShapeKind.ellipse),
              reason: 'word $i × $s seed $seed',
            );
          }
        }
      }
    });

    test('hold to snap makes a curve only at least minCurve across', () {
      final arc = HandShapes(2).curve(const [Offset(0, 100), Offset(60, 0), Offset(120, 100)]);
      final points = [for (final q in arc) StrokePoint(q.dx, q.dy, 0.5)];
      expect(HoldToStraighten.snapOf(points, 1), isNull); // 120 px across
      expect(HoldToStraighten.snapOf(points, 1.5)?.kind, ShapeKind.curve); // 180 px on screen
    });
  });

  group('curve handles', () {
    final closed = ShapeGeometry(ShapeKind.curve, const [
      Offset(0, 0),
      Offset(50, -50),
      Offset(150, -50),
      Offset(200, 0),
      Offset(250, 50),
      Offset(-50, 50),
    ]);

    test('anchors and tangents, by role, the tangents with their anchors', () {
      final handles = ShapeHandles.of(closed);
      expect(
        [for (final h in handles) h.role],
        [
          HandleRole.vertex,
          HandleRole.tangent,
          HandleRole.tangent,
          HandleRole.vertex,
          HandleRole.tangent,
          HandleRole.tangent,
        ],
      );
      expect(handles[1].anchor, const Offset(0, 0));
      expect(handles[2].anchor, const Offset(200, 0));
      expect(handles[5].anchor, const Offset(0, 0)); // the first anchor's in handle
    });

    test('an anchor moves with its tangents, lining up with the others', () {
      final moved = ShapeHandles.drag(closed, 3, const Offset(220, 3), snap: 5);
      expect(moved.points[3], const Offset(220, 0));
      expect(moved.points[2], const Offset(170, -50));
      expect(moved.points[4], const Offset(270, 50));
      expect(ShapeHandles.drag(closed, 0, const Offset(10, 10)).points[5], const Offset(-40, 60));
    });

    test('a smooth anchor stays smooth; a corner tangent snaps to its anchor', () {
      // The first anchor's tangents are in line (out (50,-50), in (-50,50)).
      final turned = ShapeHandles.drag(closed, 1, const Offset(0, -80));
      expect(turned.points[1], const Offset(0, -80));
      expect(turned.points[5].dx, closeTo(0, 1e-9));
      expect(turned.points[5].dy, closeTo((const Offset(-50, 50)).distance, 1e-9));
      final corner = ShapeHandles.drag(closed, 1, const Offset(3, -2), snap: 5);
      expect(corner.points[1], Offset.zero);
      // Shift: 15° steps from the anchor.
      final stepped = ShapeHandles.drag(closed, 1, Offset.fromDirection(0.3, 70), shift: true);
      expect((stepped.points[1]).direction, closeTo(math.pi / 12, 1e-9));
    });
  });

  group('the Shape tool draws curves', () {
    late AppDatabase db;
    late SurfaceModel model;
    late ViewportController viewport;
    late ToolSettings tools;
    late LiveInk live;
    late ContentTools content;
    late InkInputController input;
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
      clock.now += 1000; // taps apart, not double taps
    }

    List<Stroke> strokes() => [...model.strokesNear(const Rect.fromLTWH(-1000, -1000, 3000, 3000))];

    test('taps place points it passes through, a drag places one where it ends, a tap on the '
        'last makes it a corner; a double tap finishes it open', () {
      drag([const Offset(100, 300)]);
      expect(live.isDrawing, isTrue);
      expect(strokes(), isEmpty);
      drag([const Offset(250, 200), const Offset(270, 200), const Offset(300, 200)]);
      expect(live.shape?.through, const [Offset(100, 300), Offset(300, 200)]);
      drag([const Offset(400, 300)]);
      // A tap on the last point (not a double tap): a corner there.
      drag([const Offset(401, 301)]);
      expect(live.shape!.through, hasLength(3));
      drag([const Offset(500, 200)]);
      // A second tap on the last point, quickly: finished.
      clock.now -= 1000;
      clock.now += 200;
      drag([const Offset(501, 201)]);
      expect(live.isDrawing, isFalse);
      final curve = strokes().single;
      final shape = curve.shape!;
      expect(shape.kind, ShapeKind.curve);
      expect(shape.isClosed, isFalse);
      const through = [Offset(100, 300), Offset(300, 200), Offset(400, 300), Offset(500, 200)];
      expect(shape.through, through);
      expect(shape.corners, [2]);
      expect(shape.points, KappaCurve.spline(through, closed: false, corners: const [2]));
      // It passes through every point; the corner is an anchor of its spline.
      final line = Bezier.flatten(shape.points, closed: false, spacing: 0.25);
      expect(_farthest(through, line), lessThan(0.1));
      expect(shape.points, contains(const Offset(400, 300)));
      expect(curve.points, ShapeBuilder.pointsOf(shape, spacing: 2));
      expect(curve.fill, isNull);
      // One undo step.
      model.undo();
      expect(strokes(), isEmpty);
    });

    test('a tap on the first point closes it, with the tool\'s fill', () {
      tools.shapeFill = const ShapeFill.tint(0.25);
      drag([const Offset(100, 300)]);
      drag([const Offset(300, 100)]);
      drag([const Offset(500, 300)]);
      drag([const Offset(103, 302)]);
      final curve = strokes().single;
      expect(curve.shape!.isClosed, isTrue);
      expect(curve.shape!.anchorCount, 3);
      expect(curve.isClosed, isTrue);
      expect(curve.fill, isNotNull);
    });

    test('Enter or another tool finishes, Escape drops, a pinch keeps what was placed', () {
      drag([const Offset(100, 300)]);
      drag([const Offset(300, 100)]);
      expect(content.shape.finishCurve(), isTrue);
      expect(strokes(), hasLength(1));
      expect(content.shape.finishCurve(), isFalse);
      drag([const Offset(100, 400)]);
      drag([const Offset(300, 500)]);
      expect(content.shape.cancelCurve(), isTrue);
      expect(strokes(), hasLength(1));
      expect(live.isDrawing, isFalse);
      drag([const Offset(100, 400)]);
      drag([const Offset(300, 500)]);
      // A gesture abandoned (it became a pinch) drops only its own point.
      final id = ++pointer;
      input.handleDown(
        PointerDownEvent(
          pointer: id,
          kind: PointerDeviceKind.mouse,
          position: const Offset(500, 400),
        ),
      );
      content.shape.cancel();
      input.handleUp(
        PointerUpEvent(
          pointer: id,
          kind: PointerDeviceKind.mouse,
          position: const Offset(500, 400),
        ),
      );
      expect(live.shape?.anchorCount, 2);
      tools.tool = EditorTool.pen;
      expect(strokes(), hasLength(2));
      expect(strokes().last.shape!.anchorCount, 2);
    });
  });

  group('editing a selected curve', () {
    late AppDatabase db;
    late SurfaceModel model;
    late ViewportController viewport;
    late ContentTools content;
    late InkInputController input;
    late _Clock clock;
    var pointer = 0;

    setUp(() {
      db = AppDatabase.inMemory();
      model = SurfaceModel(
        surfaceId: 's',
        repository: StrokeRepository(db, deviceId: 'd'),
      );
      viewport = ViewportController()..setSize(const Size(800, 600));
      final tools = ToolSettings(stylusOnly: false)..tool = EditorTool.lasso;
      final live = LiveInk();
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
    });

    tearDown(() {
      content.dispose();
      model.dispose();
      db.close();
    });

    void tap(Offset at, {int after = 1000}) {
      final id = ++pointer;
      const k = PointerDeviceKind.mouse;
      input.handleDown(PointerDownEvent(pointer: id, kind: k, position: at));
      input.handleUp(PointerUpEvent(pointer: id, kind: k, position: at));
      clock.now += after;
    }

    test('a tap on the line adds an anchor (same outline); a double tap on one removes it', () {
      final shape = _open.map((p) => p + const Offset(100, 300));
      model.addStroke(
        Stroke(
          id: 'c',
          surfaceId: 's',
          tool: InkTool.ballpoint,
          color: 0xFF000000,
          width: 2,
          points: ShapeBuilder.pointsOf(shape),
          createdAt: 1,
          style: ShapeBuilder.styleFor(const StrokeStyle(unit: 1)),
          shape: shape,
        ),
      );
      model.history.takeUndo();
      // Selected by a tap on its line, near its first anchor's segment.
      final onLine = Bezier.cubicAt(
        shape.points[0],
        shape.points[1],
        shape.points[2],
        shape.points[3],
        0.5,
      );
      tap(onLine);
      expect(content.selection.shape, shape);
      // A tap on the line again: an anchor there.
      tap(onLine);
      final added = content.selection.shape!;
      expect(added.anchorCount, 4);
      expect(added.points[3], offsetMoreOrLessEquals(onLine, epsilon: 0.5));
      final before = Bezier.flatten(shape.points, closed: false, spacing: 0.5);
      expect(
        _farthest(Bezier.flatten(added.points, closed: false, spacing: 0.5), before),
        lessThan(0.3),
      );
      expect(model.history.canUndo, isTrue);
      // A double tap on that anchor removes it.
      final anchor = viewport.toScreen(added.points[3]);
      tap(anchor, after: 100);
      tap(anchor);
      expect(content.selection.shape!.anchorCount, 3);
      // Two steps back: as it was.
      model.undo();
      model.undo();
      expect(model.strokesNear(const Rect.fromLTWH(0, 0, 800, 600)).single.shape, shape);
    });

    test('a curve through points: its points are its handles; dragged, added, removed', () {
      const through = [Offset(100, 300), Offset(250, 180), Offset(400, 300), Offset(550, 200)];
      final shape = KappaCurve.geometry(through, closed: false);
      model.addStroke(
        Stroke(
          id: 'k',
          surfaceId: 's',
          tool: InkTool.ballpoint,
          color: 0xFF000000,
          width: 2,
          points: ShapeBuilder.pointsOf(shape),
          createdAt: 1,
          style: ShapeBuilder.styleFor(const StrokeStyle(unit: 1)),
          shape: shape,
        ),
      );
      model.history.takeUndo();
      tap(through[1]);
      expect(content.selection.shape, shape);
      expect([for (final h in ShapeHandles.of(shape)) h.at], through);
      // Its second point dragged: the curve runs through it there.
      final id = ++pointer;
      const k = PointerDeviceKind.mouse;
      input.handleDown(PointerDownEvent(pointer: id, kind: k, position: through[1]));
      input.handleMove(
        PointerMoveEvent(pointer: id, kind: k, position: through[1] + const Offset(10, -20)),
      );
      input.handleMove(
        PointerMoveEvent(pointer: id, kind: k, position: through[1] + const Offset(20, -40)),
      );
      input.handleUp(
        PointerUpEvent(pointer: id, kind: k, position: through[1] + const Offset(20, -40)),
      );
      clock.now += 1000;
      final moved = content.selection.shape!;
      expect(moved.through![1], through[1] + const Offset(20, -40));
      final line = Bezier.flatten(moved.points, closed: false, spacing: 0.25);
      expect(_farthest(moved.through!, line), lessThan(0.1));
      // A tap on its line, between the third and fourth points: a point there.
      final between = Bezier.nearest(moved.points, const Offset(480, 240), closed: false);
      final q = moved.points.sublist(3 * between.segment, 3 * between.segment + 4);
      final onLine = Bezier.cubicAt(q[0], q[1], q[2], q[3], between.t);
      tap(onLine);
      final added = content.selection.shape!;
      expect(added.through, hasLength(5));
      expect(added.through![3], offsetMoreOrLessEquals(onLine, epsilon: 0.5));
      // A double tap on it removes it again.
      tap(added.through![3], after: 100);
      tap(added.through![3]);
      expect(content.selection.shape!.through, hasLength(4));
      // Every edit one undo step: back to as it was.
      model
        ..undo()
        ..undo()
        ..undo();
      expect(model.strokesNear(const Rect.fromLTWH(0, 0, 800, 600)).single.shape, shape);
    });

    test('a corner\'s tangents show beside it and pull out from it, one undo step', () {
      // Three anchors placed by taps: corners, every tangent on its anchor.
      const a = Offset(100, 300), b = Offset(250, 200), c = Offset(400, 300);
      final shape = ShapeGeometry(ShapeKind.curve, const [a, a, b, b, b, c, c]);
      model.addStroke(
        Stroke(
          id: 'c',
          surfaceId: 's',
          tool: InkTool.ballpoint,
          color: 0xFF000000,
          width: 2,
          points: ShapeBuilder.pointsOf(shape),
          createdAt: 1,
          style: ShapeBuilder.styleFor(const StrokeStyle(unit: 1)),
          shape: shape,
        ),
      );
      model.history.takeUndo();
      tap((a + b) / 2);
      expect(content.selection.shape, shape);
      final shown = {for (final h in SelectionChrome.shapeHandles(shape, viewport)) h.index: h.at};
      // Every tangent, a fingertip from its anchor along its segment.
      expect(shown.keys, [0, 1, 2, 3, 4, 5, 6]);
      final out = shown[4]!;
      expect((out - b).distance, closeTo(SelectionChrome.crowd, 1e-9));
      expect((out - b).direction, closeTo((c - b).direction, 1e-9));
      // Pulled out from where it shows: it grows from its anchor, no jump.
      final id = ++pointer;
      const k = PointerDeviceKind.mouse;
      input.handleDown(PointerDownEvent(pointer: id, kind: k, position: out));
      input.handleMove(PointerMoveEvent(pointer: id, kind: k, position: out + const Offset(40, 0)));
      input.handleMove(PointerMoveEvent(pointer: id, kind: k, position: out + const Offset(60, 0)));
      input.handleUp(PointerUpEvent(pointer: id, kind: k, position: out + const Offset(60, 0)));
      final pulled = content.selection.shape!;
      expect(pulled.points[4], offsetMoreOrLessEquals(b + const Offset(60, 0)));
      expect(pulled.points[2], b); // the other tangent stays (a corner)
      expect(model.history.takeUndo()!.added.single.shape, pulled);
      expect(model.history.canUndo, isFalse);
    });
  });
}
