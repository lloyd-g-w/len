@Tags(['perf'])
library;

import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/features/editor/tools/content_layer.dart';
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

import '../content_tools_ui_test.dart' show openCanvas;
import '../support/canvas_fixtures.dart';
import 'support/big_library.dart';
import 'support/cpu_profile.dart';
import 'support/frame_counts.dart';

/// Connectors at scale: the repair after a pull (`ConnectorRepair`, the
/// `SyncEngine.afterApply` hook) on a canvas of 500 boxes joined by 1,000
/// attached arrows among 5,000 strokes of ink, when one box moved and when
/// nothing a connector cares about changed; and a selection drag of one
/// box with 50 / 200 arrows attached (the followers recomputed per move,
/// and the frame in the editor).
///
/// Run: `tool/heavy.sh nix develop .. -c flutter test test/perf/connectors_perf_test.dart`.
void main() {
  test('repair after a pull: 500 boxes, 1,000 arrows, 5,000 strokes', () async {
    final db = AppDatabase.inMemory();
    final strokes = StrokeRepository(db, deviceId: 'd');
    const surface = 's';
    final diagram = _diagram(surface, columns: 25, rows: 20);
    final ink = [
      for (final s in scribbles(5000, const Rect.fromLTWH(0, 0, 3750, 2400), points: 20))
        _on(s, surface),
    ];
    strokes.save([...diagram, ...ink]);
    final boxes = [
      for (final s in diagram)
        if (s.shape!.kind == ShapeKind.rectangle) s,
    ];
    final repair = ConnectorRepair(strokes);

    // Another device wrote one stroke of ink: nothing to repair.
    final idle = <int>[];
    for (var i = 0; i < 10; i++) {
      final w = Stopwatch()..start();
      final n = repair.repair(RemoteChanges()..addItem(surface, ink[i * 37].id));
      idle.add(w.elapsedMicroseconds);
      expect(n, 0);
    }

    // Another device moved one box without its arrows (theirs were edited
    // meanwhile here): its arrows are brought back onto it. The first
    // repair runs code for the first time (compiled then, in the debug
    // JIT): reported apart, as the drag's warm-up moves are.
    final moved = <int>[];
    var first = 0;
    final profile = const bool.fromEnvironment('PROFILE') ? await CpuProfile.connect() : null;
    for (var i = 0; i <= 20; i++) {
      if (i == 1) await profile?.start();
      final old = boxes[(i * 61 + 26) % boxes.length];
      final now = Stroke(
        id: 'moved$i',
        surfaceId: surface,
        tool: old.tool,
        color: old.color,
        width: old.width,
        points: [for (final p in old.points) StrokePoint(p.x + 7, p.y + 5, p.pressure)],
        createdAt: old.createdAt,
        style: old.style,
        shape: old.shape!.map((p) => p + const Offset(7, 5)).withOrigin(old.shapeId),
      );
      db.transaction(() {
        strokes.delete([old.id]);
        strokes.save([now]);
      });
      final changes = RemoteChanges()
        ..addItem(surface, old.id)
        ..addItem(surface, now.id);
      final w = Stopwatch()..start();
      final n = repair.repair(changes);
      i == 0 ? first = w.elapsedMicroseconds : moved.add(w.elapsedMicroseconds);
      expect(n, greaterThanOrEqualTo(2)); // Its arrows in and out.
      boxes[(i * 61 + 26) % boxes.length] = now;
    }
    await profile?.dump('repair, a box moved', count: 45);

    // Many changes (more than are named): the whole surface is looked at.
    final many = RemoteChanges()..reloadSurface(surface);
    await profile?.start();
    for (var i = 0; i < 10; i++) {
      repair.repair(many);
    }
    await profile?.dump('repair, surface reloaded', count: 45);
    final whole = bestUs(() => repair.repair(many), runs: 10);

    report(
      'CONNECTORS repair, ${diagram.length} shapes + ${ink.length} strokes: '
      'a stroke of ink pulled: ${_stats(idle)}; '
      'a box moved: first ${_ms(first)}, then ${_stats(moved)}; '
      'surface reloaded: best ${_ms(whole)}',
    );
    db.close();
  });

  for (final arrows in [50, 200]) {
    test('drag one box with $arrows arrows: followers per move', () async {
      final db = AppDatabase.inMemory();
      final repository = StrokeRepository(db, deviceId: 'd');
      final model = SurfaceModel(surfaceId: 's', repository: repository);
      final hub = _hub('s', arrows);
      repository.save([
        ...hub,
        for (final s in scribbles(3000, const Rect.fromLTWH(0, 0, 1280, 800), points: 20))
          _on(s, 's'),
      ]);
      model.ensureLoaded(const Rect.fromLTWH(-1000, -1000, 4000, 3000));
      final content = ContentTools(
        model: model,
        viewport: ViewportController()..setSize(const Size(1280, 800)),
        tools: ToolSettings(stylusOnly: false)..tool = EditorTool.lasso,
        live: LiveInk(),
        clipboard: InkClipboard(),
      );
      final selection = content.selection;
      selection.select([model.strokeById('hub')!], const []);
      final frame = selection.frame!;
      var i = 0;
      void move() {
        i++;
        selection.setPreview(Affine.translation(Offset(i % 40 * 1.5, i % 17 * 1.0)), frame);
      }

      for (var k = 0; k < 10; k++) {
        move(); // Warm up.
      }
      if (const bool.fromEnvironment('PROFILE')) {
        final p = (await CpuProfile.connect())!;
        await p.start();
        for (var k = 0; k < 20; k++) {
          move();
        }
        await p.dump('drag $arrows', count: 45);
      }
      final perMove = bestUs(() {
        for (var k = 0; k < 20; k++) {
          move();
        }
      }, runs: 5);
      // Each commit drops the box (and its arrows, as followers) where the
      // drag left it; the next drag picks up the moved box.
      final profile = const bool.fromEnvironment('PROFILE') ? await CpuProfile.connect() : null;
      await profile?.start();
      final commits = <int>[];
      for (var k = 0; k < 5; k++) {
        if (k > 0) {
          final frame = selection.frame!;
          for (var m = 0; m < 3; m++) {
            selection.setPreview(Affine.translation(Offset(m * 2.0 - k, k * 1.5)), frame);
          }
        }
        expect(selection.followers, isNotNull);
        final commit = Stopwatch()..start();
        selection.commitPreview();
        commits.add(commit.elapsedMicroseconds);
        expect(model.strokeById(selection.strokes.single.id)?.shapeId, 'hub');
      }
      await profile?.dump('commit $arrows', count: 90);
      report(
        'CONNECTORS drag, $arrows arrows: setPreview ${_ms(perMove ~/ 20)} a move '
        '(best of 5 × 20); commit ${_stats(commits)} (5 drags)',
      );
      content.dispose();
      model.dispose();
      db.close();
    });

    testWidgets('drag one box with $arrows arrows: a frame in the editor', (tester) async {
      await openCanvas(
        tester,
        seed: (s, nb) => s.strokes.save([
          ..._hub(nb.id, arrows),
          for (final x in scribbles(3000, const Rect.fromLTWH(0, 0, 1280, 800), points: 20))
            _on(x, nb.id),
        ]),
      );
      await settle(() => true);
      await tester.sendKeyEvent(LogicalKeyboardKey.keyL);
      await tester.pump();
      final content = tester.widget<ContentLayer>(find.byType(ContentLayer)).content;
      content.selection.select([content.model.strokeById('hub')!], const []);
      await tester.pump(const Duration(milliseconds: 500));
      final drag = await tester.startGesture(const Offset(600, 400), kind: PointerDeviceKind.mouse);
      await tester.pump(const Duration(milliseconds: 16));
      final frames = await countFrames((i) async {
        await drag.moveTo(Offset(600 + (i % 40) * 3.0, 400 + (i % 13) * 2.0));
        await tester.pump(const Duration(milliseconds: 16));
      }, 60);
      await drag.up();
      await tester.pump(const Duration(seconds: 2));
      final hub = content.model.strokesNear(const Rect.fromLTWH(0, 0, 1280, 800));
      expect(hub.where((s) => s.shapeId == 'hub' && s.id != 'hub'), hasLength(1)); // Moved.
      report('CONNECTORS drag frame, $arrows arrows: $frames');
    }, timeout: const Timeout(Duration(minutes: 4)));
  }
}

