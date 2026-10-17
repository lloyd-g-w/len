import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/geometry/affine.dart';
import 'package:len/ink/input/ink_input_controller.dart';
import 'package:len/ink/input/live_ink.dart';
import 'package:len/ink/selection/connectors.dart';
import 'package:len/ink/selection/ink_clipboard.dart';
import 'package:len/ink/shapes/shape_anchors.dart';
import 'package:len/ink/shapes/shape_builder.dart';
import 'package:len/ink/shapes/shape_handles.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ink/tools/content_tools.dart';
import 'package:len/ink/viewport.dart';

import 'shape_geometry_test.dart' show shapeStroke;

// Arrows that stay attached (connectors): the geometry's references, ends
// attaching on drag and on draw, following their shapes in one undo step,
// letting go, and through sync.

const _all = Rect.fromLTWH(-1000, -1000, 3000, 3000);

void main() {
  group('geometry', () {
    final arrow = ShapeGeometry(ShapeKind.arrow, const [
      Offset(0, 0),
      Offset(100, 0),
      Offset(50, 20),
    ], tail: const ShapeAttachment('box', 0.25));

    test('attachments round-trip; old data without them reads unchanged', () {
      expect(ShapeGeometry.fromJson(arrow.toJson()), arrow);
      expect(arrow.toJson()['a'], [
        {'id': 'box', 't': 0.25},
        null,
      ]);
      final plain = ShapeGeometry(ShapeKind.line, const [Offset(0, 0), Offset(10, 0)]);
      expect(plain.toJson().containsKey('a'), isFalse);
      expect(
        ShapeGeometry.fromJson({
          'k': 'line',
          'p': [0, 0, 10, 0],
        }),
        plain,
      );
      // Moving, bending: the references stay.
      expect(arrow.map((p) => p + const Offset(5, 5)).tail, arrow.tail);
      expect(arrow.withPoint(2, const Offset(50, 40)).tail, arrow.tail);
    });

    test('a shape\'s identity (origin) round-trips and survives its edits', () {
      final box = ShapeGeometry(ShapeKind.rectangle, const [
        Offset(0, 0),
        Offset(10, 0),
        Offset(10, 10),
        Offset(0, 10),
      ]);
      expect(box.toJson().containsKey('o'), isFalse);
      final edited = box.withOrigin('first');
      expect(edited.toJson()['o'], 'first');
      expect(ShapeGeometry.fromJson(edited.toJson()), edited);
      expect(edited.map((p) => p * 2).origin, 'first');
      final circle = ShapeGeometry(ShapeKind.circle, const [Offset.zero, Offset(5, 0)]);
      expect(circle.withOrigin('c').map((p) => Offset(p.dx * 2, p.dy)).origin, 'c');
      expect(() => ShapeGeometry.fromJson({...box.toJson(), 'o': ''}), throwsFormatException);
      expect(() => ShapeGeometry.fromJson({...box.toJson(), 'o': 3}), throwsFormatException);
    });

    test('malformed attachments make the shape malformed', () {
      for (final a in [
        [null],
        [
          {'id': 'x'},
          null,
        ],
        [
          {'id': '', 't': 0},
          null,
        ],
        [
          {'id': 'x', 't': 2},
          null,
        ],
      ]) {
        expect(
          () => ShapeGeometry.fromJson({
            'k': 'arrow',
            'p': [0, 0, 10, 0],
            'a': a,
          }),
          throwsFormatException,
        );
      }
      expect(
        () => ShapeGeometry.fromJson({
          'k': 'rectangle',
          'p': [0, 0, 10, 0, 10, 10, 0, 10],
          'a': [null, null],
        }),
        throwsFormatException,
      );
    });

    test('an outline point keeps its place when the shape is moved, turned, resized', () {
      final shapes = [
        for (final kind in [
          ShapeKind.rectangle,
          ShapeKind.ellipse,
          ShapeKind.triangle,
          ShapeKind.diamond,
          ShapeKind.star,
        ])
          ShapeBuilder.dragged(kind, const Offset(10, 20), const Offset(130, 100)),
        ShapeBuilder.dragged(ShapeKind.ellipse, Offset.zero, const Offset(80, 80)), // circle
        ShapeGeometry(ShapeKind.curve, const [
          Offset(0, 0), Offset(30, -20), Offset(70, -20), Offset(100, 0), //
          Offset(120, 40), Offset(-20, 40),
        ]),
      ];
      final t = Affine.translation(const Offset(40, -10)).then(Affine.rotation(0.4));
      for (final shape in shapes) {
        for (final at in [0.0, 0.13, 0.5, 0.77]) {
          final p = ShapeAnchors.pointAt(shape, at);
          expect(ShapeAnchors.nearest(shape, p), closeTo(at, 1e-6), reason: '$shape at $at');
          expect(
            ShapeAnchors.pointAt(shape.map(t.apply), at),
            offsetMoreOrLessEquals(t.apply(p), epsilon: 1e-6),
          );
        }
      }
    });
  });

  group('editing', () {
    late AppDatabase db;
    late StrokeRepository repository;
    late SurfaceModel model;
    late ViewportController viewport;
    late ToolSettings tools;
    late ContentTools content;
    late InkInputController input;
    var pointer = 0;

    setUp(() {
      db = AppDatabase.inMemory();
      repository = StrokeRepository(db, deviceId: 'd');
      model = SurfaceModel(surfaceId: 's', repository: repository);
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

    void drag(List<Offset> path, {void Function()? before}) {
      final id = ++pointer;
      const kind = PointerDeviceKind.stylus;
      input.handleDown(PointerDownEvent(pointer: id, kind: kind, position: path.first));
      for (final p in path.skip(1)) {
        input.handleMove(PointerMoveEvent(pointer: id, kind: kind, position: p));
      }
      before?.call();
      input.handleUp(PointerUpEvent(pointer: id, kind: kind, position: path.last));
    }

    Stroke seed(ShapeGeometry shape, String id) {
      model.addStroke(shapeStroke(shape, id: id));
      model.history.takeUndo(); // seeded, not an edit
      return model.strokeById(id)!;
    }

    final boxShape = ShapeBuilder.dragged(
      ShapeKind.rectangle,
      const Offset(300, 200),
      const Offset(400, 300),
    );
    Stroke box() => seed(boxShape, 'box');

    /// An arrow from (100, 250) with its tip on the box's left side.
    Stroke attachedArrow() => seed(
      ShapeGeometry(
        ShapeKind.arrow,
        const [Offset(100, 250), Offset(300, 250)],
        tip: const ShapeAttachment('box', 0.875), // the left side's middle
      ),
      'arrow',
    );

    Stroke? stored(bool Function(Stroke s) test) => model.strokesNear(_all).where(test).firstOrNull;
    Stroke arrowNow() => stored((s) => s.shape!.kind == ShapeKind.arrow)!;
    Stroke boxNow() => stored((s) => s.shape!.kind == ShapeKind.rectangle)!;

    void expectAttached() {
      final a = arrowNow(), b = boxNow();
      expect(a.shape!.tip!.id, b.shapeId);
      expect(
        a.shape!.points[1],
        offsetMoreOrLessEquals(ShapeAnchors.pointAt(b.shape!, a.shape!.tip!.at), epsilon: 1e-6),
      );
    }

    void transform(Affine t) {
      final s = content.selection;
      s.setPreview(t, s.frame!);
      s.commitPreview();
    }

    test('the end follows its box moved, resized, turned, reshaped; one undo step each', () {
      final b = box();
      attachedArrow();
      expect(ShapeAnchors.pointAt(b.shape!, 0.875), const Offset(300, 250));
      final edits = <void Function()>[
        () => transform(Affine.translation(const Offset(50, 80))),
        () => transform(Affine.scaling(2, 1.5, anchor: boxNow().bounds.center)),
        () => transform(Affine.rotation(0.6, pivot: boxNow().bounds.center)),
        () {
          final shape = content.selection.shape!;
          content.selection
            ..reshape(ShapeHandles.drag(shape, 1, shape.points[1] + const Offset(40, -30)))
            ..commitReshape();
        },
      ];
      final steps = <(ShapeGeometry, ShapeGeometry)>[(boxNow().shape!, arrowNow().shape!)];
      for (final edit in edits) {
        content.selection.select([boxNow()], const []);
        edit();
        expectAttached();
        // A new stroke, the same shape: the arrow still names it as before.
        expect(boxNow().id, isNot('box'));
        expect(boxNow().shapeId, 'box');
        expect(arrowNow().shape!.tip!.id, 'box');
        expect(arrowNow().shape!.points[0], const Offset(100, 250)); // the tail stays
        steps.add((boxNow().shape!, arrowNow().shape!));
      }
      // Each edit is one step: undo takes box and arrow back together.
      for (final (boxWas, arrowWas) in steps.reversed.skip(1)) {
        model.undo();
        expect(boxNow().shape, boxWas);
        expect(arrowNow().shape!.points, arrowWas.points);
        expectAttached();
      }
      model.redo();
      expect(arrowNow().shape!.points, steps[1].$2.points);
      expectAttached();
    });

    // A circle whose rim point is 30° round, an ellipse turned by 30°:
    // stretched, they get new axes (and parameters).
    const centre = Offset(200, 200);
    final circle = ShapeGeometry(ShapeKind.circle, [
      centre,
      centre + Offset.fromDirection(math.pi / 6, 50),
    ]);
    final ellipse = ShapeGeometry(ShapeKind.ellipse, [
      centre,
      centre + Offset.fromDirection(math.pi / 6, 80),
      centre + Offset.fromDirection(math.pi / 6 + math.pi / 2, 40),
    ]);
    for (final (shape, withArrow) in [
      (circle, false),
      (circle, true),
      (ellipse, false),
      (ellipse, true),
    ]) {
      final name = '${shape.kind.name}${withArrow ? ' and its arrow' : ''}';
      test('a turned $name stretched: the arrow stays at the same point', () {
        final squash = Affine.scaling(2, 1, anchor: centre);
        final ring = seed(shape, 'ring');
        final end = ShapeAnchors.pointAt(shape, 0.1);
        seed(
          ShapeGeometry(ShapeKind.arrow, [
            Offset.zero,
            end,
          ], tip: const ShapeAttachment('ring', 0.1)),
          'arrow',
        );
        content.selection.select([ring, if (withArrow) arrowNow()], const []);
        transform(squash);
        final a = arrowNow().shape!;
        final r = stored((s) => s.shape!.kind != ShapeKind.arrow)!;
        expect(a.tip?.id, 'ring');
        expect(a.points[1], offsetMoreOrLessEquals(squash.apply(end), epsilon: 1e-3));
        expect(Connectors.sits(a, 1, r.shape), isTrue);
      });
    }

    test('while the box is dragged, its arrow is shown following', () {
      box();
      attachedArrow();
      final s = content.selection..select([boxNow()], const []);
      s.setPreview(Affine.translation(const Offset(0, 40)), s.frame!);
      expect(s.followers, isNotNull);
      expect(model.isHidden('arrow'), isTrue);
      s.cancelPreview();
      expect(s.followers, isNull);
      expect(model.isHidden('arrow'), isFalse);
      // Reshaped by a handle too.
      final shape = s.shape!;
      s.reshape(ShapeHandles.drag(shape, 0, shape.points[0] + const Offset(-20, 0)));
      expect(s.followers, isNotNull);
      s.commitReshape();
      expect(s.followers, isNull);
      expect(model.isHidden(arrowNow().id), isFalse);
      expectAttached();
    });

    test('moved with its box the arrow stays attached; moved alone it lets go', () {
      box();
      attachedArrow();
      content.selection.select([boxNow(), arrowNow()], const []);
      transform(Affine.translation(const Offset(30, 30)));
      expectAttached();
      expect(arrowNow().shape!.points[0], const Offset(130, 280));
      content.selection.select([arrowNow()], const []);
      transform(Affine.translation(const Offset(0, -40)));
      expect(arrowNow().shape!.tip, isNull);
      // The box moves on without it.
      final before = arrowNow().shape;
      content.selection.select([boxNow()], const []);
      transform(Affine.translation(const Offset(10, 10)));
      expect(arrowNow().shape, before);
    });

    test('restyled or bent the arrow stays attached', () {
      box();
      attachedArrow();
      content.selection
        ..select([arrowNow()], const [])
        ..recolor(0xFFE03131);
      expectAttached();
      final shape = content.selection.shape!;
      content.selection
        ..reshape(ShapeHandles.drag(shape, 2, const Offset(200, 200)))
        ..commitReshape();
      expect(arrowNow().shape!.isBent, isTrue);
      expectAttached();
      // A bent arrow follows its box too, still bent.
      content.selection.select([boxNow()], const []);
      transform(Affine.translation(const Offset(0, 60)));
      expectAttached();
      expect(arrowNow().shape!.isBent, isTrue);
    });

    test('a deleted box leaves the arrow where it is', () {
      box();
      final arrow = attachedArrow();
      content.selection
        ..select([boxNow()], const [])
        ..delete();
      expect(arrowNow().shape, arrow.shape);
      expect(arrowNow().id, arrow.id);
      // Undo brings the box back, still with its arrow.
      model.undo();
      content.selection.select([boxNow()], const []);
      transform(Affine.translation(const Offset(0, 20)));
      expectAttached();
    });

    test('a pasted copy of box and arrow is attached to its own box', () {
      box();
      attachedArrow();
      content.selection.select([boxNow()], const []);
      transform(Affine.translation(const Offset(0, 10))); // an edited box: origin 'box'
      content.selection
        ..select([boxNow(), arrowNow()], const [])
        ..duplicate();
      final copies = content.selection.strokes;
      final copyBox = copies.firstWhere((s) => s.shape!.kind == ShapeKind.rectangle);
      final copyArrow = copies.firstWhere((s) => s.shape!.kind == ShapeKind.arrow);
      expect(copyArrow.shape!.tip!.id, copyBox.id);
      expect(copyBox.shapeId, copyBox.id); // a shape of its own
      // Only the arrow copied: it lets go.
      content.selection
        ..select([
          stored((s) => s.shape!.kind == ShapeKind.arrow && s.id != copyArrow.id)!,
        ], const [])
        ..duplicate();
      expect(content.selection.strokes.single.shape!.tip, isNull);
    });

    test('a dragged end attaches to a box it is dropped on, or in; dragged off, lets go', () {
      box();
      seed(ShapeGeometry(ShapeKind.line, const [Offset(100, 100), Offset(200, 100)]), 'line');
      final s = content.selection;
      drag([viewport.toScreen(const Offset(150, 100))]); // selects the line
      expect(s.shapeStroke?.id, 'line');
      var hinted = false;
      // Dropped near the top side.
      drag([
        const Offset(200, 100),
        const Offset(260, 150),
        const Offset(352, 203),
      ], before: () => hinted = s.attachHint?.target.id == 'box');
      expect(hinted, isTrue);
      expect(s.attachHint, isNull);
      var line = s.strokes.single.shape!;
      expect(line.tip!.id, 'box');
      expect(line.points[1], offsetMoreOrLessEquals(const Offset(352, 200), epsilon: 1e-6));
      // Dropped inside: where the box faces the other end.
      drag([const Offset(352, 200), const Offset(340, 240), const Offset(330, 260)]);
      line = s.strokes.single.shape!;
      expect(line.tip!.id, 'box');
      final p = line.points[1];
      expect(p.dx == 300 || p.dy == 200, isTrue, reason: '$p on the left or top side');
      // Off it again.
      drag([p, p + const Offset(-60, -40), const Offset(200, 160)]);
      expect(s.strokes.single.shape!.tip, isNull);
      // Where it was dropped (angles snap).
      expect((s.strokes.single.shape!.points[1] - const Offset(200, 160)).distance, lessThan(4));
    });

    test('a line drawn with the Shape tool from one box to another attaches both ends', () {
      seed(boxShape, 'a');
      seed(boxShape.map((p) => p + const Offset(-250, 0)), 'b');
      tools
        ..tool = EditorTool.shape
        ..shape = ShapeKind.arrow;
      var hinted = false;
      drag([
        const Offset(120, 250),
        const Offset(200, 250),
        const Offset(302, 252),
      ], before: () => hinted = content.selection.attachHint?.target.id == 'a');
      expect(hinted, isTrue);
      expect(content.selection.attachHint, isNull);
      final arrow = stored((s) => s.shape!.kind == ShapeKind.arrow)!.shape!;
      expect(arrow.tail!.id, 'b'); // started inside b: its right side, facing the tip
      expect(arrow.points[0].dx, closeTo(150, 1e-6));
      expect(arrow.tip!.id, 'a');
      expect(arrow.points[1], offsetMoreOrLessEquals(const Offset(300, 252), epsilon: 1e-6));
      // Away from shapes: no attachments.
      drag([const Offset(500, 500), const Offset(600, 520)]);
      final free = stored((s) => s.shape!.kind == ShapeKind.arrow && s.bounds.top > 400)!.shape!;
      expect(free.isAttached, isFalse);
    });

    test('a box moved on one device brings its arrow along on another', () {
      box();
      attachedArrow();
      model.flush();
      final other = AppDatabase.inMemory();
      addTearDown(other.close);
      final remote = StrokeRepository(other, deviceId: 'e');
      void push() {
        final records = repository.dirtyRecords(100);
        for (final r in records) {
          remote.applyRemote(r);
        }
        repository.markClean([for (final r in records) (id: r.id, updatedAt: r.updatedAt)]);
      }

      push();
      content.selection.select([boxNow()], const []);
      transform(Affine.rotation(math.pi / 5, pivot: boxNow().bounds.center));
      model.flush();
      push();
      final strokes = remote.loadChunks('s', [
        for (var x = -2; x < 4; x++)
          for (var y = -2; y < 4; y++) (x: x, y: y),
      ]);
      final b = strokes.firstWhere((s) => s.shape!.kind == ShapeKind.rectangle);
      final a = strokes.firstWhere((s) => s.shape!.kind == ShapeKind.arrow);
      expect(b.shape, boxNow().shape);
      expect(a.shape!.tip!.id, b.shapeId);
      expect(a.shape!.points[1], arrowNow().shape!.points[1]);
    });
  });
}
