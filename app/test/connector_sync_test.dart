import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/core/clock.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/surface_copier.dart';
import 'package:len/data/syncable.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/geometry/affine.dart';
import 'package:len/ink/input/live_ink.dart';
import 'package:len/ink/selection/connector_repair.dart';
import 'package:len/ink/selection/ink_clipboard.dart';
import 'package:len/ink/shapes/shape_anchors.dart';
import 'package:len/ink/shapes/shape_builder.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ink/tools/content_tools.dart';
import 'package:len/ink/viewport.dart';
import 'package:len/sync/remote_changes.dart';
import 'package:len/sync/sync_engine.dart';
import 'package:uuid/uuid.dart';

import 'support/fake_server.dart';

// Connectors edited on two devices at once: one moves the box, the other
// edits or draws its arrow. Arrows name the box by its identity across
// edits (`Stroke.shapeId`), and every device applying the other's changes
// brings ends left off it back on (`ConnectorRepair`): the same repair
// everywhere, written once, no undo step, no back and forth.

class _Time {
  int now = 1000;
}

class _DeviceClock extends Clock {
  _DeviceClock(this.time, this.prefix);

  final _Time time;
  final String prefix;
  int _ids = 0;

  @override
  int nowMs() => time.now += 10;

  @override
  String newId() => '$prefix${_ids++}';
}

const _all = Rect.fromLTWH(-1000, -1000, 3000, 3000);

/// An installation with the page open in an editor.
class _Device {
  _Device(this.server, _Time time, String prefix) {
    s = AppServices.create(AppDatabase.inMemory(), clock: _DeviceClock(time, prefix));
    addTearDown(s.dispose);
  }

  final FakeServer server;
  late final AppServices s;
  late final SurfaceModel model;
  late final ContentTools content;

  Future<RemoteChanges> sync() async {
    final changes = await s.sync.engine.sync(apiFor(server));
    if (_page == null) return changes;
    final ids = changes.itemsOf(page);
    if (ids != null) model.refreshItems(ids);
    return changes;
  }

  String? _page;
  String get page => _page!;

  void open(String page) {
    _page = page;
    model = SurfaceModel(surfaceId: page, repository: s.strokes, clock: s.clock);
    model.ensureLoaded(_all);
    final live = LiveInk();
    content = ContentTools(
      model: model,
      viewport: ViewportController()..setSize(const Size(800, 600)),
      tools: ToolSettings(stylusOnly: false)..tool = EditorTool.lasso,
      live: live,
      clipboard: InkClipboard(),
    );
    addTearDown(() {
      content.dispose();
      model.dispose();
    });
  }

  /// The live strokes stored on the page.
  List<Stroke> get stored => SurfaceCopier(s.strokes).loadAll(page);

  List<Stroke> get arrows => [
    for (final x in stored)
      if (x.shape!.kind == ShapeKind.arrow) x,
  ];
  Stroke get box => stored.singleWhere((x) => x.shape!.kind == ShapeKind.rectangle);

  List<SyncRecord> get dirty => [
    for (final store in s.sync.engine.stores) ...store.dirtyRecords(1000),
  ];

  /// Edits [stroke] (as loaded in the editor) with the lasso.
  void edit(Stroke Function() stroke, void Function(ContentTools c) edit) {
    content.selection.select([model.strokeById(stroke().id)!], const []);
    edit(content);
    content.selection.clear();
    model.flush();
  }

  void move(Offset by) {
    final s = content.selection;
    s.setPreview(Affine.translation(by), s.frame!);
    s.commitPreview();
  }
}

Stroke _shape(String id, String surface, ShapeGeometry shape) => Stroke(
  id: id,
  surfaceId: surface,
  tool: InkTool.ballpoint,
  color: 0xFF1C7ED6,
  width: 2,
  points: ShapeBuilder.pointsOf(shape),
  createdAt: 1,
  style: ShapeBuilder.styleFor(const StrokeStyle(unit: 1)),
  shape: shape,
);

/// Devices a and b with a page holding a box and an arrow attached to the
/// middle of its left side, synced.
Future<(_Device, _Device)> _devices() async {
  final time = _Time(), server = FakeServer();
  final a = _Device(server, time, 'a'), b = _Device(server, time, 'b');
  final n = a.s.notebooks.create(
    title: 'Diagram',
    kind: NotebookKind.paged,
    paper: PaperStyle.blank,
    coverColor: 0,
  );
  final page = a.s.pages.pagesOf(n.id).single.id;
  a.s.strokes.save([
    _shape(
      'box',
      page,
      ShapeBuilder.dragged(ShapeKind.rectangle, const Offset(300, 200), const Offset(400, 300)),
    ),
    _shape(
      'arrow',
      page,
      ShapeGeometry(ShapeKind.arrow, const [
        Offset(100, 250),
        Offset(300, 250),
      ], tip: const ShapeAttachment('box', 0.875)),
    ),
  ]);
  await a.sync();
  await b.sync();
  a.open(page);
  b.open(page);
  return (a, b);
}

/// Every arrow's tip lies on the one box, attached to it.
void _expectOnBox(_Device d) {
  final box = d.box;
  for (final arrow in d.arrows) {
    final tip = arrow.shape!.tip!;
    expect(tip.id, box.shapeId);
    expect(
      arrow.shape!.points[1],
      offsetMoreOrLessEquals(ShapeAnchors.pointAt(box.shape!, tip.at), epsilon: 1e-3),
    );
  }
}

