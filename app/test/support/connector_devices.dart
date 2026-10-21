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
import 'package:len/ink/selection/connectors.dart';
import 'package:len/ink/selection/ink_clipboard.dart';
import 'package:len/ink/shapes/shape_anchors.dart';
import 'package:len/ink/shapes/shape_builder.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/ink/tool_settings.dart';
import 'package:len/ink/tools/content_tools.dart';
import 'package:len/ink/viewport.dart';
import 'package:len/sync/remote_changes.dart';
import 'package:len/sync/sync_engine.dart';

import 'fake_server.dart';

// Devices editing one page of shapes and connectors, synced through a fake
// server (connector_sync_test, connector_convergence_test).

/// The time all devices of a run share.
class SharedTime {
  int now = 1000;
}

class _DeviceClock extends Clock {
  _DeviceClock(this.time, this.prefix);

  final SharedTime time;
  final String prefix;
  int _ids = 0;

  @override
  int nowMs() => time.now += 10;

  @override
  String newId() => '$prefix${_ids++}';
}

const _all = Rect.fromLTWH(-1000, -1000, 3000, 3000);

/// An installation with the page open in an editor; its stroke ids start
/// with [prefix].
class ConnectorDevice {
  ConnectorDevice(this.server, SharedTime time, String prefix) {
    s = AppServices.create(AppDatabase.inMemory(), clock: _DeviceClock(time, prefix));
    addTearDown(s.dispose);
  }

  final FakeServer server;
  late final AppServices s;
  late final SurfaceModel model;
  late final ContentTools content;

  /// Syncs, refreshing the editor with what changed.
  Future<RemoteChanges> sync() async {
    final changes = await s.sync.engine.sync(apiFor(server));
    if (_page == null) return changes;
    final ids = changes.itemsOf(page);
    if (ids != null) model.refreshItems(ids);
    if (changes.strokeSurfaces.contains(page) && ids == null) model.reload();
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

  /// Moves the selection by [by] (a drag).
  void move(Offset by) {
    final s = content.selection;
    s.setPreview(Affine.translation(by), s.frame!);
    s.commitPreview();
  }
}

/// A shape stroke [id] on [surface].
Stroke shapeOn(String id, String surface, ShapeGeometry shape, {int color = 0xFF1C7ED6}) => Stroke(
  id: id,
  surfaceId: surface,
  tool: InkTool.ballpoint,
  color: color,
  width: 2,
  points: ShapeBuilder.pointsOf(shape),
  createdAt: 1,
  style: ShapeBuilder.styleFor(const StrokeStyle(unit: 1)),
  shape: shape,
);

/// [n] devices (prefixes a, b, c, …) with a page holding a box and an
/// arrow attached to the middle of its left side, synced and open.
Future<List<ConnectorDevice>> connectorDevices([int n = 2]) async {
  final time = SharedTime(), server = FakeServer();
  final devices = [
    for (var i = 0; i < n; i++) ConnectorDevice(server, time, String.fromCharCode(0x61 + i)),
  ];
  final a = devices.first;
  final notebook = a.s.notebooks.create(
    title: 'Diagram',
    kind: NotebookKind.paged,
    paper: PaperStyle.blank,
    coverColor: 0,
  );
  final page = a.s.pages.pagesOf(notebook.id).single.id;
  a.s.strokes.save([
    shapeOn(
      'box',
      page,
      ShapeBuilder.dragged(ShapeKind.rectangle, const Offset(300, 200), const Offset(400, 300)),
    ),
    shapeOn(
      'arrow',
      page,
      ShapeGeometry(ShapeKind.arrow, const [
        Offset(100, 250),
        Offset(300, 250),
      ], tip: const ShapeAttachment('box', 0.875)),
    ),
  ]);
  for (final d in devices) {
    await d.sync();
  }
  for (final d in devices) {
    d.open(page);
  }
  return devices;
}

/// Every arrow's tip lies on the one box, attached to it.
void expectOnBox(ConnectorDevice d) {
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

/// Every attached end on [d]'s page whose shape is there sits on it.
void expectConnected(ConnectorDevice d) {
  final stored = d.stored;
  for (final line in stored) {
    final shape = line.shape;
    if (shape == null || !shape.isAttached) continue;
    for (final end in [0, 1]) {
      final target = Connectors.targetOf(shape, end, stored);
      if (target == null) continue;
      expect(Connectors.sits(shape, end, target.shape), isTrue, reason: '${line.id} end $end');
    }
  }
}

/// Every shape on [d]'s page has one live stroke.
void expectOneStrokeEach(ConnectorDevice d) {
  final ids = [for (final s in d.stored) s.shapeId];
  expect(ids.toSet(), hasLength(ids.length), reason: 'twins left: $ids');
}

/// The devices hold the same strokes, everything pushed, and syncing
/// again changes nothing.
Future<void> expectSettled(List<ConnectorDevice> devices) async {
  Set<String> ids(ConnectorDevice d) => {for (final x in d.stored) x.id};
  for (final d in devices) {
    expect(ids(d), ids(devices.first));
    expect(d.dirty, isEmpty);
  }
  for (final d in [...devices, devices.first]) {
    final changes = await d.sync();
    expect(changes.strokeSurfaces, isEmpty);
  }
}
