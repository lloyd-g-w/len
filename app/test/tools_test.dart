import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/element_repository.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/domain/text_data.dart';
import 'package:len/ink/elements/text_edit_session.dart';
import 'package:len/ink/selection/ink_clipboard.dart';
import 'package:len/ink/selection/lasso_path.dart';
import 'package:len/ink/selection/selection_controller.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ink/tools/laser.dart';
import 'package:len/ink/tools/lasso_tool.dart';
import 'package:len/ink/tools/pointer_tool.dart';
import 'package:len/ink/tools/shape_tool.dart';
import 'package:len/ink/undo_history.dart';
import 'package:len/ink/viewport.dart';

import 'data_test.dart' show FakeClock;
import 'elements_test.dart' show textBox;
import 'selection_test.dart' show line;

ToolPointer at(Offset p) => ToolPointer(screen: p, world: p);

void main() {
  late AppDatabase db;
  late SurfaceModel model;
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
  });

  tearDown(() {
    model.dispose();
    db.close();
  });

  group('LassoTool', () {
    late SelectionController selection;
    late LassoTool lasso;
    var now = 0;

    setUp(() {
      selection = SelectionController(model: model, clipboard: InkClipboard(), clock: clock);
      lasso = LassoTool(
        selection: selection,
        viewport: ViewportController()..setSize(const Size(800, 600)),
        path: LassoPath(),
        nowMs: () => now,
      );
    });

    tearDown(() => selection.dispose());

    void tap(Offset p) {
      lasso
        ..down(at(p))
        ..up();
    }

    test('tapping selects the item under the pointer; empty space clears', () {
      model.commit(InkEdit(added: [line('a', const Offset(10, 10), const Offset(90, 10))]));
      tap(const Offset(50, 12));
      expect(selection.strokes.single.id, 'a');
      tap(const Offset(400, 400));
      expect(selection.isEmpty, isTrue);
    });

    test('double tap on a text box asks to edit it', () {
      model.commit(InkEdit(addedElements: [textBox('t', const Offset(100, 100))]));
      SurfaceElement? edited;
      lasso.onEditText = (e) => edited = e;
      now = 1000;
      tap(const Offset(150, 110));
      expect(selection.elements.single.id, 't');
      now = 1200;
      tap(const Offset(152, 112));
      expect(edited?.id, 't');
      expect(selection.isEmpty, isTrue);
    });

    test('two slow taps do not edit', () {
      model.commit(InkEdit(addedElements: [textBox('t', const Offset(100, 100))]));
      SurfaceElement? edited;
      lasso.onEditText = (e) => edited = e;
      now = 1000;
      tap(const Offset(150, 110));
      now = 3000;
      tap(const Offset(150, 110));
      expect(edited, isNull);
    });

    testWidgets('a long press on empty space offers to paste', (tester) async {
      Offset? pressedAt;
      lasso.onLongPress = (screen, world) => pressedAt = world;
      lasso.down(at(const Offset(300, 300)));
      await tester.pump(LassoTool.longPress + const Duration(milliseconds: 10));
      lasso.up();
      expect(pressedAt, const Offset(300, 300));
      expect(selection.isEmpty, isTrue);
    });

    test('dragging a selection by a corner scales it in one undo step', () {
      model.commit(InkEdit(added: [line('a', const Offset(100, 100), const Offset(200, 200))]));
      tap(const Offset(150, 150));
      final corner = selection.frame!.rect.bottomRight;
      lasso
        ..down(at(corner))
        ..move(at(corner + const Offset(50, 50)))
        ..move(at(corner + const Offset(100, 100)))
        ..up();
      // The opposite corner (99, 99) stays; the dragged one follows the pointer.
      final scaled = selection.strokes.single;
      const s = 202 / 102;
      expect(scaled.points.first.x, closeTo(99 + 1 * s, 1e-3));
      expect(scaled.points.last.y, closeTo(99 + 101 * s, 1e-3));
      expect(scaled.width, closeTo(2 * s, 1e-3));
      expect(model.history.canUndo, isTrue);
      model.undo();
      expect(model.strokeById('a'), isNotNull);
    });
  });

  group('TextEditSession', () {
    late TextEditSession session;

    setUp(() => session = TextEditSession(model: model, clock: clock));
    tearDown(() => session.dispose());

    test('an empty new box is discarded without an undo step', () {
      session
        ..create(const Offset(10, 10), width: 200, style: const TextData())
        ..end();
      expect(model.loadedElementCount, 0);
      expect(model.history.canUndo, isFalse);
    });

    test('typing then ending stores one element; emptying it deletes it', () {
      session.create(const Offset(10, 10), width: 200, style: const TextData(fontSize: 20));
      session.setData(session.data.copyWith(text: 'a'));
      session.setData(session.data.copyWith(text: 'ab\ncd'));
      final growing = session.current!.rect.height;
      session.end();
      final stored =
          model.elementById(session.current?.id ?? '') ??
          model.elementsNear(const Rect.fromLTWH(0, 0, 400, 400)).single;
      expect(TextData.fromJson(stored.data).text, 'ab\ncd');
      expect(stored.rect.height, growing);
      expect(stored.rect.height, greaterThan(40)); // two lines

      session.edit(stored);
      expect(model.isHidden(stored.id), isTrue);
      session
        ..setData(session.data.copyWith(text: ''))
        ..end();
      expect(model.elementById(stored.id), isNull);
      expect(model.isHidden(stored.id), isFalse);
      model.undo();
      expect(model.elementById(stored.id), isNotNull);
    });

    test('undo underneath an edit abandons it', () {
      final e = textBox('t', Offset.zero);
      model.commit(InkEdit(addedElements: [e]));
      session.edit(model.elementById('t')!);
      model.undo();
      expect(session.isEditing, isFalse);
      expect(model.isHidden('t'), isFalse);
    });

    test('the width can be changed but never below the minimum', () {
      session.create(Offset.zero, width: 200, style: const TextData(text: 'x'));
      session.setRect(const Rect.fromLTWH(5, 5, 2, 10));
      expect(session.current!.rect.left, 5);
      expect(session.current!.rect.width, greaterThanOrEqualTo(24));
    });
  });

  test('ShapeTool.constrain makes squares and 15° lines', () {
    expect(
      ShapeTool.constrain(ShapeKind.rectangle, Offset.zero, const Offset(30, -10)),
      const Offset(30, -30),
    );
    final end = ShapeTool.constrain(ShapeKind.line, Offset.zero, const Offset(100, 4));
    expect(end.dy, closeTo(0, 1e-9));
    expect(end.dx, closeTo(const Offset(100, 4).distance, 1e-9));
  });

  test('LaserTrail fades and expires points', () {
    var now = 0;
    final trail = LaserTrail(nowMs: () => now)
      ..add(Offset.zero, startsSegment: true)
      ..add(const Offset(10, 0));
    now = 500;
    trail.add(const Offset(20, 0));
    expect(LaserTrail.fade(0, 500), closeTo(0.5, 1e-9));
    now = 1200;
    trail.tick();
    expect(trail.points, hasLength(1));
    expect(trail.points.single.startsSegment, isTrue);
    now = 1600;
    trail.tick();
    expect(trail.isEmpty, isTrue);
    trail.dispose();
  });
}
