import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/element_repository.dart';
import 'package:len/data/settings_repository.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/domain/surface_element.dart';
import 'package:len/ink/selection/ink_clipboard.dart';
import 'package:len/ink/selection/lasso.dart';
import 'package:len/ink/selection/lasso_path.dart';
import 'package:len/ink/selection/selection_controller.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ink/tools/lasso_tool.dart';
import 'package:len/ink/tools/pointer_tool.dart';
import 'package:len/ink/undo_history.dart';
import 'package:len/ink/viewport.dart';

import 'data_test.dart' show FakeClock;
import 'elements_test.dart' show textBox;
import 'selection_test.dart' show line;

const _square = [Offset(0, 0), Offset(100, 0), Offset(100, 100), Offset(0, 100)];

Lasso _lasso({
  LassoCover cover = LassoCover.mostly,
  Set<LassoKind> kinds = const {...LassoKind.values},
}) => Lasso(
  _square,
  config: LassoConfig(cover: cover, kinds: kinds),
);

Stroke _highlight(String id, Offset from, Offset to) {
  final s = line(id, from, to);
  return Stroke(
    id: s.id,
    surfaceId: s.surfaceId,
    tool: InkTool.highlighter,
    color: s.color,
    width: 12,
    points: s.points,
    createdAt: 1,
  );
}

SurfaceElement _image(String id, Rect rect, {double z = 1}) => SurfaceElement(
  id: id,
  surfaceId: 's',
  type: 'image',
  rect: rect,
  z: z,
  createdAt: 1,
  data: const {},
);

ToolPointer _at(Offset p) => ToolPointer(screen: p, world: p);

