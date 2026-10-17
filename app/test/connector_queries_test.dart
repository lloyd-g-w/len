import 'package:flutter_test/flutter_test.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/connector_queries.dart';
import 'package:len/data/stroke_repository.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/selection/connector_repair.dart';
import 'package:len/ink/shapes/shape_anchors.dart';
import 'package:len/ink/shapes/shape_builder.dart';
import 'package:len/sync/remote_changes.dart';

import 'shape_geometry_test.dart' show shapeStroke;

// What a connector repair reads after a pull: only the lines the changes
// can have left off their shapes, and the shapes those lines name.

/// [s] on page `p`.
Stroke _on(Stroke s) => Stroke(
  id: s.id,
  surfaceId: 'p',
  tool: s.tool,
  color: s.color,
  width: s.width,
  points: s.points,
  createdAt: s.createdAt,
  style: s.style,
  shape: s.shape,
);

ShapeGeometry _box(double x) =>
    ShapeBuilder.dragged(ShapeKind.rectangle, Offset(x, 0), Offset(x + 50, 50));

/// A line from box [from]'s right side to box [to]'s left side, attached
/// to both; [off] moves its tip off by that much.
Stroke _link(String id, Stroke from, Stroke to, {Offset off = Offset.zero}) => _on(
  shapeStroke(
    ShapeGeometry(
      ShapeKind.arrow,
      [ShapeAnchors.pointAt(from.shape!, 0.375), ShapeAnchors.pointAt(to.shape!, 0.875) + off],
      tail: ShapeAttachment(from.shapeId, 0.375),
      tip: ShapeAttachment(to.shapeId, 0.875),
    ),
    id: id,
  ),
);

void main() {
  late AppDatabase db;
  late StrokeRepository strokes;
  late ConnectorQueries queries;
  final a = _on(shapeStroke(_box(0), id: 'a'));
  final b = _on(shapeStroke(_box(100), id: 'b'));
  final c = _on(shapeStroke(_box(200), id: 'c'));
  final ab = _link('ab', a, b), bc = _link('bc', b, c), ca = _link('ca', c, a);
  final ink = _on(
    Stroke(
      id: 'ink',
      surfaceId: 'p',
      tool: InkTool.ballpoint,
      color: 0xFF000000,
      width: 2,
      points: const [StrokePoint(0, 0, 0.5), StrokePoint(10, 10, 0.5)],
      createdAt: 1,
    ),
  );

  setUp(() {
    db = AppDatabase.inMemory();
    strokes = StrokeRepository(db, deviceId: 'd');
    queries = ConnectorQueries(strokes.db);
    strokes.save([a, b, c, ab, bc, ca, ink]);
  });
  tearDown(() => db.close());

  Set<String> ids(Iterable<Stroke> s) => {for (final x in s) x.id};

  test('ink changed: nothing to look at', () {
    final read = queries.touchedBy('p', ['ink', 'unknown']);
    expect(read.lines, isEmpty);
    expect(read.shapes, isEmpty);
  });

  test('a shape changed: the lines attached to it, with all the shapes they name', () {
    final read = queries.touchedBy('p', ['b']);
    expect(ids(read.lines), {'ab', 'bc'});
    expect(ids(read.shapes), containsAll(['ab', 'bc', 'a', 'b', 'c']));
    expect(ids(read.shapes), isNot(contains('ca')));
  });

  test('a shape edited (a new stroke of it) or deleted: found by its identity', () {
    final moved = _on(
      shapeStroke(_box(100).map((p) => p + const Offset(0, 30)).withOrigin('b'), id: 'b2'),
    );
    db.transaction(() {
      strokes.delete(['b']);
      strokes.save([moved]);
    });
    expect(ids(queries.touchedBy('p', ['b2']).lines), {'ab', 'bc'});
    expect(ids(queries.touchedBy('p', ['b']).lines), {'ab', 'bc'}); // its tombstone
    expect(ids(queries.touchedBy('p', ['b']).shapes), containsAll(['b2', 'a', 'c']));
  });

  test('a line changed: itself and its shapes', () {
    final read = queries.touchedBy('p', ['ca']);
    expect(ids(read.lines), {'ca'});
    expect(ids(read.shapes), {'ca', 'a', 'c'});
  });

  test('too many shapes changed: every line', () {
    final boxes = [
      for (var i = 0; i <= ConnectorQueries.maxNames; i++)
        _on(shapeStroke(_box(1000 + 60.0 * i), id: 'x$i')),
    ];
    strokes.save(boxes);
    final read = queries.touchedBy('p', [for (final x in boxes) x.id]);
    expect(ids(read.lines), containsAll(['ab', 'bc', 'ca']));
  });

  test('the repair reads only what changed, and fixes it', () {
    final off = _link('bc', b, c, off: const Offset(0, 20));
    strokes.save([off]); // bc's tip off c, as a concurrent edit leaves it.
    final repair = ConnectorRepair(strokes);
    expect(repair.repair(RemoteChanges()..addItem('p', 'ink')), 0);
    expect(repair.repair(RemoteChanges()..addItem('p', 'a')), 0); // ab, ca sit
    final changes = RemoteChanges()..addItem('p', 'c');
    expect(repair.repair(changes), 1);
    expect(changes.itemsOf('p'), contains('bc'));
    // Not named (too many changes): the whole page.
    strokes.save([off]);
    expect(repair.repair(RemoteChanges()..reloadSurface('p')), 1);
  });
}