/// [columns] × [rows] boxes 60 × 40, 150 × 120 apart, each joined to the
/// next one right and the next one down by an arrow attached at both ends.
List<Stroke> _diagram(String surface, {required int columns, required int rows}) {
  final boxes = <Stroke>[];
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < columns; c++) {
      final at = Offset(c * 150.0, r * 120.0);
      boxes.add(
        _shape(
          'box${boxes.length}',
          surface,
          ShapeBuilder.dragged(ShapeKind.rectangle, at, at + const Offset(60, 40)),
        ),
      );
    }
  }
  final arrows = <Stroke>[];
  Stroke arrow(Stroke from, double out, Stroke to, double into) => _shape(
    'arrow${arrows.length}',
    surface,
    ShapeGeometry(
      ShapeKind.arrow,
      [ShapeAnchors.pointAt(from.shape!, out), ShapeAnchors.pointAt(to.shape!, into)],
      tail: ShapeAttachment(from.id, out),
      tip: ShapeAttachment(to.id, into),
    ),
  );
  for (var r = 0; r < rows; r++) {
    for (var c = 0; c < columns; c++) {
      final box = boxes[r * columns + c];
      // Right side's middle to the next box's left; bottom to the top below
      // (wrapping round, so every box has two arrows out and two in).
      arrows
        ..add(arrow(box, 0.375, boxes[r * columns + (c + 1) % columns], 0.875))
        ..add(arrow(box, 0.625, boxes[(r + 1) % rows * columns + c], 0.125));
    }
  }
  return [...boxes, ...arrows];
}

/// A box (560, 350)–(660, 450), id `hub`, with [count] arrows pointing at
/// it from a ring around it, their tips attached round its outline.
List<Stroke> _hub(String surface, int count) {
  final box = _shape(
    'hub',
    surface,
    ShapeBuilder.dragged(ShapeKind.rectangle, const Offset(560, 350), const Offset(660, 450)),
  );
  return [
    box,
    for (var i = 0; i < count; i++)
      () {
        final at = (i + 0.5) / count;
        final tip = ShapeAnchors.pointAt(box.shape!, at);
        final away = tip - const Offset(610, 400);
        final tail = tip + away / away.distance * (150 + 100 * (i % 3));
        return _shape(
          'spoke$i',
          surface,
          ShapeGeometry(ShapeKind.arrow, [tail, tip], tip: ShapeAttachment('hub', at)),
        );
      }(),
  ];
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

Stroke _on(Stroke s, String surface) => Stroke(
  id: s.id,
  surfaceId: surface,
  tool: s.tool,
  color: s.color,
  width: s.width,
  points: s.points,
  createdAt: s.createdAt + 10,
  style: s.style,
);

String _ms(int us) => '${(us / 1000).toStringAsFixed(2)} ms';

String _stats(List<int> us) {
  final sorted = [...us]..sort();
  return 'best ${_ms(sorted.first)}, median ${_ms(sorted[sorted.length ~/ 2])}, '
      'max ${_ms(sorted.last)}';
}
