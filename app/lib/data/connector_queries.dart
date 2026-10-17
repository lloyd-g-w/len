import 'dart:convert';

import 'package:sqlite3/common.dart';

import '../domain/stroke.dart';
import 'stroke_queries.dart';
import 'stroke_row.dart';

/// The shape strokes a connector repair (`ConnectorRepair`) reads: the
/// [lines] to check and the [shapes] their ends may be attached to (every
/// stroke of each shape they name, the lines among them too).
typedef ConnectorShapes = ({List<Stroke> shapes, List<Stroke> lines});

/// Reads the lines and shapes connectors are made of from the `strokes`
/// table (attachments live in the `style` column, `sh.a`; a shape's
/// identity across edits is `sh.o`, else the stroke id).
class ConnectorQueries {
  ConnectorQueries(this._db);

  final CommonDatabase _db;

  /// A surface's live shapes (by their index: never its ink).
  static const _shapes =
      'strokes INDEXED BY strokes_shapes '
      "WHERE surface_id = ? AND deleted = 0 AND style LIKE '%\"sh\"%'";
  static const _attached = "$_shapes AND style LIKE '%\"a\":%'";

  /// Changed shapes looked for one by one at most; more read [all].
  static const int maxNames = 64;

  /// The live shape strokes on [surfaceId] (drawn with the Shape tool or
  /// snapped), every line checked — none when no line there is attached
  /// to a shape (a quick test first).
  ConnectorShapes all(String surfaceId) {
    final attached = _db.select('SELECT EXISTS (SELECT 1 FROM $_attached) AS found', [surfaceId]);
    if (attached.first['found'] != 1) return (shapes: const [], lines: const []);
    final shapes = _strokes('SELECT * FROM $_shapes', [surfaceId]);
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
    final ids = changed.toList();
    for (var i = 0; i < ids.length; i += _batch) {
      final batch = ids.sublist(i, (i + _batch).clamp(0, ids.length));
      final rows = _db.select(
        'SELECT id, style FROM strokes '
        "WHERE id IN (${_marks(batch.length)}) AND style LIKE '%\"sh\"%'",
        batch,
      );
      for (final r in rows) {
        final shape = _shapeOf(r['style']);
        if (shape == null) continue;
        if (shape.isClosed) names.add(shape.origin ?? r['id'] as String);
        if (shape.isAttached) lines.add(r['id'] as String);
      }
    }
    if (names.isEmpty && lines.isEmpty) return (shapes: const [], lines: const []);
    if (names.length > maxNames) return all(surfaceId);
    final quoted = [for (final n in names) jsonEncode(n)];
    final attached = [
      for (final s in _strokes(
        'SELECT * FROM $_attached AND (id IN (${_marks(lines.length)})'
        '${' OR instr(style, ?) > 0' * quoted.length})',
        [surfaceId, ...lines, ...quoted],
      ))
        if (lines.contains(s.id) || _names(s).any(names.contains)) s,
    ];
    if (attached.isEmpty) return (shapes: const [], lines: const []);
    final targets = {for (final s in attached) ..._names(s)}.toList();
    return (shapes: [...attached, ..._named(surfaceId, targets)], lines: attached);
  }

  /// The live strokes on [surfaceId] of the shapes [names] ([Stroke.shapeId]).
  List<Stroke> _named(String surfaceId, List<String> names) {
    final out = <Stroke>[];
    final wanted = names.toSet();
    for (var i = 0; i < names.length; i += _batch) {
      final batch = names.sublist(i, (i + _batch).clamp(0, names.length));
      final origins = [for (final n in batch) '"o":${jsonEncode(n)}'];
      out.addAll(
        _strokes(
          'SELECT * FROM $_shapes AND (id IN (${_marks(batch.length)})'
          '${' OR instr(style, ?) > 0' * origins.length})',
          [surfaceId, ...batch, ...origins],
        ).where((s) => wanted.contains(s.shapeId)),
      );
    }
    return out;
  }

  /// The shapes [line]'s ends are attached to.
  static Iterable<String> _names(Stroke line) => [
    if (line.shape?.tail case final a?) a.id,
    if (line.shape?.tip case final a?) a.id,
  ];

  List<Stroke> _strokes(String sql, List<Object?> args) => _db
      .select(sql, args)
      .map(StrokeQueries.rowToStroke)
      .nonNulls
      .where((s) => s.shape != null)
      .toList();

  static ShapeGeometry? _shapeOf(Object? style) {
    if (style is! String) return null;
    try {
      return StrokeRow.shapeOf(StrokeQueries.decodeStyle(style));
    } on FormatException {
      return null;
    }
  }

  static String _marks(int n) => n == 0 ? 'NULL' : List.filled(n, '?').join(', ');

  /// Keeps bound parameters well under SQLite's limit.
  static const int _batch = 250;
}
