import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/element_repository.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/domain/text/text_data.dart';
import 'package:len/ink/geometry/affine.dart';
import 'package:len/ink/selection/ink_clipboard.dart';
import 'package:len/ink/selection/lasso.dart';
import 'package:len/ink/selection/selection_controller.dart';
import 'package:len/ink/selection/selection_frame.dart';
import 'package:len/ink/selection/transform_items.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/undo_history.dart';

import 'data_test.dart' show FakeClock;
import 'elements_test.dart' show textBox;

Stroke line(String id, Offset from, Offset to, {int points = 20, double width = 2}) => Stroke(
  id: id,
  surfaceId: 's',
  tool: InkTool.ballpoint,
  color: 0xFF000000,
  width: width,
  points: [
    for (var i = 0; i < points; i++)
      StrokePoint(
        from.dx + (to.dx - from.dx) * i / (points - 1),
        from.dy + (to.dy - from.dy) * i / (points - 1),
        0.5,
      ),
  ],
  createdAt: 1,
);

/// A 100×100 square lasso from (0,0), drawn as a freehand loop.
final square = Lasso(const [Offset(0, 0), Offset(100, 0), Offset(100, 100), Offset(0, 100)]);

void expectOffset(Offset actual, Offset expected) {
  expect(actual.dx, closeTo(expected.dx, 1e-6));
  expect(actual.dy, closeTo(expected.dy, 1e-6));
}

