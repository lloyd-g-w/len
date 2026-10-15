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
import 'package:len/ink/selection/selection_chrome.dart';
import 'package:len/ink/selection/selection_controller.dart';
import 'package:len/ink/selection/selection_frame.dart';
import 'package:len/ink/shapes/shape_builder.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ink/tools/laser.dart';
import 'package:len/ink/tools/laser_tool.dart';
import 'package:len/ink/tools/lasso_tool.dart';
import 'package:len/ink/tools/pointer_tool.dart';
import 'package:len/ink/tools/shape_tool.dart';
import 'package:len/ink/tools/text_tool.dart';
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

    group('on PDF text (R7-1)', () {
      late _FakeText text;
      setUp(() => lasso.text = text = _FakeText(const Rect.fromLTRB(0, 0, 400, 40)));

      test('a tap on text selects its word; on ink, the ink', () {
        model.commit(InkEdit(added: [line('a', const Offset(10, 20), const Offset(90, 20))]));
        tap(const Offset(200, 20));
        expect(text.log, ['word (200.0, 20.0)']);
        expect(selection.isEmpty, isTrue);
        tap(const Offset(50, 21));
        expect(selection.strokes.single.id, 'a', reason: 'ink over text wins');
        expect(text.log, hasLength(1));
      });

      test('an open drag from text selects text; a loop selects ink', () {
        lasso
          ..down(at(const Offset(100, 20)))
          ..move(at(const Offset(200, 22)))
          ..move(at(const Offset(300, 24)))
          ..up();
        expect(text.log, ['between (100.0, 20.0) (300.0, 24.0) done']);
        model.commit(InkEdit(added: [line('a', const Offset(150, 100), const Offset(200, 100))]));
        text.log.clear();
        for (final p in const [Offset(120, 20), Offset(250, 20), Offset(250, 150)]) {
          p == const Offset(120, 20) ? lasso.down(at(p)) : lasso.move(at(p));
        }
        lasso
          ..move(at(const Offset(120, 150)))
          ..move(at(const Offset(120, 30)))
          ..up();
        expect(selection.strokes.single.id, 'a');
        expect(text.log, isEmpty);
      });

      testWidgets('held on text: the word, then a drag extends it', (tester) async {
        Offset? pasteAt;
        lasso.onLongPress = (screen, world) => pasteAt = world;
        lasso.down(at(const Offset(100, 20)));
        await tester.pump(LassoTool.longPress + const Duration(milliseconds: 10));
        lasso
          ..move(at(const Offset(200, 20)))
          ..up();
        expect(text.log, [
          'word (100.0, 20.0)',
          'between (100.0, 20.0) (200.0, 20.0)',
          'between (100.0, 20.0) (200.0, 20.0) done',
        ]);
        expect(pasteAt, isNull, reason: 'no paste menu on text');
      });
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

    test('a frame past the screen edge keeps its handles inside; they resize without a jump', () {
      model.commit(InkEdit(added: [line('a', const Offset(-50, 100), const Offset(850, 400))]));
      tap(const Offset(400, 250));
      final frame = selection.frame!;
      final before = frame.rect;
      expect(before.right, greaterThan(800));
      // As if the true corner, off screen, had been dragged 100 px left.
      final expected = frame.resized(
        SelectionHandle.bottomRight,
        before.bottomRight - const Offset(100, 0),
      );
      final handle = SelectionChrome.handles(
        selection.frame!,
        lasso.viewport,
      )[SelectionHandle.bottomRight]!;
      expect(handle.dx, 800 - SelectionChrome.edgeInset);
      lasso
        ..down(at(handle))
        ..move(at(handle - const Offset(50, 0)))
        ..move(at(handle - const Offset(100, 0)))
        ..up();
      expect(selection.frame!.rect.right, closeTo(expected.frame.rect.right, 1e-6));
      expect(selection.frame!.rect.left, closeTo(before.left, 1e-6));
    });
  });

  group('TextEditSession', () {
    late TextEditSession session;

    setUp(() => session = TextEditSession(model: model, clock: clock));
    tearDown(() => session.dispose());

    test('a box typed under the last one stays on its page', () {
      // A page 600 × 800 centred in a taller view: below it is in view.
      final viewport = ViewportController(contentBounds: const Rect.fromLTWH(0, 0, 600, 800))
        ..setSize(const Size(1000, 1200));
      final tool = TextTool(session: session, tools: ToolSettings(), viewport: viewport);
      session.lastBox = (surfaceId: model.surfaceId, rect: const Rect.fromLTWH(50, 740, 200, 40));
      expect(viewport.visibleWorld.bottom, greaterThan(900));
      expect(tool.typingUnderLast(), isNull);
      tool.startTyping('x');
      final box = session.current!.rect;
      expect(const Rect.fromLTWH(0, 0, 600, 800).contains(box.center), isTrue, reason: '$box');
      // Under a box higher up: right under it.
      session
        ..discard()
        ..lastBox = (surfaceId: model.surfaceId, rect: const Rect.fromLTWH(50, 100, 200, 40));
      expect(tool.typingUnderLast()!.dx, 50);
    });

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

    test('a wide box edited while zoomed in keeps its width (the screen is no limit)', () {
      session
        ..autoWidthLimit = double.infinity
        ..create(Offset.zero, style: const TextData(fontSize: 20));
      session.setData(session.data.copyWith(text: 'Hello there, a long line'));
      final id = session.current!.id;
      session.end();
      final box = model.elementById(id)!;
      final width = box.rect.width;
      session
        ..autoWidthLimit =
            width /
            2 // zoomed in: the screen shows half of it
        ..edit(box)
        ..setData(session.data.copyWith(text: '${session.data.text}!'));
      expect(session.data.autoWidth, isTrue);
      expect(session.current!.rect.width, greaterThan(width));
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

  test('ShapeTool.constrain makes regular shapes and 15° lines', () {
    expect(
      ShapeTool.constrain(ShapeKind.rectangle, Offset.zero, const Offset(30, -10)),
      const Offset(30, -30),
    );
    // Equilateral triangles and regular stars: equal sides, points on a circle.
    final tri = ShapeBuilder.dragged(
      ShapeKind.triangle,
      Offset.zero,
      ShapeTool.constrain(ShapeKind.triangle, Offset.zero, const Offset(-50, 200)),
    ).points;
    for (var i = 0; i < 3; i++) {
      expect((tri[(i + 1) % 3] - tri[i]).distance, closeTo((tri[1] - tri[0]).distance, 1e-9));
    }
    final star = ShapeBuilder.dragged(
      ShapeKind.star,
      Offset.zero,
      ShapeTool.constrain(ShapeKind.star, Offset.zero, const Offset(300, 40)),
    );
    final u = star.points[1] - star.points[0], v = star.points[2] - star.points[0];
    expect(u.distance, closeTo(v.distance, 1e-9));
    expect(u.distance, greaterThan(150)); // as large as the drag
    final end = ShapeTool.constrain(ShapeKind.line, Offset.zero, const Offset(100, 4));
    expect(end.dy, closeTo(0, 1e-9));
    expect(end.dx, closeTo(const Offset(100, 4).distance, 1e-9));
  });

  test('LaserTrail stamps points on the next frame, fades and expires them', () {
    final trail = LaserTrail()
      ..down(Offset.zero)
      ..move(const Offset(10, 0));
    expect(trail.alphaAt(0), 1);
    trail.tick(10000); // first frame after a long idle: points are fresh
    expect(trail.length, 2);
    trail.move(const Offset(20, 0));
    trail.tick(10500);
    expect(trail.alphaAt(0), closeTo(0.5, 1e-9));
    trail.tick(11200);
    expect(trail.length, 1);
    expect(trail.startsAt(0), isTrue);
    expect(trail.pointAt(0), const Offset(20, 0));
    trail.up();
    trail.tick(11600);
    expect(trail.isEmpty, isTrue);
    expect(trail.isVisible, isTrue, reason: 'the dot fades with the trail');
    trail.tick(12700);
    expect(trail.isVisible, isFalse);
    trail.dispose();
  });

  test('LaserTrail is a fixed-size ring buffer', () {
    final trail = LaserTrail(capacity: 4)..down(Offset.zero);
    for (var i = 1; i < 10; i++) {
      trail.move(Offset(i.toDouble(), 0));
    }
    expect(trail.length, 4);
    expect([for (var i = 0; i < 4; i++) trail.pointAt(i).dx], [6, 7, 8, 9]);
    trail.down(const Offset(50, 0)); // a new stroke overwrites the oldest point
    expect(trail.pointAt(3), const Offset(50, 0));
    expect(trail.startsAt(3), isTrue);
    expect(trail.startsAt(2), isFalse);
    trail.dispose();
  });

  test('laser dot mode keeps no trail; the dot fades after lifting', () {
    final trail = LaserTrail()..config = const LaserConfig(mode: LaserMode.dot);
    trail
      ..down(Offset.zero)
      ..move(const Offset(30, 0))
      ..tick(1000);
    expect(trail.isEmpty, isTrue);
    expect(trail.head, const Offset(30, 0));
    expect(trail.headAlpha, 1);
    trail
      ..up()
      ..tick(2000);
    expect(trail.headAlpha, 1, reason: 'stamped on the first frame after lifting');
    trail.tick(2000 + LaserTrail.dotFade.inMilliseconds / 2);
    expect(trail.headAlpha, closeTo(0.5, 1e-9));
    trail.tick(3000);
    expect(trail.isVisible, isFalse);
    expect(trail.head, isNull);
    trail.dispose();
  });

  test('a hovering mouse shows the laser dot without a trail or frames', () {
    final trail = LaserTrail();
    trail.hover(const Offset(10, 20));
    expect(trail.head, const Offset(10, 20));
    expect(trail.headAlpha, 1);
    expect(trail.isEmpty, isTrue, reason: 'hovering leaves no trail');
    expect(trail.animating, isFalse, reason: 'a still dot needs no frames');
    trail
      ..hover(const Offset(30, 20))
      ..tick(1000);
    expect(trail.headAlpha, 1, reason: 'stays while hovering');
    expect(trail.head, const Offset(30, 20));
    // Pressing draws as usual; lifting with the mouse still there fades
    // until the next hover shows it again.
    trail
      ..down(const Offset(30, 20))
      ..move(const Offset(60, 20))
      ..up();
    expect(trail.animating, isTrue);
    // Leaving the canvas fades the dot.
    trail
      ..hover(const Offset(60, 20))
      ..tick(5000);
    expect(trail.headAlpha, 1);
    trail
      ..hover(null)
      ..tick(6000) // Stamped on the first frame after leaving, like a lift.
      ..tick(6000 + trail.lifetime.inMilliseconds / 2);
    expect(trail.headAlpha, closeTo(0.5, 1e-9));
    trail.tick(20000);
    expect(trail.isVisible, isFalse);
    trail.dispose();
  });

  test('the laser tool records samples a few pixels apart; the dot follows all', () {
    final trail = LaserTrail();
    final tool = LaserTool(trail, config: () => const LaserConfig(size: 9))
      ..down(const ToolPointer(screen: Offset.zero, world: Offset.zero))
      ..move(const ToolPointer(screen: Offset(0.5, 0), world: Offset(0.5, 0)))
      ..move(const ToolPointer(screen: Offset(3, 0), world: Offset(3, 0)));
    expect(trail.config.size, 9);
    expect(trail.length, 2);
    expect(trail.head, const Offset(3, 0));
    tool.up();
    trail.dispose();
  });

  test('laser settings persist with the tool settings', () {
    final store = SettingsRepository(db);
    const config = LaserConfig(
      mode: LaserMode.dot,
      color: 0xFF2F8BFF,
      size: 10,
      duration: Duration(milliseconds: 2500),
    );
    final tools = ToolSettings(store: store)..laser = config;
    tools.dispose();
    final restored = ToolSettings(store: store);
    expect(restored.laser, config);
    restored.dispose();
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

/// PDF text filling [area], recording what the lasso asks of it.
class _FakeText implements LassoText {
  _FakeText(this.area);

  final Rect area;
  final List<String> log = [];

  String _p(Offset o) => '(${o.dx}, ${o.dy})';

  @override
  bool hasTextAt(Offset screen) => area.contains(screen);

  @override
  void selectWordAt(Offset screen) => log.add('word ${_p(screen)}');

  @override
  void selectBetween(Offset from, Offset to, {required bool done}) =>
      log.add('between ${_p(from)} ${_p(to)}${done ? ' done' : ''}');
}
