import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/element_repository.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/ink/geometry/affine.dart';
import 'package:len/ink/selection/ink_clipboard.dart';
import 'package:len/ink/selection/selection_controller.dart';
import 'package:len/ink/selection/selection_frame.dart';
import 'package:len/ink/selection/transform_items.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/undo_history.dart';

import 'data_test.dart' show FakeClock;
import 'elements_test.dart' show textBox;
import 'support/property.dart';

const _eps = 1e-6;

Offset _point(math.Random r, [double extent = 1000]) =>
    Offset(r.nextDouble() * 2 * extent - extent, r.nextDouble() * 2 * extent - extent);

double _angle(math.Random r) => r.nextDouble() * 4 * math.pi - 2 * math.pi;

/// A scale factor of either sign, away from zero.
double _scale(math.Random r) => (0.1 + r.nextDouble() * 5) * (r.nextBool() ? 1 : -1);

/// An invertible transform: a few random moves, rotations and scalings.
Affine _affine(math.Random r) {
  var t = Affine.identity;
  for (var i = Gens.intIn(1, 4)(r); i > 0; i--) {
    t = t.then(switch (r.nextInt(3)) {
      0 => Affine.translation(_point(r)),
      1 => Affine.rotation(_angle(r), pivot: _point(r)),
      _ => Affine.scaling(_scale(r), _scale(r), anchor: _point(r)),
    });
  }
  return t;
}

/// A transform keeping shapes (rotation, uniform positive scale, move):
/// what the selection gestures make of a frame's own axes.
Affine _similarity(math.Random r) {
  final scale = 0.2 + r.nextDouble() * 4;
  return Affine.rotation(
    _angle(r),
    pivot: _point(r),
  ).then(Affine.scaling(scale, scale, anchor: _point(r))).then(Affine.translation(_point(r)));
}

void _near(Offset actual, Offset expected, {double tolerance = _eps, String? reason}) {
  final scale = math.max(1, expected.distance);
  expect(
    (actual - expected).distance,
    lessThanOrEqualTo(tolerance * scale),
    reason: '${reason ?? ''} $actual vs $expected',
  );
}

void _finite(Offset p, [String? what]) =>
    expect(p.dx.isFinite && p.dy.isFinite, isTrue, reason: '${what ?? ''} $p');

SelectionFrame _frame(math.Random r) {
  final degenerate = r.nextDouble() < 0.15;
  final w = degenerate && r.nextBool() ? 0.0 : r.nextDouble() * 400;
  final h = degenerate && r.nextBool() ? 0.0 : r.nextDouble() * 400;
  final at = _point(r, 500);
  return SelectionFrame(Rect.fromLTWH(at.dx, at.dy, w, h), r.nextBool() ? 0 : _angle(r));
}

Stroke _stroke(math.Random r) => Stroke(
  id: 'o',
  surfaceId: 's',
  tool: Gens.oneOf(InkTool.values)(r),
  color: 0xFF000000,
  width: 0.5 + r.nextDouble() * 10,
  points: [
    for (var i = Gens.intIn(1, 20)(r); i > 0; i--) StrokePoint(_point(r).dx, _point(r).dy, 0.5),
  ],
  createdAt: 7,
  style: StrokeStyle.defaultsFor(InkTool.ballpoint).copyWith(unit: 0.5 + r.nextDouble()),
);

SurfaceElement _image(math.Random r) {
  final at = _point(r, 500);
  return SurfaceElement(
    id: 'i',
    surfaceId: 's',
    type: 'image',
    rect: Rect.fromLTWH(at.dx, at.dy, 1 + r.nextDouble() * 300, 1 + r.nextDouble() * 300),
    rotation: r.nextBool() ? 0 : _angle(r) / 2,
    z: 1,
    createdAt: 1,
    data: const {'blob': 'x', 'width': 10, 'height': 10},
  );
}