void main() {
  group('Lasso', () {
    test('point in polygon, including concave shapes', () {
      final u = Lasso(const [
        Offset(0, 0),
        Offset(30, 0),
        Offset(30, 70),
        Offset(70, 70),
        Offset(70, 0),
        Offset(100, 0),
        Offset(100, 100),
        Offset(0, 100),
      ]);
      expect(u.contains(const Offset(10, 10)), isTrue);
      expect(u.contains(const Offset(50, 30)), isFalse); // inside the notch
      expect(u.contains(const Offset(50, 90)), isTrue);
      expect(u.contains(const Offset(150, 50)), isFalse);
    });

    test('selects strokes by the share of their length inside', () {
      expect(square.selectsStroke(line('in', const Offset(10, 50), const Offset(90, 50))), isTrue);
      expect(
        square.selectsStroke(line('out', const Offset(110, 50), const Offset(190, 50))),
        isFalse,
      );
      expect(
        square.selectsStroke(line('mostly', const Offset(20, 50), const Offset(130, 50))),
        isTrue,
      );
      expect(
        square.selectsStroke(line('barely', const Offset(70, 50), const Offset(170, 50))),
        isFalse,
      );
    });

    test('point density does not sway the rule', () {
      // 75% of the length is inside, but 90% of the points are outside.
      final dense = Stroke(
        id: 'd',
        surfaceId: 's',
        tool: InkTool.ballpoint,
        color: 0,
        width: 2,
        points: [
          const StrokePoint(25, 50, 0.5),
          for (var i = 0; i <= 90; i++) StrokePoint(100 + i * 25 / 90, 50, 0.5),
        ],
        createdAt: 1,
      );
      expect(square.insideShare(dense), closeTo(0.75, 0.03));
      expect(square.selectsStroke(dense), isTrue);
    });

    test('a two-point straight line is judged along its length', () {
      final twoPoint = line('l', const Offset(-60, 50), const Offset(80, 50), points: 2);
      expect(square.insideShare(twoPoint), closeTo(80 / 140, 0.05));
      expect(square.selectsStroke(twoPoint), isTrue);
    });

    test('dots are selected when inside', () {
      Stroke dot(Offset at) => Stroke(
        id: 'dot',
        surfaceId: 's',
        tool: InkTool.ballpoint,
        color: 0,
        width: 2,
        points: [StrokePoint(at.dx, at.dy, 0.5)],
        createdAt: 1,
      );
      expect(square.selectsStroke(dot(const Offset(50, 50))), isTrue);
      expect(square.selectsStroke(dot(const Offset(150, 50))), isFalse);
    });

    test('selects elements by centre or most of their outline', () {
      expect(square.selectsElement(textBox('a', const Offset(10, 10), width: 60)), isTrue);
      expect(square.selectsElement(textBox('b', const Offset(150, 10))), isFalse);
      // Centre (110, 25) outside, but a degenerate lasso never selects.
      expect(
        Lasso(const [Offset(0, 0), Offset(1, 1)]).selectsElement(textBox('c', Offset.zero)),
        isFalse,
      );
    });
  });

  group('Affine', () {
    test('compose, invert, rotation and scale', () {
      final t = Affine.rotation(
        math.pi / 2,
        pivot: const Offset(10, 10),
      ).then(Affine.scaling(2, 2)).then(Affine.translation(const Offset(5, 0)));
      final p = const Offset(20, 10);
      // Rotate 90° clockwise about (10,10): (20,10) → (10,20); ×2 → (20,40); +5.
      expectOffset(t.apply(p), const Offset(25, 40));
      expectOffset(t.inverse.apply(t.apply(p)), p);
      expect(t.rotation, closeTo(math.pi / 2, 1e-9));
      expect(t.meanScale, closeTo(2, 1e-9));
    });
  });

  group('SelectionFrame', () {
    const frame = SelectionFrame(Rect.fromLTWH(0, 0, 100, 50));

    test('corner resize keeps the aspect ratio and the opposite corner', () {
      final r = frame.resized(SelectionHandle.bottomRight, const Offset(200, 60));
      expect(r.frame.rect.width / r.frame.rect.height, closeTo(2, 1e-9));
      expectOffset(r.transform.apply(Offset.zero), Offset.zero);
      expectOffset(r.frame.rect.topLeft, Offset.zero);
    });

    test('edge resize stretches one axis', () {
      final r = frame.resized(SelectionHandle.left, const Offset(-100, 999));
      expect(r.frame.rect, const Rect.fromLTWH(-100, 0, 200, 50));
      expectOffset(r.transform.apply(const Offset(100, 25)), const Offset(100, 25));
    });

    test('resize never collapses or flips', () {
      final r = frame.resized(SelectionHandle.right, const Offset(-500, 0));
      expect(r.frame.rect.width, greaterThanOrEqualTo(SelectionFrame.minExtent - 1e-9));
    });

    test('a frame without extent (one point) does not blow up on a corner drag', () {
      // It used to scale by minExtent / 1e-9 (4e9) around the point.
      const point = SelectionFrame(Rect.fromLTWH(480, 330, 0, 0), 1.2);
      final r = point.resized(SelectionHandle.bottomRight, const Offset(10, 600));
      expect(r.transform.meanScale, closeTo(1, 1e-9));
      expectOffset(r.transform.apply(const Offset(500, 300)), const Offset(500, 300));
    });

    test('a thin frame (a straight line) resizes from where it is grabbed', () {
      const thin = SelectionFrame(Rect.fromLTWH(0, 0, 200, 1));
      // Grabbed in place: no jump.
      final same = thin.resized(SelectionHandle.bottomRight, const Offset(200, 1));
      expect(same.frame.rect.width, closeTo(200, 1e-6));
      // Shrinks to half.
      final half = thin.resized(SelectionHandle.bottomRight, const Offset(100, 0.5));
      expect(half.frame.rect.width, closeTo(100, 1e-6));
      // Never below the smallest extent along its long side.
      final tiny = thin.resized(SelectionHandle.bottomRight, const Offset(-50, 0));
      expect(tiny.frame.rect.width, closeTo(SelectionFrame.minExtent, 1e-6));
    });

    test('rotation follows the handle and snaps to 45°', () {
      final r = frame.rotatedTowards(frame.center + const Offset(100, 2));
      expect(r.frame.angle, closeTo(math.pi / 2, 1e-9)); // snapped
      expectOffset(r.transform.apply(frame.center), frame.center);
      final free = frame.rotatedTowards(frame.center + const Offset(100, -40));
      expect(free.frame.angle, closeTo(math.atan2(100, 40), 1e-9));
    });

    test('a rotated frame resizes along its own axes', () {
      final rotated = frame.rotatedTowards(frame.center + const Offset(100, 0)).frame;
      // After 90°, the frame's "right" edge points down in world space.
      final r = rotated.resized(
        SelectionHandle.right,
        rotated.at(const Offset(1, 0.5)) + const Offset(0, 50),
      );
      expect(r.frame.rect.width, closeTo(150, 1e-6));
      expect(r.frame.rect.height, closeTo(50, 1e-6));
      expectOffset(r.frame.at(const Offset(0, 0.5)), rotated.at(const Offset(0, 0.5)));
    });
  });

  group('TransformItems', () {
    test('strokes map points and scale width, keeping paint order', () {
      final s = line('a', Offset.zero, const Offset(10, 0), width: 3);
      final t = TransformItems.stroke(s, Affine.scaling(2, 2), id: 'b');
      expect(t.points.last.offset, const Offset(20, 0));
      expect(t.width, 6);
      expect(t.createdAt, s.createdAt);
    });

    test('text scales its font uniformly and rewraps on stretch', () {
      final e = textBox('t', Offset.zero, width: 100);
      final bigger = TransformItems.element(e, Affine.scaling(2, 2));
      expect(TextData.fromJson(bigger.data).fontSize, 48);
      expect(bigger.rect.width, 200);
      final wider = TransformItems.element(e, Affine.scaling(2, 1));
      expect(TextData.fromJson(wider.data).fontSize, 24);
      expect(wider.rect.width, 200);
    });

    test('elements rotate about the transform', () {
      final e = textBox('t', Offset.zero, width: 100);
      final r = TransformItems.element(e, Affine.rotation(math.pi / 2, pivot: e.rect.center));
      expect(r.rotation, closeTo(math.pi / 2, 1e-9));
      expectOffset(r.rect.center, e.rect.center);
    });
  });

  group('SelectionController', () {
    late AppDatabase db;
    late SurfaceModel model;
    late SelectionController selection;
    late InkClipboard clipboard;
    late FakeClock clock;

    setUp(() {
      db = AppDatabase.inMemory();
      clock = FakeClock();
      model = SurfaceModel(
        surfaceId: 's',
        repository: StrokeRepository(db, deviceId: 'd', clock: clock),
        elementRepository: ElementRepository(db, deviceId: 'd', clock: clock),
        clock: clock,
      );
      clipboard = InkClipboard();
      selection = SelectionController(model: model, clipboard: clipboard, clock: clock);
      model.commit(
        InkEdit(
          added: [line('a', const Offset(10, 10), const Offset(50, 10))],
          addedElements: [textBox('t', const Offset(10, 40))],
        ),
      );
    });

    tearDown(() {
      selection.dispose();
      model.dispose();
      db.close();
    });

    void selectAll() => selection.select([model.strokeById('a')!], [model.elementById('t')!]);

    test('selecting hides the content from the committed layer', () {
      selectAll();
      expect(model.isHidden('a'), isTrue);
      expect(model.isHidden('t'), isTrue);
      expect(selection.picture, isNotNull);
      selection.clear();
      expect(model.isHidden('a'), isFalse);
    });

    test('a move is one undoable edit and the selection follows it', () {
      selectAll();
      final move = selection.frame!.moved(const Offset(100, 0));
      selection
        ..setPreview(move.transform, move.frame)
        ..commitPreview();
      expect(model.strokeById('a'), isNull);
      expect(selection.strokes.single.points.first.offset, const Offset(110, 10));
      expect(model.elementById('t')!.rect.left, 110);
      expect(selection.frame!.rect.left, closeTo(move.frame.rect.left, 1e-9));

      model.undo();
      expect(selection.isEmpty, isTrue); // stale selection dropped
      expect(model.strokeById('a'), isNotNull);
      expect(model.elementById('t')!.rect.left, 10);
      expect(model.isHidden('a'), isFalse);
      model.redo();
      expect(model.elementById('t')!.rect.left, 110);
    });

    test('settled is notified as a drag starts and ends, not on its moves', () {
      var all = 0, settled = 0;
      selection
        ..addListener(() => all++)
        ..settled.addListener(() => settled++);
      selectAll();
      expect(settled, all);
      final before = (all: all, settled: settled);
      for (var i = 1; i <= 5; i++) {
        final move = selection.frame!.moved(Offset(i * 10.0, 0));
        selection.setPreview(move.transform, move.frame);
      }
      expect(selection.isChanging, isTrue);
      expect(all - before.all, 5);
      expect(settled - before.settled, 1); // The drag started: the menu hides.
      selection.commitPreview();
      expect(selection.isChanging, isFalse);
      expect(settled - before.settled, 2); // It ended: the menu shows again.
      selection.clear();
      expect(settled - before.settled, 3);
    });

    test('a burst of nudges is one undo step; a pause or another edit starts a new one', () {
      selectAll();
      double left() => model.elementById('t')!.rect.left;
      selection
        ..nudge(const Offset(1, 0))
        ..nudge(const Offset(1, 0));
      clock.now += 900;
      selection.nudge(const Offset(1, 0));
      expect(left(), 13);
      clock.now += 1100; // a pause
      selection.nudge(const Offset(10, 0));
      selection.recolor(0xFFFF0000); // another edit
      selection.nudge(const Offset(1, 0));
      expect(left(), 24);

      model.undo();
      expect(left(), 23);
      model.undo(); // the recolour
      model.undo();
      expect(left(), 13);
      model.undo();
      expect(left(), 10);
    });

    test('a nudge after an undo does not join the undone step', () {
      selectAll();
      selection.nudge(const Offset(1, 0));
      model.undo();
      selectAll();
      selection.nudge(const Offset(5, 0));
      model.undo();
      expect(model.elementById('t')!.rect.left, 10);
      expect(model.history.canUndo, isTrue, reason: 'the initial content');
    });

    test('delete, copy and paste (also onto another surface)', () {
      selectAll();
      selection.cut();
      expect(model.loadedStrokeCount, 0);
      expect(model.loadedElementCount, 0);
      expect(clipboard.isEmpty, isFalse);

      selection.paste(const Offset(500, 500));
      expect(model.loadedStrokeCount, 1);
      expect(selection.frame!.rect.center.dx, closeTo(500, 1e-6));
      expect(model.elementById('t'), isNull); // pasted under a new id
      expect(selection.elements.single.surfaceId, 's');

      final other = SurfaceModel(
        surfaceId: 'other',
        repository: StrokeRepository(db, deviceId: 'd'),
        elementRepository: ElementRepository(db, deviceId: 'd'),
      );
      final pastedId = selection.strokes.single.id;
      selection.model = other;
      expect(model.isHidden(pastedId), isFalse);
      selection.paste(Offset.zero);
      expect(other.loadedStrokeCount, 1);
      expect(selection.strokes.single.surfaceId, 'other');
      other.undo();
      expect(other.loadedStrokeCount, 0);
      other.dispose();
    });

    test('duplicate and recolour', () {
      selectAll();
      selection.duplicate();
      expect(model.loadedStrokeCount, 2);
      expect(model.loadedElementCount, 2);
      selection.recolor(0xFFFF0000);
      expect(selection.strokes.single.color, 0xFFFF0000);
      expect(TextData.fromJson(selection.elements.single.data).color, 0xFFFF0000);
      expect(model.strokeById('a')!.color, 0xFF000000); // original untouched
      model.undo(); // recolour
      model.undo(); // duplicate
      expect(model.loadedStrokeCount, 1);
    });

    test('restyle text boxes (font, size) and ink (width, pen type)', () {
      selectAll();
      final box = selection.elements.single;
      selection.restyleText((t) => t.withFont(TextFont.caveat).withFontSize(48));
      final text = selection.elements.single;
      final data = TextData.fromJson(text.data);
      expect(data.font, TextFont.caveat);
      expect(data.fontSize, 48);
      expect(text.id, box.id);
      expect(text.rect.topLeft, box.rect.topLeft);
      expect(text.rect.height, greaterThan(box.rect.height)); // laid out again
      expect(selection.strokes.single.id, 'a'); // ink untouched

      selection.restyleInk(width: 9, tool: InkTool.highlighter, styleFor: StrokeStyle.defaultsFor);
      final ink = selection.strokes.single;
      expect(ink.tool, InkTool.highlighter);
      expect(ink.width, 9);
      expect(ink.style, StrokeStyle.defaultsFor(InkTool.highlighter));
      expect(ink.points, model.strokeById(ink.id)!.points);
      expect(model.strokeById('a'), isNull);
      model.undo();
      expect(model.strokeById('a')!.tool, InkTool.ballpoint);
      model.undo();
      expect(TextData.fromJson(model.elementById(box.id)!.data).font, TextFont.inter);
    });
  });
}
