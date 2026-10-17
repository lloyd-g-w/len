import 'dart:convert';

import 'package:sqlite3/common.dart';

import '../domain/shape_geometry.dart';
import '../domain/shaped.dart';
import 'app_database.dart';
import 'stroke_queries.dart';
import 'stroke_row.dart';

/// The shape strokes a connector repair (`ConnectorRepair`) reads: the
/// [lines] to check and the [shapes] their ends may be attached to (every
/// stroke of each shape they name, the lines among them too).
typedef ConnectorShapes = ({List<ShapeRow> shapes, List<ShapeRow> lines});

/// A live shape stroke as a connector repair reads it: its id and shape
/// alone (its points, the most of a row to decode, are read only for the
/// lines repaired).
class ShapeRow implements Shaped {
  const ShapeRow(this.id, this.shape);

  @override
  final String id;

  @override
  final ShapeGeometry shape;

  @override
  String get shapeId => shape.origin ?? id;
}

/// Reads the lines and shapes connectors are made of from the `strokes`
/// table (attachments live in the `style` column, `sh.a`; a shape's
/// identity across edits is `sh.o`, else the stroke id), through indexes
/// of live shape strokes per surface ([migrate]).
class ConnectorQueries {
  ConnectorQueries(this._db);

  final AppDatabase _db;

  /// Live shape strokes: the condition of the indexes [migrate] makes.
  static const _live = "deleted = 0 AND style LIKE '%\"sh\"%'";

  /// [_live] with a style JSON can read (the expression indexes').
  static const _valid = '$_live AND json_valid(style)';

  /// A surface's live shapes (by their index: never its ink).
  static const _shapes = 'strokes INDEXED BY strokes_shapes WHERE surface_id = ? AND $_live';
  static const _attached = "$_shapes AND style LIKE '%\"a\":%'";

  /// The index expressions: what a shape's tail and tip are attached to,
  /// and its identity across edits.
  static const _tail = r"json_extract(style, '$.sh.a[0].id')";
  static const _tip = r"json_extract(style, '$.sh.a[1].id')";
  static const _origin = r"json_extract(style, '$.sh.o')";

  /// Version 20: live shape strokes indexed per surface by what their ends
  /// are attached to and by their identity ([_tail], [_tip], [_origin]),
  /// so the lines attached to a changed shape and a shape's strokes are
  /// found without reading every shape on the surface.
  static void migrate(CommonDatabase db) {
    for (final (name, expression) in [
      ('strokes_shape_tails', _tail),
      ('strokes_shape_tips', _tip),
      ('strokes_shape_origins', _origin),
    ]) {
      db.execute('CREATE INDEX $name ON strokes(surface_id, $expression) WHERE $_valid');
    }
  }

  /// Changed shapes looked for one by one at most; more read [all].
  static const int maxNames = 64;

  /// The live shape strokes on [surfaceId] (drawn with the Shape tool or
  /// snapped), every line checked — none when no line there is attached
  /// to a shape (a quick test first).
  ConnectorShapes all(String surfaceId) {
    final attached = _db.select('SELECT EXISTS (SELECT 1 FROM $_attached) AS found', [surfaceId]);
    if (attached.first['found'] != 1) return (shapes: const [], lines: const []);
    final shapes = _rows('SELECT id, style FROM $_shapes', [surfaceId]);
    return (shapes: shapes, lines: shapes);
  }

  /// What a change to strokes [changed] on [surfaceId] (applied from other
  /// devices: live, or deleted since) can have left off its shapes: the
  /// live lines among them, and those attached to a closed shape one of
  /// them is (or was) a stroke of; with every live stroke of the shapes
  /// these lines name. Nothing more is read when none of [changed] is a
  /// shape (ink, text, images); [all] when too many shapes changed.
  ConnectorShapes touchedBy(String surfaceId, Iterable<String> changed) {
    final names = <String>{}, lines = <String>{};
    final rows = _db.select(
      'SELECT id, style FROM strokes '
      "WHERE id IN (SELECT value FROM json_each(?)) AND style LIKE '%\"sh\"%'",
      [jsonEncode(changed.toList())],
    );
    for (final r in rows) {
      final shape = _shapeOf(r['style']);
      if (shape == null) continue;
      if (shape.isClosed) names.add(shape.origin ?? r['id'] as String);
      if (shape.isAttached) lines.add(r['id'] as String);
    }
    if (names.isEmpty && lines.isEmpty) return (shapes: const [], lines: const []);
    if (names.length > maxNames) return all(surfaceId);
    final named = jsonEncode(names.toList());
    final attached = [
      for (final s in _rows(
        '${_in('strokes_shape_tails', _tail)} UNION ${_in('strokes_shape_tips', _tip)} '
        'UNION SELECT id, style FROM strokes '
        'WHERE id IN (SELECT value FROM json_each(?)) AND surface_id = ? AND $_live',
        [surfaceId, named, surfaceId, named, jsonEncode(lines.toList()), surfaceId],
      ))
        if (s.shape.isAttached) s,
    ];
    if (attached.isEmpty) return (shapes: const [], lines: const []);
    final targets = {for (final s in attached) ..._names(s)};
    return (shapes: [...attached, ..._named(surfaceId, targets)], lines: attached);
  }

  /// The live strokes on [surfaceId] of the shapes [names] ([Shaped.shapeId]):
  /// those of these ids, and those that are edits of them.
  List<ShapeRow> _named(String surfaceId, Set<String> names) {
    final named = jsonEncode(names.toList());
    return [
      for (final s in _rows(
        'SELECT id, style FROM strokes '
        'WHERE id IN (SELECT value FROM json_each(?)) AND surface_id = ? AND $_live '
        'UNION ${_in('strokes_shape_origins', _origin)}',
        [named, surfaceId, surfaceId, named],
      ))
        if (names.contains(s.shapeId)) s,
    ];
  }

  /// The live shapes on a surface (`?`) whose [expression] is among a JSON
  /// array of names (`?`), through [index].
  static String _in(String index, String expression) =>
      'SELECT id, style FROM strokes INDEXED BY $index '
      'WHERE surface_id = ? AND $_valid AND $expression IN (SELECT value FROM json_each(?))';

  /// The shapes [line]'s ends are attached to.
  static Iterable<String> _names(ShapeRow line) => [
    if (line.shape.tail case final a?) a.id,
    if (line.shape.tip case final a?) a.id,
  ];

  /// The shapes of the rows (`id, style`) [sql] selects.
  List<ShapeRow> _rows(String sql, List<Object?> args) => [
    for (final r in _db.select(sql, args))
      if (_shapeOf(r['style']) case final shape?) ShapeRow(r['id'] as String, shape),
  ];

  static ShapeGeometry? _shapeOf(Object? style) {
    if (style is! String) return null;
    try {
      return StrokeRow.shapeOf(StrokeQueries.decodeStyle(style));
    } on FormatException {
      return null;
    }
  }
}