/// Both devices hold the same strokes, everything pushed, and syncing
/// again changes nothing.
Future<void> _expectSettled(_Device a, _Device b) async {
  Set<String> ids(_Device d) => {for (final x in d.stored) x.id};
  expect(ids(a), ids(b));
  expect(a.dirty, isEmpty);
  expect(b.dirty, isEmpty);
  for (final d in [a, b, a]) {
    final changes = await d.sync();
    expect(changes.strokeSurfaces, isEmpty);
  }
}

void main() {
  test('a box moved on one device while its arrow is recoloured on the other', () async {
    final (a, b) = await _devices();
    a.edit(() => a.box, (c) => a.move(const Offset(0, 60)));
    b.edit(() => b.arrows.single, (c) => c.selection.recolor(0xFFE03131));
    expect(b.arrows.single.shape!.tip!.id, 'box');
    final steps = b.model.history.recorded;

    await a.sync();
    final changes = await b.sync(); // Brings the moved box: b repairs its arrow.
    await a.sync();

    for (final d in [a, b]) {
      _expectOnBox(d);
      // A's arrow moved with the box; b's recoloured one brought onto it.
      expect({for (final x in d.arrows) x.color}, {0xFF1C7ED6, 0xFFE03131});
    }
    final repaired = b.arrows.firstWhere((x) => x.color == 0xFFE03131);
    expect(changes.itemsOf(b.page), contains(repaired.id));
    // The editor shows it, and has no undo step of it.
    expect(b.model.strokeById(repaired.id), isNotNull);
    expect(b.model.history.recorded, steps);
    await _expectSettled(a, b);
  });

  test('an arrow drawn to the box on one device while it moves on the other', () async {
    final (a, b) = await _devices();
    a.edit(() => a.box, (c) => a.move(const Offset(40, 80)));
    b.s.strokes.save([
      _shape(
        'new',
        b.page,
        ShapeGeometry(
          ShapeKind.arrow,
          const [Offset(350, 50), Offset(350, 200)],
          tip: const ShapeAttachment('box', 0.125), // the top side's middle
        ),
      ),
    ]);
    await b.sync();
    await a.sync(); // a repairs b's arrow onto the box it moved.
    await b.sync();
    for (final d in [a, b]) {
      expect(d.arrows, hasLength(2));
      _expectOnBox(d);
    }
    await _expectSettled(a, b);
  });

  test('two devices repairing the same arrow at once write one stroke', () async {
    final (a, b) = await _devices();
    a.edit(() => a.box, (c) => a.move(const Offset(0, 60)));
    b.edit(() => b.arrows.single, (c) => c.selection.recolor(0xFFE03131));
    // b pulls a's move but does not get to repair before a does.
    final engine = b.s.sync.engine;
    final repair = engine.afterApply;
    engine.afterApply = null;
    await a.sync();
    final missed = await b.sync();
    engine.afterApply = repair;
    await a.sync(); // a repairs b's arrow and pushes it.
    final mine = ConnectorRepair(b.s.strokes).repair(missed);
    expect(mine, 1); // b repairs it too, the same way.
    await b.sync();
    await a.sync();
    for (final d in [a, b]) {
      expect(d.arrows, hasLength(2)); // a's and the one repaired, once.
      _expectOnBox(d);
    }
    await _expectSettled(a, b);
  });

  test('ends attached to shapes not on the page, or sitting, are left alone', () {
    final box = _shape(
      'box',
      'p',
      ShapeBuilder.dragged(ShapeKind.rectangle, const Offset(0, 0), const Offset(10, 10)),
    );
    final sitting = _shape(
      'sitting',
      'p',
      ShapeGeometry(ShapeKind.line, [
        const Offset(-20, 5),
        ShapeAnchors.pointAt(box.shape!, 0.875),
      ], tip: const ShapeAttachment('box', 0.875)),
    );
    final stray = _shape(
      'stray',
      'p',
      ShapeGeometry(ShapeKind.line, const [
        Offset(50, 50),
        Offset(60, 60),
      ], tail: const ShapeAttachment('gone', 0.5)),
    );
    expect(ConnectorRepair.repairsOn([box, sitting, stray]), isEmpty);
    // Two strokes of one shape (edited on two devices at once): the one
    // the end sits on keeps it.
    final twin = _shape('twin', 'p', box.shape!.map((p) => p + const Offset(100, 0)));
    final named = _shape('box2', 'p', twin.shape!.withOrigin('box'));
    expect(ConnectorRepair.repairsOn([box, named, sitting]), isEmpty);
    // Off both: the stroke of that very id.
    final off = _shape('off', 'p', sitting.shape!.withPoint(1, const Offset(-5, 40)));
    final (line, fixed) = ConnectorRepair.repairsOn([named, box, off]).single;
    expect(line.id, 'off');
    expect(fixed.shape!.points[1], ShapeAnchors.pointAt(box.shape!, 0.875));
    expect(fixed.id, ConnectorRepair.idOf(off, null, box));
    // A UUID v5 in a fixed namespace, as the uuid package makes them.
    expect(fixed.id, const Uuid().v5('6f1c2b0e-4f5d-5c8a-9a37-2d8e1c4b7a10', 'off>|box'));
  });
}
