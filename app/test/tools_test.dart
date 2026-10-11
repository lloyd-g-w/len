import 'dart:convert';
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/element_repository.dart';
import 'package:len/data/settings_repository.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/domain/text/text_data.dart';
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
        ..create(const Offset(10, 10), style: const TextData())
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
      session.setWidth(5, 2);
      expect(session.current!.rect.left, 5);
      expect(session.current!.rect.width, greaterThanOrEqualTo(24));
    });

    test('a new box grows with its text, then wraps at its limit', () {
      session
        ..autoWidthLimit = 300
        ..create(Offset.zero, style: const TextData(fontSize: 20));
      expect(session.data.autoWidth, isTrue);
      session.setData(session.data.copyWith(text: 'Hi'));
      final narrow = session.current!.rect.width;
      session.setData(session.data.copyWith(text: 'Hello there'));
      expect(session.current!.rect.width, greaterThan(narrow));
      expect(session.current!.rect.height, lessThan(30)); // one line
      session.setData(session.data.copyWith(text: 'Hello there, a much longer line ' * 3));
      expect(session.current!.rect.width, 300);
      expect(session.data.autoWidth, isFalse);
      expect(session.current!.rect.height, greaterThan(40)); // wraps
    });

    test('resizing a box ends auto width', () {
      session.create(Offset.zero, style: const TextData(text: 'x'));
      session.setData(session.data.copyWith(text: 'abc'));
      session.setWidth(0, 120);
      expect(session.data.autoWidth, isFalse);
      session.setData(session.data.copyWith(text: 'abcd'));
      expect(session.current!.rect.width, 120);
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

  test('LaserTrail stamps points on the next frame, fades and expires them', () {
    final trail = LaserTrail()
      ..add(Offset.zero, startsSegment: true)
      ..add(const Offset(10, 0));
    expect(LaserTrail.fade(trail.points.first.time, 0), 1);
    trail.tick(10000); // first frame after a long idle: points are fresh
    expect(trail.points, hasLength(2));
    trail.add(const Offset(20, 0));
    trail.tick(10500);
    expect(LaserTrail.fade(trail.points.first.time, trail.now), closeTo(0.5, 1e-9));
    trail.tick(11200);
    expect(trail.points, hasLength(1));
    expect(trail.points.single.startsSegment, isTrue);
    trail.tick(11600);
    expect(trail.isEmpty, isTrue);
    trail.dispose();
  });

  test('shape and text defaults persist with the tool settings', () {
    final store = SettingsRepository(db);
    final tools = ToolSettings(store: store)
      ..shape = ShapeKind.star
      ..textStyle = const TextData(text: 'ignored', fontSize: 40, font: TextFont.lora);
    expect(tools.tool, EditorTool.shape);
    expect(tools.textStyle.text, '');
    tools.dispose(); // flushes the debounced save
    final restored = ToolSettings(store: store);
    expect(restored.shape, ShapeKind.star);
    expect(restored.textStyle, const TextData(fontSize: 40, font: TextFont.lora));
    restored.dispose();
  });

  test('preset-era settings keep their shape and text defaults and gain slots', () {
    final store = SettingsRepository(db)
      ..toolPrefs = jsonEncode({
        'penType': 'fountain',
        'pens': {
          'fountain': {
            'presets': [
              {'c': 0xFF112233, 'w': 2.0},
              {'c': 0xFF445566, 'w': 4.0},
            ],
            'selected': 1,
          },
        },
        'shape': 'triangle',
        'text': const TextData(fontSize: 30, font: TextFont.mono).toJson(),
      });
    final tools = ToolSettings(store: store);
    expect(tools.shape, ShapeKind.triangle);
    expect(tools.textStyle, const TextData(fontSize: 30, font: TextFont.mono));
    final pen = tools.configOf(InkTool.ballpoint);
    expect(pen.color, 0xFF445566);
    expect(pen.colors, containsAll([0xFF112233, 0xFF445566]));
    tools.dispose();
  });

  test('tools without ink switch to the pen when a quick colour or width is picked', () {
    final tools = ToolSettings()..tool = EditorTool.lasso;
    tools.selectColor(1);
    expect(tools.tool, EditorTool.pen);
    tools
      ..tool = EditorTool.text
      ..selectWidth(0);
    expect(tools.tool, EditorTool.pen);
    tools
      ..tool = EditorTool.shape
      ..selectColor(0)
      ..stepWidth(1);
    expect(tools.tool, EditorTool.shape);
    expect(tools.activeInk, InkTool.ballpoint);
  });
}