void main() {
  group('Affine', () {
    test('then composes, and a transform followed by its inverse is the identity', () async {
      await forAll((r) => (a: _affine(r), b: _affine(r), c: _affine(r), p: _point(r)), (x) {
        _near(x.a.then(x.b).apply(x.p), x.b.apply(x.a.apply(x.p)), tolerance: 1e-9);
        _near(
          x.a.then(x.b).then(x.c).apply(x.p),
          x.a.then(x.b.then(x.c)).apply(x.p),
          tolerance: 1e-9,
        );
        _near(x.a.then(x.a.inverse).apply(x.p), x.p);
        _near(x.a.inverse.then(x.a).apply(x.p), x.p);
        _near(x.a.inverse.apply(x.a.apply(x.p)), x.p);
        final det = x.a.then(x.b).determinant;
        expect(det, closeTo(x.a.determinant * x.b.determinant, 1e-9 * det.abs() + 1e-12));
        expect(x.a.then(x.b).meanScale, closeTo(x.a.meanScale * x.b.meanScale, 1e-9 * det.abs()));
        // Vectors ignore translation.
        _near(x.a.applyVector(x.p), x.a.apply(x.p) - x.a.apply(Offset.zero), tolerance: 1e-9);
      }, runs: 500);
    });

    test('rotations keep their pivot and distances; scalings keep their anchor', () async {
      await forAll((r) => (angle: _angle(r), pivot: _point(r), p: _point(r), q: _point(r)), (x) {
        final rot = Affine.rotation(x.angle, pivot: x.pivot);
        _near(rot.apply(x.pivot), x.pivot);
        expect((rot.apply(x.p) - rot.apply(x.q)).distance, closeTo((x.p - x.q).distance, 1e-6));
        expect(rot.meanScale, closeTo(1, 1e-12));
        _near(rot.then(Affine.rotation(-x.angle, pivot: x.pivot)).apply(x.p), x.p);
        final s = Affine.scaling(x.angle, x.angle / 2, anchor: x.pivot);
        _near(s.apply(x.pivot), x.pivot);
      }, runs: 300);
    });
  });

  group('SelectionFrame', () {
    /// The frame's corners as world points, in order.
    void expectFrame(SelectionFrame actual, SelectionFrame expected, String what) {
      for (var i = 0; i < 4; i++) {
        _near(actual.corners[i], expected.corners[i], tolerance: 1e-7, reason: '$what corner $i');
      }
    }

    test('gestures move the frame exactly as their transform moves the content', () async {
      await forAll(
        (r) => (
          frame: _frame(r),
          pointer: _point(r, r.nextBool() ? 600 : 1e5),
          handle: Gens.oneOf<SelectionHandle?>([null, ...SelectionHandle.values])(r),
          snap: r.nextBool(),
        ),
        (x) {
          final f = x.frame;
          final result = switch (x.handle) {
            null => f.moved(x.pointer),
            SelectionHandle.rotate => f.rotatedTowards(x.pointer, snap: x.snap),
            final h => f.resized(h, x.pointer),
          };
          final t = result.transform, g = result.frame;
          for (final v in [t.a, t.b, t.c, t.d, t.tx, t.ty, g.rect.width, g.rect.height, g.angle]) {
            expect(v.isFinite, isTrue, reason: '$t $g');
          }
          for (var i = 0; i < 4; i++) {
            _near(t.apply(f.corners[i]), g.corners[i], tolerance: 1e-7, reason: 'corner $i');
          }
          expectFrame(f.transformed(t), g, 'transformed');
          // Never flips.
          expect(t.determinant, greaterThan(0));
        },
        runs: 1000,
      );
    });

    test('resizing keeps the opposite handle and a usable size', () async {
      await forAll(
        (r) => (
          frame: _frame(r),
          pointer: _point(r, 600),
          handle: Gens.oneOf<SelectionHandle>([
            for (final h in SelectionHandle.values)
              if (h != SelectionHandle.rotate) h,
          ])(r),
        ),
        (x) {
          final f = x.frame, h = x.handle;
          final result = f.resized(h, x.pointer);
          final fixed = f.at(h.oppositeFraction);
          _near(result.transform.apply(fixed), fixed, reason: 'anchor moved');
          _near(result.frame.at(h.oppositeFraction), fixed, reason: 'frame anchor moved');
          final w = f.rect.width, hgt = f.rect.height;
          final nw = result.frame.rect.width, nh = result.frame.rect.height;
          const min = SelectionFrame.minExtent - 1e-9;
          if (h.isCorner) {
            if (math.max(w, hgt) > 0) expect(math.max(nw, nh), greaterThanOrEqualTo(min));
            if (hgt > 0 && w > 0) expect(nw / nh, closeTo(w / hgt, 1e-6 * w / hgt));
          } else if (h.fraction.dx != 0.5) {
            if (w > 0) expect(nw, greaterThanOrEqualTo(min));
            expect(nh, closeTo(hgt, 1e-9));
          } else {
            if (hgt > 0) expect(nh, greaterThanOrEqualTo(min));
            expect(nw, closeTo(w, 1e-9));
          }
        },
        runs: 1000,
      );
    });

    test('gestures undone by the opposite gesture leave the content in place', () async {
      await forAll(
        (r) => (
          frame: SelectionFrame(
            Rect.fromLTWH(
              _point(r).dx,
              _point(r).dy,
              10 + r.nextDouble() * 300,
              10 + r.nextDouble() * 300,
            ),
            r.nextBool() ? 0 : _angle(r),
          ),
          delta: _point(r, 300),
          handle: Gens.oneOf([
            for (final h in SelectionHandle.values)
              if (h != SelectionHandle.rotate) h,
          ])(r),
          p: _point(r),
        ),
        (x) {
          final f = x.frame;
          // Move there and back.
          final there = f.moved(x.delta);
          final back = there.frame.moved(-x.delta);
          _near(there.transform.then(back.transform).apply(x.p), x.p);
          expectFrame(back.frame, f, 'moved back');
          // Rotate there and back (the rotate handle starts "up").
          final turned = f.rotatedTowards(f.center + x.delta, snap: false);
          final unturned = turned.frame.rotatedTowards(f.center + f.up * 50, snap: false);
          _near(turned.transform.then(unturned.transform).apply(x.p), x.p);
          expectFrame(unturned.frame, f, 'rotated back');
          // Resize by dragging a handle out and back to where it was
          // (within the size limits, so it can come back).
          final h = x.handle;
          final grabbed = f.at(h.fraction);
          final pulled = grabbed + (grabbed - f.at(h.oppositeFraction)) * 0.5;
          final resized = f.resized(h, pulled);
          final restored = resized.frame.resized(h, grabbed);
          _near(resized.transform.then(restored.transform).apply(x.p), x.p, tolerance: 1e-6);
          expectFrame(restored.frame, f, 'resized back');
        },
        runs: 500,
      );
    });
  });

  group('TransformItems', () {
    test('a stroke transformed and back keeps its points, width and scale', () async {
      await forAll((r) => (stroke: _stroke(r), t: _affine(r)), (x) {
        final s = x.stroke, t = x.t;
        final there = TransformItems.stroke(s, t, id: 'n');
        expect(there.id, 'n');
        expect(there.createdAt, s.createdAt);
        expect([there.tool, there.color, there.surfaceId], [s.tool, s.color, s.surfaceId]);
        for (var i = 0; i < s.points.length; i++) {
          _near(there.points[i].offset, t.apply(s.points[i].offset), tolerance: 1e-9);
          expect(there.points[i].pressure, s.points[i].pressure);
        }
        final back = TransformItems.stroke(there, t.inverse, id: 'b');
        for (var i = 0; i < s.points.length; i++) {
          _near(back.points[i].offset, s.points[i].offset);
        }
        expect(back.style.unit, closeTo(s.style.unit, 1e-6 * s.style.unit));
        final width = s.width * t.meanScale;
        if (width >= 0.1 && width <= 400) expect(back.width, closeTo(s.width, 1e-6 * s.width));
      }, runs: 500);
    });

    test('an element transformed and back keeps its box', () async {
      await forAll((r) => (e: _image(r), t: _similarity(r)), (x) {
        final there = TransformItems.element(x.e, x.t);
        expect(there.id, x.e.id);
        _near(there.rect.center, x.t.apply(x.e.rect.center));
        final back = TransformItems.element(there, x.t.inverse);
        _near(back.rect.center, x.e.rect.center);
        expect(back.rect.width, closeTo(x.e.rect.width, 1e-6 * x.e.rect.width));
        expect(back.rect.height, closeTo(x.e.rect.height, 1e-6 * x.e.rect.height));
        final turn = (back.rotation - x.e.rotation) % (2 * math.pi);
        expect(math.min(turn, 2 * math.pi - turn), lessThan(1e-9));
      }, runs: 500);
    });

    test('degenerate transforms (zero or negative scales) give finite items', () async {
      await forAll(
        (r) => (
          stroke: _stroke(r),
          image: _image(r),
          text: textBox('t', _point(r, 500)).copyWith(rotation: _angle(r)),
          t: Affine.scaling(
            Gens.oneOf([0.0, -1.0, 1e-12, -3.0, 2.0])(r),
            Gens.oneOf([0.0, -1.0, 1e-12, -0.5, 1.0])(r),
            anchor: _point(r),
          ).then(Affine.rotation(_angle(r))),
        ),
        (x) {
          final s = TransformItems.stroke(x.stroke, x.t, id: 'n');
          for (final p in s.points) {
            _finite(p.offset, 'stroke point');
          }
          expect(s.width, inInclusiveRange(0.1, 400));
          expect(s.style.unit.isFinite && s.style.unit >= 0, isTrue);
          _finite(s.bounds.topLeft);
          _finite(s.bounds.bottomRight);
          for (final e in [x.image, x.text]) {
            final out = TransformItems.element(e, x.t);
            _finite(out.rect.topLeft, '${e.type} rect');
            _finite(out.rect.bottomRight, '${e.type} rect');
            expect(out.rect.width, greaterThanOrEqualTo(0));
            expect(out.rect.height, greaterThanOrEqualTo(0));
            expect(out.rotation.isFinite, isTrue);
            expect(out.rotation.abs(), lessThanOrEqualTo(math.pi + 1e-9));
          }
        },
        runs: 300,
      );
    });
  });

  test('a committed selection transform is one undo step', () async {
    await forAll((r) => (seed: r.nextInt(1 << 30), t: _similarity(r)), (x) {
      final r = math.Random(x.seed);
      final db = AppDatabase.inMemory();
      final clock = FakeClock();
      final model = SurfaceModel(
        surfaceId: 's',
        repository: StrokeRepository(db, deviceId: 'd', clock: clock),
        elementRepository: ElementRepository(db, deviceId: 'd', clock: clock),
        clock: clock,
      );
      final selection = SelectionController(model: model, clipboard: InkClipboard(), clock: clock);
      addTearDown(() {
        selection.dispose();
        model.dispose();
        db.close();
      });
      final strokes = [
        for (var i = 0; i < 3; i++)
          Stroke(
            id: 'k$i',
            surfaceId: 's',
            tool: InkTool.ballpoint,
            color: 0xFF000000,
            width: 2,
            points: [
              for (var j = 0; j < 4; j++) StrokePoint(_point(r, 300).dx, _point(r, 300).dy, 0.5),
            ],
            createdAt: i,
          ),
      ];
      final box = textBox('t', _point(r, 300));
      model.commit(InkEdit(added: strokes, addedElements: [box]));
      selection.select(strokes, [box]);
      final frame = selection.frame!;
      selection
        ..setPreview(x.t, frame.transformed(x.t))
        ..commitPreview();
      expect(selection.strokes, hasLength(3));
      for (var i = 0; i < 3; i++) {
        final moved = selection.strokes.firstWhere((s) => s.createdAt == i);
        expect(model.strokeById(moved.id), same(moved));
        for (var j = 0; j < 4; j++) {
          _near(moved.points[j].offset, x.t.apply(strokes[i].points[j].offset));
        }
      }
      model.undo();
      for (final s in strokes) {
        expect(model.strokeById(s.id), same(s));
      }
      expect(model.elementById('t'), same(box));
      expect(model.history.canUndo, isTrue); // just the drawing
      model.redo();
      expect(model.strokeById('k0'), isNull);
      _near(model.elementById('t')!.rect.center, x.t.apply(box.rect.center));
    }, runs: 40);
  });
}
