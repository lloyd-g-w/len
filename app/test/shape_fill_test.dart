import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/element_repository.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/chunk_grid.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/domain/stroke_chunks.dart';
import 'package:len/ink/geometry/affine.dart';
import 'package:len/ink/input/live_ink.dart';
import 'package:len/ink/selection/ink_clipboard.dart';
import 'package:len/ink/selection/selection_controller.dart';
import 'package:len/ink/selection/transform_items.dart';
import 'package:len/ink/shapes/shape_builder.dart';
import 'package:len/ink/stroke_hit_test.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ink/tools/content_hit_test.dart';
import 'package:len/ink/tools/pointer_tool.dart';
import 'package:len/ink/tools/shape_tool.dart';
import 'package:len/ink/undo_history.dart';
import 'package:len/ink/viewport.dart';

import 'data_test.dart' show FakeClock;

const tint = 0x40D32F2F;

/// A closed [kind] shape over [box] in red, filled with [fill].
Stroke shape(
  String id,
  Rect box, {
  int? fill = tint,
  ShapeKind kind = ShapeKind.rectangle,
  int createdAt = 1,
}) => Stroke(
  id: id,
  surfaceId: 's',
  tool: InkTool.ballpoint,
  color: 0xFFD32F2F,
  width: 2,
  points: ShapeBuilder.pointsOf(ShapeBuilder.dragged(kind, box.topLeft, box.bottomRight)),
  shape: ShapeBuilder.dragged(kind, box.topLeft, box.bottomRight),
  createdAt: createdAt,
  style: ShapeBuilder.styleFor(const StrokeStyle()).withFill(fill),
);