void main() {
  group('Lasso cover', () {
    // Inside; three-quarters inside; a quarter inside; crossing with no
    // point inside (two points, the segment runs through the lasso).
    final inside = line('in', const Offset(10, 50), const Offset(90, 50));
    final most = line('most', const Offset(40, 30), const Offset(120, 30));
    final little = line('little', const Offset(80, 70), const Offset(160, 70));
    final across = line('across', const Offset(-20, 40), const Offset(140, 40), points: 2);
    final outside = line('out', const Offset(120, 10), const Offset(180, 10));

    List<String> picks(Lasso lasso) => [
      for (final s in [inside, most, little, across, outside])
        if (lasso.selectsStroke(s)) s.id,
    ];

    test('mostly (the default) takes strokes at least half inside', () {
      expect(picks(Lasso(_square)), ['in', 'most', 'across']);
    });

    test('whole takes only strokes entirely inside', () {
      expect(picks(_lasso(cover: LassoCover.whole)), ['in']);
    });

    test('touching takes any stroke with a part inside or crossing the outline', () {
      expect(picks(_lasso(cover: LassoCover.touching)), ['in', 'most', 'little', 'across']);
    });

    test('whole needs no crossing: both ends inside a concave lasso is not enough', () {
      // A U: the stroke from one arm to the other crosses the notch.
      final u = Lasso(const [
        Offset(0, 0),
        Offset(30, 0),
        Offset(30, 70),
        Offset(70, 70),
        Offset(70, 0),
        Offset(100, 0),
        Offset(100, 100),
        Offset(0, 100),
      ], config: const LassoConfig(cover: LassoCover.whole));
      expect(u.selectsStroke(line('bridge', const Offset(15, 20), const Offset(85, 20))), isFalse);
      expect(u.selectsStroke(line('base', const Offset(15, 85), const Offset(85, 85))), isTrue);
    });

    test('elements: whole needs every corner, touching any overlap', () {
      final within = textBox('within', const Offset(10, 10), width: 50);
      final half = textBox('half', const Offset(70, 10), width: 50);
      final edge = textBox('edge', const Offset(90, 60), width: 60);
      final apart = textBox('apart', const Offset(150, 10), width: 30);
      List<String> picks(Lasso lasso) => [
        for (final e in [within, half, edge, apart])
          if (lasso.selectsElement(e)) e.id,
      ];
      expect(picks(Lasso(_square)), ['within', 'half']);
      expect(picks(_lasso(cover: LassoCover.whole)), ['within']);
      expect(picks(_lasso(cover: LassoCover.touching)), ['within', 'half', 'edge']);
    });

    test('touching: a lasso inside a box takes it, inside a backdrop image not', () {
      final small = Lasso(const [
        Offset(40, 40),
        Offset(60, 40),
        Offset(60, 60),
      ], config: const LassoConfig(cover: LassoCover.touching));
      expect(small.selectsElement(_image('above', const Rect.fromLTWH(0, 0, 100, 100))), isTrue);
      expect(
        small.selectsElement(_image('below', const Rect.fromLTWH(0, 0, 100, 100), z: -1)),
        isFalse,
      );
    });
  });

  test('touching: a lasso inside a filled shape takes it, inside an empty outline not', () {
    Stroke box(String id, {int? fill}) => Stroke(
      id: id,
      surfaceId: 's',
      tool: InkTool.ballpoint,
      color: 0xFF000000,
      width: 2,
      style: const StrokeStyle().withFill(fill),
      points: [
        for (final p in const [
          Offset(-50, -50),
          Offset(150, -50),
          Offset(150, 150),
          Offset(-50, 150),
          Offset(-50, -50),
        ])
          StrokePoint(p.dx, p.dy, 0.5),
      ],
      createdAt: 1,
    );
    final lasso = _lasso(cover: LassoCover.touching);
    expect(lasso.selectsStroke(box('filled', fill: 0x8000FF00)), isTrue);
    expect(lasso.selectsStroke(box('empty')), isFalse);
    expect(Lasso(_square).selectsStroke(box('filled', fill: 0x8000FF00)), isFalse);
  });

  group('Lasso kinds', () {
    final pen = line('pen', const Offset(10, 20), const Offset(90, 20));
    final marker = _highlight('marker', const Offset(10, 40), const Offset(90, 40));
    final box = textBox('box', const Offset(10, 50), width: 50);
    final picture = _image('picture', const Rect.fromLTWH(20, 60, 40, 30));
    final link = SurfaceElement(
      id: 'link',
      surfaceId: 's',
      type: 'link',
      rect: const Rect.fromLTWH(70, 70, 20, 20),
      z: 1,
      createdAt: 1,
      data: const {},
    );

    List<String> picks(Set<LassoKind> kinds) {
      final lasso = _lasso(kinds: kinds);
      return [
        for (final s in [pen, marker])
          if (lasso.selectsStroke(s)) s.id,
        for (final e in [box, picture, link])
          if (lasso.selectsElement(e)) e.id,
      ];
    }

    test('only the kinds turned on are selected; links go with images', () {
      expect(picks({...LassoKind.values}), ['pen', 'marker', 'box', 'picture', 'link']);
      expect(picks({LassoKind.ink}), ['pen']);
      expect(picks({LassoKind.highlighter}), ['marker']);
      expect(picks({LassoKind.text}), ['box']);
      expect(picks({LassoKind.images}), ['picture', 'link']);
      expect(picks({LassoKind.ink, LassoKind.text}), ['pen', 'box']);
    });

    test('a shifted lasso (another page) keeps its options', () {
      final shifted = _lasso(
        cover: LassoCover.whole,
        kinds: {LassoKind.text},
      ).shifted(const Offset(0, 10));
      expect(shifted.config, const LassoConfig(cover: LassoCover.whole, kinds: {LassoKind.text}));
    });
  });

  group('LassoConfig', () {
    test('round-trips through JSON; bad parts take their defaults', () {
      const config = LassoConfig(
        shape: LassoShape.rectangle,
        cover: LassoCover.touching,
        kinds: {LassoKind.ink, LassoKind.images},
      );
      expect(LassoConfig.fromJson(config.toJson()), config);
      expect(LassoConfig.fromJson({'shape': 'star', 'cover': 1, 'kinds': []}), const LassoConfig());
      expect(LassoConfig.fromJson('nonsense'), const LassoConfig());
    });

    test('persists with the tool settings and is adopted by linked tools', () {
      final db = AppDatabase.inMemory();
      addTearDown(db.close);
      final store = SettingsRepository(db);
      const config = LassoConfig(shape: LassoShape.rectangle, kinds: {LassoKind.highlighter});
      final tools = ToolSettings(store: store)..lasso = config;
      tools.dispose();
      final restored = ToolSettings(store: store);
      expect(restored.lasso, config);
      final linked = ToolSettings()..adopt(restored);
      expect(linked.lasso, config);
      restored.dispose();
      linked.dispose();
    });
  });

  group('LassoTool with options', () {
    late AppDatabase db;
    late SurfaceModel model;
    late SelectionController selection;
    late LassoPath path;
    var config = const LassoConfig();
    late LassoTool tool;

    setUp(() {
      db = AppDatabase.inMemory();
      final clock = FakeClock();
      model = SurfaceModel(
        surfaceId: 's',
        repository: StrokeRepository(db, deviceId: 'd', clock: clock),
        elementRepository: ElementRepository(db, deviceId: 'd', clock: clock),
        clock: clock,
      );
      selection = SelectionController(model: model, clipboard: InkClipboard(), clock: clock);
      path = LassoPath();
      config = const LassoConfig();
      tool = LassoTool(
        selection: selection,
        viewport: ViewportController()..setSize(const Size(800, 600)),
        path: path,
        config: () => config,
      );
      model.commit(
        InkEdit(
          added: [
            line('a', const Offset(20, 20), const Offset(80, 20)),
            _highlight('h', const Offset(20, 60), const Offset(80, 60)),
          ],
          addedElements: [textBox('t', const Offset(200, 20), width: 60)],
        ),
      );
    });

    tearDown(() {
      selection.dispose();
      path.dispose();
      model.dispose();
      db.close();
    });

    void drag(List<Offset> points, {void Function()? whileDown}) {
      tool.down(_at(points.first));
      for (final p in points.skip(1)) {
        tool.move(_at(p));
      }
      whileDown?.call();
      tool.up();
    }

    test('a rectangle drag selects what its rectangle encloses', () {
      config = const LassoConfig(shape: LassoShape.rectangle);
      drag(
        const [Offset(10, 10), Offset(50, 40), Offset(90, 30)],
        whileDown: () => expect(path.points, const [
          Offset(10, 10),
          Offset(90, 10),
          Offset(90, 30),
          Offset(10, 30),
        ]),
      );
      expect(selection.strokes.map((s) => s.id), ['a']);
      expect(path.isEmpty, isTrue);
      // Dragged from the opposite corner, up and left.
      drag(const [Offset(300, 70), Offset(240, 50), Offset(10, 0)]);
      expect(selection.strokes.map((s) => s.id), unorderedEquals(['a', 'h']));
      expect(selection.elements.single.id, 't');
    });

    test('the kinds apply to loops and taps', () {
      config = const LassoConfig(kinds: {LassoKind.highlighter});
      drag(const [Offset(0, 0), Offset(300, 0), Offset(300, 100), Offset(0, 100), Offset(0, 5)]);
      expect(selection.strokes.map((s) => s.id), ['h']);
      expect(selection.elements, isEmpty);
      selection.clear(); // Its handles reach up to the pen line.
      // A tap on the pen line or the box selects nothing; on the highlight, it.
      for (final p in const [Offset(50, 20), Offset(220, 30)]) {
        tool
          ..down(_at(p))
          ..up();
        expect(selection.isEmpty, isTrue, reason: '$p');
      }
      tool
        ..down(_at(const Offset(50, 60)))
        ..up();
      expect(selection.strokes.single.id, 'h');
    });

    test('a rectangle from PDF text that takes no ink selects the text', () {
      config = const LassoConfig(shape: LassoShape.rectangle);
      final text = _FakeText();
      tool.text = text;
      drag(const [Offset(400, 300), Offset(450, 320), Offset(500, 340)]);
      expect(selection.isEmpty, isTrue);
      expect(text.spans, [(const Offset(400, 300), const Offset(500, 340))]);
      // Around ink, the ink wins.
      drag(const [Offset(400, 300), Offset(200, 100), Offset(10, 10)]);
      expect(selection.strokes.map((s) => s.id), unorderedEquals(['a', 'h']));
      expect(text.spans, hasLength(1));
    });

    test('options are read when a gesture starts', () {
      config = const LassoConfig(cover: LassoCover.touching);
      // A loop around the left half of both strokes.
      drag(const [Offset(0, 0), Offset(30, 0), Offset(30, 80), Offset(0, 80), Offset(0, 5)]);
      expect(selection.strokes.map((s) => s.id), unorderedEquals(['a', 'h']));
      selection.clear();
      config = const LassoConfig(cover: LassoCover.whole);
      drag(const [Offset(0, 0), Offset(30, 0), Offset(30, 80), Offset(0, 80), Offset(0, 5)]);
      expect(selection.isEmpty, isTrue);
    });
  });
}

/// PDF text everywhere right of x 300.
class _FakeText implements LassoText {
  final spans = <(Offset, Offset)>[];

  @override
  bool hasTextAt(Offset screen) => screen.dx > 300;

  @override
  void selectWordAt(Offset screen) {}

  @override
  void selectBetween(Offset from, Offset to, {required bool done}) {
    if (done) spans.add((from, to));
  }
}
