import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/connector_queries.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/selection/connector_repair.dart';
import 'package:len/ink/selection/shape_merge.dart';
import 'package:len/ink/shapes/shape_anchors.dart';
import 'package:len/ink/shapes/shape_builder.dart';
import 'package:uuid/uuid.dart';

import 'support/connector_devices.dart';

// Connectors edited on two devices at once: one moves the box, the other
// edits or draws its arrow, or both edit one of them. Arrows name the box
// by its identity across edits (`Stroke.shapeId`), edits name the stroke
// they replace (`sh.r`), and every device applying the other's changes
// merges two edits of one shape into one stroke (`ShapeMerge`) and brings
// ends left off it back on (`ConnectorRepair`): the same everywhere,
// written once, no undo step, no back and forth.

void main() {
  test('a box moved on one device while its arrow is recoloured on the other', () async {
    final [a, b] = await connectorDevices();
    a.edit(() => a.box, (c) => a.move(const Offset(0, 60)));
    b.edit(() => b.arrows.single, (c) => c.selection.recolor(0xFFE03131));
    expect(b.arrows.single.shape!.tip!.id, 'box');
    final steps = b.model.history.recorded;

    await a.sync();
    final changes = await b.sync(); // Brings the moved box and arrow: b merges.
    await a.sync();

    for (final d in [a, b]) {
      expectOnBox(d);
      // One arrow: moved with the box (a) and recoloured (b).
      final arrow = d.arrows.single;
      expect(arrow.color, 0xFFE03131);
      expect(arrow.shapeId, 'arrow');
    }
    final merged = b.arrows.single;
    expect(changes.itemsOf(b.page), contains(merged.id));
    // The editor shows it, and has no undo step of it.
    expect(b.model.strokeById(merged.id), isNotNull);
    expect(b.model.history.recorded, steps);
    await expectSettled([a, b]);
  });

  test('an arrow drawn to the box on one device while it moves on the other', () async {
    final [a, b] = await connectorDevices();
    a.edit(() => a.box, (c) => a.move(const Offset(40, 80)));
    b.s.strokes.save([
      shapeOn(
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
      expectOnBox(d);
      // The repaired arrow is still the shape it was (an edit keeps it).
      expect({for (final x in d.arrows) x.shapeId}, {'arrow', 'new'});
      expect(d.arrows.map((x) => x.id), isNot(contains('new')));
    }
    await expectSettled([a, b]);
  });

  test('two devices merging the same edits at once write one stroke', () async {
    final [a, b] = await connectorDevices();
    a.edit(() => a.box, (c) => a.move(const Offset(0, 60)));
    b.edit(() => b.arrows.single, (c) => c.selection.recolor(0xFFE03131));
    // b pulls a's move but does not get to merge before a does.
    final engine = b.s.sync.engine;
    final repair = engine.afterApply;
    engine.afterApply = null;
    await a.sync();
    final missed = await b.sync();
    engine.afterApply = repair;
    await a.sync(); // a merges the arrows and pushes the merge.
    final mine = ConnectorRepair(b.s.strokes).repair(missed);
    expect(mine, 1); // b merges them too, the same way.
    await b.sync();
    await a.sync();
    for (final d in [a, b]) {
      expect(d.arrows.single.color, 0xFFE03131); // Once.
      expectOnBox(d);
    }
    await expectSettled([a, b]);
  });

  test('two devices repairing the same arrow at once write one stroke', () async {
    final [a, b] = await connectorDevices();
    a.edit(() => a.box, (c) => a.move(const Offset(0, 60)));
    // b draws a second arrow to the box where it was.
    b.model.addStroke(
      shapeOn(
        'new',
        b.page,
        ShapeGeometry(ShapeKind.arrow, const [
          Offset(350, 50),
          Offset(350, 200),
        ], tip: const ShapeAttachment('box', 0.125)),
      ),
    );
    b.model.flush();
    // b pushes it and pulls the move but does not get to repair before a
    // does.
    final engine = b.s.sync.engine;
    final repair = engine.afterApply;
    engine.afterApply = null;
    await a.sync();
    final missed = await b.sync();
    engine.afterApply = repair;
    await a.sync(); // a repairs b's arrow and pushes it.
    expect(ConnectorRepair(b.s.strokes).repair(missed), 1); // b too, the same way.
    await b.sync();
    await a.sync();
    for (final d in [a, b]) {
      expect(d.arrows, hasLength(2)); // a's and the one repaired, once.
      expectOnBox(d);
    }
    await expectSettled([a, b]);
  });

  test('both devices edit the arrow: one recolours it, the other moves it', () async {
    final [a, b] = await connectorDevices();
    a.edit(() => a.arrows.single, (c) => c.selection.recolor(0xFFE03131));
    b.edit(() => b.arrows.single, (c) => b.move(const Offset(0, -100))); // Lets go.
    final moved = b.arrows.single.shape!;
    await a.sync();
    await b.sync();
    await a.sync();
    for (final d in [a, b]) {
      final arrow = d.arrows.single;
      expect(arrow.color, 0xFFE03131);
      expect(arrow.shape!.points, moved.points);
      expect(arrow.shape!.isAttached, isFalse);
    }
    await expectSettled([a, b]);
  });

  test('both devices move the box: one box, the arrow on it', () async {
    final [a, b] = await connectorDevices();
    a.edit(() => a.box, (c) => a.move(const Offset(0, 60)));
    b.edit(() => b.box, (c) => b.move(const Offset(80, 0)));
    // Both moved it: the move of the stroke of the least id wins.
    final first = [a.box, b.box].reduce((x, y) => x.id.compareTo(y.id) < 0 ? x : y);
    await a.sync();
    await b.sync();
    await a.sync();
    for (final d in [a, b]) {
      expect(d.box.shape!.points, first.shape!.points);
      expect(d.arrows, hasLength(1));
      expectOnBox(d);
    }
    await expectSettled([a, b]);
  });

  test('one device recolours the box while the other moves it', () async {
    final [a, b] = await connectorDevices();
    a.edit(() => a.box, (c) => c.selection.recolor(0xFF2F9E44));
    b.edit(() => b.box, (c) => b.move(const Offset(80, 40)));
    final moved = b.box.shape!.points;
    await b.sync();
    await a.sync();
    await b.sync();
    for (final d in [a, b]) {
      expect(d.box.color, 0xFF2F9E44);
      expect(d.box.shape!.points, moved);
      expect(d.box.shapeId, 'box');
      expect(d.arrows, hasLength(1));
      expectOnBox(d);
    }
    await expectSettled([a, b]);
  });

  test('edits by clients that name no predecessor: the least id wins whole', () {
    final db = AppDatabase.inMemory();
    addTearDown(db.close);
    final strokes = StrokeRepository(db, deviceId: 'd');
    final box = ShapeBuilder.dragged(
      ShapeKind.rectangle,
      const Offset(0, 0),
      const Offset(100, 100),
    );
    ShapeGeometry arrow(Offset tail) => ShapeGeometry(ShapeKind.arrow, [
      tail,
      const Offset(0, 50),
    ], tip: const ShapeAttachment('box', 0.875));
    final x2 = shapeOn(
      'x2',
      'p',
      arrow(const Offset(-80, 0)).withOrigin('arrow'),
      color: 0xFFE03131,
    );
    final x1 = shapeOn('x1', 'p', arrow(const Offset(-50, 50)).withOrigin('arrow'));
    strokes.save([shapeOn('box', 'p', box.map((p) => p + const Offset(0, 40))), x2, x1]);
    final (:removed, :added) = ConnectorRepair(strokes).fixesFor('p', ['x2']);
    expect({for (final s in removed) s.id}, {'x1', 'x2'});
    final merged = added.single;
    expect(merged.color, 0xFF1C7ED6); // x1's, whole
    expect(merged.shapeId, 'arrow');
    expect(merged.shape!.points[0], const Offset(-50, 50));
    // On the moved box.
    expect(merged.shape!.points[1], ShapeAnchors.pointAt(box, 0.875) + const Offset(0, 40));
    // Repaired: the merge (never written), then the twins it merged.
    expect(merged.shape!.replaces.take(3), [
      ConnectorRepair.mergeIdOf([x1, x2]),
      'x1',
      'x2',
    ]);
  });

  test('a merge takes each part from the edit that changed it', () {
    ShapeGeometry line(List<Offset> p, {ShapeAttachment? tip}) =>
        ShapeGeometry(ShapeKind.line, p, tip: tip);
    final base = shapeOn('base', 'p', line(const [Offset(0, 0), Offset(100, 0)]));
    Stroke edit(String id, ShapeGeometry g, {int color = 0xFF1C7ED6}) =>
        shapeOn(id, 'p', g.editing('base', base.shape!), color: color);
    // m1 bends it, m2 moves its tip and attaches it, m3 recolours it.
    final m1 = edit('m1', line(const [Offset(0, 0), Offset(100, 0), Offset(50, 30)]));
    final m2 = edit(
      'm2',
      line(const [Offset(0, 0), Offset(100, 80)], tip: const ShapeAttachment('box', 0.5)),
    );
    final m3 = edit('m3', base.shape!, color: 0xFFE03131);
    final twins = [m1, m2, m3];
    expect(ShapeMerge.baseOf(twins), 'base');
    final merged = ShapeMerge.merged(
      twins,
      ShapeVersion.of(base),
      id: ConnectorRepair.mergeIdOf(twins),
    );
    expect(merged.color, 0xFFE03131);
    expect(merged.shape!.points, const [Offset(0, 0), Offset(100, 80), Offset(50, 30)]);
    expect(merged.shape!.tip, const ShapeAttachment('box', 0.5));
    expect(merged.shapeId, 'base');
    expect(merged.shape!.replaces, ['m1', 'm2', 'm3', 'base']);
    expect(merged.id, ConnectorRepair.mergeIdOf([m1, m2, m3]));
    // A version brought back (an undo), or arriving before its deletion,
    // beside an edit of it: superseded, the edit stays alone.
    expect(ShapeMerge.staleIn([base, m3]), {'base'});
    expect(ShapeMerge.staleIn(twins), isEmpty);
  });

  test('ends attached to shapes not on the page, or sitting, are left alone', () {
    final box = shapeOn(
      'box',
      'p',
      ShapeBuilder.dragged(ShapeKind.rectangle, const Offset(0, 0), const Offset(10, 10)),
    );
    final sitting = shapeOn(
      'sitting',
      'p',
      ShapeGeometry(ShapeKind.line, [
        const Offset(-20, 5),
        ShapeAnchors.pointAt(box.shape!, 0.875),
      ], tip: const ShapeAttachment('box', 0.875)),
    );
    final stray = shapeOn(
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
    final twin = shapeOn('twin', 'p', box.shape!.map((p) => p + const Offset(100, 0)));
    final named = shapeOn('box2', 'p', twin.shape!.withOrigin('box'));
    expect(ConnectorRepair.repairsOn([box, named, sitting]), isEmpty);
    // Off both: the stroke of that very id.
    final off = shapeOn('off', 'p', sitting.shape!.withPoint(1, const Offset(-5, 40)));
    final (line, fixed) = ConnectorRepair.repairsOn([named, box, off]).single;
    expect(line.id, 'off');
    expect(fixed.shape!.points[1], ShapeAnchors.pointAt(box.shape!, 0.875));
    expect(fixed.id, ConnectorRepair.idOf(off, null, box));
    // A UUID v5 in a fixed namespace, as the uuid package makes them.
    expect(fixed.id, const Uuid().v5('6f1c2b0e-4f5d-5c8a-9a37-2d8e1c4b7a10', 'off>|box'));
  });
}