void main() {
  // The Shape tool reads the keyboard (Shift).
  TestWidgetsFlutterBinding.ensureInitialized();
  const box = Rect.fromLTWH(0, 0, 600, 400);

  group('data', () {
    test('the fill round-trips through JSON and is parsed strictly', () {
      final style = const StrokeStyle().withFill(tint);
      expect(style.toJson()['f'], tint);
      expect(StrokeStyle.fromJson(jsonDecode(jsonEncode(style.toJson()))), style);
      expect(const StrokeStyle().toJson().containsKey('f'), isFalse);
      expect(StrokeStyle.fromJson(const StrokeStyle().toJson()).fill, isNull);
      for (final bad in [-1, 0x100000000, 1.5, '0xFF000000', true]) {
        final json = {...const StrokeStyle().toJson(), 'f': bad};
        expect(() => StrokeStyle.fromJson(json), throwsFormatException, reason: '$bad');
      }
      // copyWith keeps it; withFill sets and clears it.
      expect(style.copyWith(opacity: 0.5).fill, tint);
      expect(style.withFill(null).fill, isNull);
      expect(style.withFill(null), const StrokeStyle());
    });

    test('only closed outlines are closed (and show a fill)', () {
      for (final kind in ShapeKind.values.where((k) => k.isClosed)) {
        expect(shape('a', box, kind: kind).isClosed, isTrue, reason: kind.name);
        expect(shape('a', box, kind: kind).fill, tint, reason: kind.name);
      }
      final line = shape('l', box, kind: ShapeKind.line);
      expect(line.isClosed, isFalse);
      expect(line.fill, isNull);
    });

    test('a filled shape is indexed in every chunk it covers', () {
      final big = Rect.fromLTWH(0, 0, ChunkGrid.size * 3, ChunkGrid.size * 3);
      final centre = (x: 1, y: 1);
      expect(StrokeChunks.of(shape('o', big, fill: null)), isNot(contains(centre)));
      expect(StrokeChunks.of(shape('f', big)), contains(centre));
    });

    test('a filled shape syncs to another device', () {
      final a = AppDatabase.inMemory(), b = AppDatabase.inMemory();
      addTearDown(a.close);
      addTearDown(b.close);
      final here = StrokeRepository(a, deviceId: 'a'), there = StrokeRepository(b, deviceId: 'b');
      final big = Rect.fromLTWH(0, 0, ChunkGrid.size * 2.5, 300);
      here.save([shape('f', big), shape('o', const Rect.fromLTWH(0, 0, 50, 50), fill: null)]);
      for (final record in here.dirtyRecords(10)) {
        expect(there.applyRemote(record), isTrue);
      }
      final keys = ChunkGrid.rangeFor(big.inflate(10)).keys.toList();
      final pulled = {for (final s in there.loadChunks('s', keys)) s.id: s};
      expect(pulled['f']!.style.fill, tint);
      expect(pulled['f']!.isClosed, isTrue);
      expect(pulled['o']!.style.fill, isNull);
    });

    test('ShapeFill: tints follow the ink, preferences parse strictly', () {
      expect(ShapeFill.none.colorFor(0xFF123456), isNull);
      expect(const ShapeFill.tint(0.25).colorFor(0xFF123456), 0x40123456);
      expect(const ShapeFill.solid(0xFFFACC15).colorFor(0xFF123456), 0xFFFACC15);
      for (final f in [
        ShapeFill.none,
        const ShapeFill.tint(0.12),
        const ShapeFill.solid(0xFF0EA5E9),
      ]) {
        expect(ShapeFill.parse(jsonDecode(jsonEncode(f.toJson()))), f);
        expect(ShapeFill.of(f.colorFor(0xFF123456), 0xFF123456), f);
      }
      expect(ShapeFill.parse({'tint': 0.3}), ShapeFill.none);
      expect(ShapeFill.parse('solid'), ShapeFill.none);
      final tools = ToolSettings()..shapeFill = const ShapeFill.tint(0.45);
      final restored = ToolSettings()..adopt(tools);
      expect(restored.shapeFill, const ShapeFill.tint(0.45));
      expect(tools.toJson()['shapeFill'], {'tint': 0.45});
    });
  });

  group('editing', () {
    late AppDatabase db;
    late FakeClock clock;
    late SurfaceModel model;

    setUp(() {
      db = AppDatabase.inMemory();
      clock = FakeClock();
      model = SurfaceModel(
        surfaceId: 's',
        repository: StrokeRepository(db, deviceId: 'd', clock: clock),
        elementRepository: ElementRepository(db, deviceId: 'd', clock: clock),
        clock: clock,
      );
    });

    tearDown(() {
      model.dispose();
      db.close();
    });

    test('hit tests take the fill as part of the shape', () {
      final filled = shape('f', box), hollow = shape('h', box, fill: null);
      const inside = Offset(300, 200);
      expect(StrokeHitTest.sweepHits(filled, inside, inside, 2), isTrue);
      expect(StrokeHitTest.sweepHits(hollow, inside, inside, 2), isFalse);
      expect(StrokeHitTest.sweepHits(filled, inside, inside, 2, fill: false), isFalse);
      expect(
        StrokeHitTest.sweepHits(filled, const Offset(700, 200), const Offset(800, 9), 2),
        false,
      );
      // A star's points are inside, its notches between them are not.
      final star = shape('s', box, kind: ShapeKind.star);
      expect(StrokeHitTest.fillContains(star, const Offset(300, 30)), isTrue);
      expect(StrokeHitTest.fillContains(star, const Offset(150, 60)), isFalse);
      // A tap on the fill selects the shape; ink on top of it wins there.
      model.commit(InkEdit(added: [filled]));
      expect(ContentHitTest.strokeAt(model, inside, 4)?.id, 'f');
    });

    test('a tap on ink under a tint selects the ink; under a solid fill, the shape', () {
      final word = Stroke(
        id: 'w',
        surfaceId: 's',
        tool: InkTool.ballpoint,
        color: 0xFF000000,
        width: 2,
        points: const [StrokePoint(280, 200, 0.5), StrokePoint(320, 200, 0.5)],
        createdAt: 1,
      );
      // The box drawn around the word afterwards.
      model.commit(InkEdit(added: [word, shape('t', box, createdAt: 2)]));
      expect(ContentHitTest.strokeAt(model, const Offset(300, 200), 4)?.id, 'w');
      // Beside the word, the tint is the box.
      expect(ContentHitTest.strokeAt(model, const Offset(300, 120), 4)?.id, 't');
      model.commit(InkEdit(removed: [model.strokeById('t')!]));
      model.commit(InkEdit(added: [shape('o', box, fill: 0xFFD32F2F, createdAt: 2)]));
      expect(ContentHitTest.strokeAt(model, const Offset(300, 200), 4)?.id, 'o');
    });

    test('send to back puts a filled box beneath the label it hid; one undo step', () {
      Stroke word(String id, int at) => Stroke(
        id: id,
        surfaceId: 's',
        tool: InkTool.ballpoint,
        color: 0xFF000000,
        width: 2,
        points: const [StrokePoint(280, 200, 0.5), StrokePoint(320, 200, 0.5)],
        createdAt: at,
      );
      final far = Stroke(
        id: 'far',
        surfaceId: 's',
        tool: InkTool.ballpoint,
        color: 0xFF000000,
        width: 2,
        points: const [StrokePoint(2000, 2000, 0.5), StrokePoint(2040, 2000, 0.5)],
        createdAt: 1,
      );
      // The label, then the box drawn (solid) around it: the box hides it.
      model.commit(
        InkEdit(
          added: [
            far,
            word('w1', 10),
            word('w2', 11),
            shape('box', box, fill: 0xFFFFEB3B, createdAt: 12),
          ],
        ),
      );
      final selection = SelectionController(model: model, clipboard: InkClipboard(), clock: clock);
      addTearDown(selection.dispose);
      selection.select([model.strokeById('box')!], const []);
      selection.sendToBack();
      final sent = selection.strokes.single;
      expect(model.strokeById('box'), isNull);
      // Beneath the label, not beneath ink it doesn't touch.
      expect(sent.createdAt, lessThan(10));
      expect(sent.createdAt, greaterThan(1));
      expect(sent.fill, 0xFFFFEB3B);
      expect(ContentHitTest.strokeAt(model, const Offset(300, 200), 4)?.id, 'w2');
      // Already at the back: nothing to do, no undo step.
      final steps = model.history.recorded;
      selection.sendToBack();
      expect(model.history.recorded, steps);
      // And to the front again, above both words, which keep their order.
      selection.bringToFront();
      expect(selection.strokes.single.createdAt, greaterThan(11));
      model.undo();
      model.undo();
      expect(model.strokeById('box')?.createdAt, 12);
      // Several strokes keep their own order.
      selection.select([model.strokeById('w1')!, model.strokeById('w2')!], const []);
      selection.bringToFront();
      final [a, b] = [...selection.strokes]..sort(Stroke.paintOrder);
      expect(a.points, word('', 0).points);
      expect(a.createdAt, 13);
      expect(b.createdAt, 14);
    });

    test('erasers leave a fill alone, so writing on a filled box goes without it', () {
      final word = Stroke(
        id: 'w',
        surfaceId: 's',
        tool: InkTool.ballpoint,
        color: 0xFF000000,
        width: 2,
        points: const [StrokePoint(280, 200, 0.5), StrokePoint(320, 200, 0.5)],
        createdAt: 2,
      );
      model.commit(InkEdit(added: [shape('f', box), word]));
      const inside = Offset(300, 200);
      expect(model.eraseAlong(inside, inside + const Offset(5, 0), 4, continueEdit: false), isTrue);
      expect(model.strokeById('w'), isNull);
      expect(model.strokeById('f')?.fill, tint);
      // Nothing left to erase in the fill.
      expect(model.eraseAlong(inside, inside, 4, continueEdit: false), isFalse);
      expect(
        model.eraseAlong(inside, inside, 4, continueEdit: false, mode: EraserMode.pixel),
        isFalse,
      );
      // The outline still takes it.
      expect(
        model.eraseAlong(const Offset(300, -3), const Offset(300, 3), 4, continueEdit: false),
        isTrue,
      );
      expect(model.strokeById('f'), isNull);
      model.undo();
      expect(model.strokeById('f')?.fill, tint);
    });

    test('the pixel eraser leaves no fill on the pieces of a cut outline', () {
      model.commit(InkEdit(added: [shape('f', box)]));
      // Cutting the outline opens the shape: its pieces have no fill.
      model.eraseAlong(
        const Offset(300, -10),
        const Offset(300, 10),
        4,
        continueEdit: false,
        mode: EraserMode.pixel,
      );
      final pieces = model.strokesNear(box.inflate(10)).toList();
      expect(pieces, isNotEmpty);
      expect(pieces.every((s) => s.style.fill == null && !s.isClosed), isTrue);
    });

    test('moving, rotating, scaling and restyling keep the fill', () {
      final star = shape('s', box, kind: ShapeKind.star);
      final t = Affine.rotation(0.7, pivot: const Offset(13, 7)).then(Affine.scaling(1.37, 0.61));
      final moved = TransformItems.stroke(star, t, id: 'm');
      expect(moved.isClosed, isTrue);
      expect(moved.fill, tint);
      final restyled = TransformItems.restyleStroke(
        moved,
        id: 'r',
        tool: InkTool.highlighter,
        style: const StrokeStyle(opacity: 0.4),
      );
      expect(restyled.fill, tint);
      expect(restyled.style.opacity, 0.4);
    });

    test('a shape given another pen keeps the even line of shapes', () {
      final plain = shape('s', box);
      final rect = plain.withPoints(
        plain.points,
        shape: plain.shape,
        style: ShapeBuilder.styleFor(const StrokeStyle(unit: 0.5)).withFill(tint),
      );
      // The pen's handwriting look: thinning, tapers, flat ends, stabiliser.
      const pen = StrokeStyle(
        opacity: 0.4,
        thinning: 0.6,
        streamline: 0.5,
        ends: StrokeEnds.flat,
        taperStart: 8,
        taperEnd: 8,
      );
      final restyled = TransformItems.restyleStroke(
        rect,
        id: 'r',
        tool: InkTool.highlighter,
        style: pen,
      );
      expect(restyled.style, ShapeBuilder.styleFor(pen.copyWith(unit: 0.5)).withFill(tint));
      expect(restyled.style.opacity, 0.4);
      expect(restyled.style.unit, 0.5, reason: 'its outline was spaced at that zoom');
    });

    test('the Style panel sets and clears fills of selected shapes, one undo each', () {
      final selection = SelectionController(model: model, clipboard: InkClipboard(), clock: clock);
      addTearDown(selection.dispose);
      final open = shape('l', const Rect.fromLTWH(0, 500, 99, 99), kind: ShapeKind.line);
      model.commit(InkEdit(added: [shape('h', box, fill: null), open]));
      selection.select([model.strokeById('h')!, model.strokeById('l')!], const []);
      const fill = ShapeFill.tint(0.25);
      selection.refill((s) => fill.colorFor(s.color));
      final filled = selection.strokes.where((s) => s.isClosed).single;
      expect(filled.style.fill, 0x40D32F2F);
      expect(selection.strokes.where((s) => !s.isClosed).single.style.fill, isNull);
      // Recolouring takes the tint along.
      selection.recolor(0xFF1C4ED8);
      expect(selection.strokes.where((s) => s.isClosed).single.style.fill, 0x401C4ED8);
      // Nothing changes: no edit.
      final steps = model.history.recorded;
      selection.refill((s) => 0x401C4ED8);
      expect(model.history.recorded, steps);
      selection.refill((s) => null);
      expect(selection.strokes.every((s) => s.style.fill == null), isTrue);
      model.undo();
      expect(model.strokesNear(box).where((s) => s.isClosed).single.style.fill, 0x401C4ED8);
      model.undo();
      model.undo();
      expect(model.strokesNear(box).where((s) => s.isClosed).single.style.fill, isNull);
    });
  });

  test('the Shape tool fills closed shapes with its fill, not lines', () async {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    final clock = FakeClock();
    final model = SurfaceModel(
      surfaceId: 's',
      repository: StrokeRepository(db, deviceId: 'd', clock: clock),
      elementRepository: ElementRepository(db, deviceId: 'd', clock: clock),
      clock: clock,
    );
    addTearDown(model.dispose);
    final tools = ToolSettings()..shapeFill = const ShapeFill.tint(0.25);
    final tool = ShapeTool(
      model: () => model,
      live: LiveInk(),
      tools: tools,
      viewport: ViewportController(),
      clock: clock,
    );
    void drag(Offset from, Offset to) {
      tool
        ..down(ToolPointer(world: from, screen: from))
        ..move(ToolPointer(world: to, screen: to))
        ..up();
    }

    final ink = tools.configOf(InkTool.ballpoint).color;
    tools.shape = ShapeKind.ellipse;
    drag(const Offset(10, 10), const Offset(200, 100));
    tools.shape = ShapeKind.arrow;
    drag(const Offset(10, 300), const Offset(200, 300));
    final strokes = model.strokesNear(const Rect.fromLTWH(0, 0, 400, 400)).toList()
      ..sort(Stroke.paintOrder);
    expect(strokes.first.fill, const ShapeFill.tint(0.25).colorFor(ink));
    expect(strokes.last.style.fill, isNull);
  });
}
