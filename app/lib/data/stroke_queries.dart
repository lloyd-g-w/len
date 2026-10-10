import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:sqlite3/sqlite3.dart';

import '../domain/chunk_grid.dart';
import '../domain/stroke.dart';
import 'stroke_codec.dart';
import 'stroke_reader.dart';

/// Read-only stroke queries on a SQLite connection.
///
/// Used by `StrokeRepository` on the UI isolate's connection and by
/// `BackgroundStrokeReader` on its own read-only connection in a worker
/// isolate (WAL lets readers run alongside the writer).
class StrokeQueries implements StrokeReader {
  StrokeQueries(this._db);

  final Database _db;

  /// Keeps bound parameters well under SQLite's limit.
  static const int _batch = 250;

  /// Chunks within [range] that contain at least one live stroke.
  List<ChunkKey> populatedChunks(String surfaceId, ChunkRange range) => _db
      .select(
        'SELECT DISTINCT cx, cy FROM stroke_chunks '
        'WHERE surface_id = ? AND cx BETWEEN ? AND ? AND cy BETWEEN ? AND ?',
        [surfaceId, range.minX, range.maxX, range.minY, range.maxY],
      )
      .map((r) => (x: r['cx'] as int, y: r['cy'] as int))
      .toList();

  /// Live strokes on [surfaceId] touching any of [keys].
  List<Stroke> loadChunks(String surfaceId, List<ChunkKey> keys) {
    final byId = <String, Stroke>{};
    for (var i = 0; i < keys.length; i += _batch) {
      final slice = keys.sublist(i, (i + _batch).clamp(0, keys.length));
      final tuples = List.filled(slice.length, '(?, ?)').join(', ');
      final rows = _db.select(
        '''
        SELECT * FROM strokes WHERE deleted = 0 AND id IN (
          SELECT stroke_id FROM stroke_chunks
          WHERE surface_id = ? AND (cx, cy) IN (VALUES $tuples)
        )''',
        [
          surfaceId,
          for (final k in slice) ...[k.x, k.y],
        ],
      );
      for (final stroke in rows.map(rowToStroke).nonNulls) {
        byId[stroke.id] = stroke;
      }
    }
    return byId.values.toList();
  }

  @override
  ChunkLoad read(String surfaceId, ChunkRange range, {Set<ChunkKey> skip = const {}}) {
    final missing = [
      for (final key in populatedChunks(surfaceId, range))
        if (!skip.contains(key)) key,
    ];
    if (missing.isEmpty) return ChunkLoad.empty;
    return ChunkLoad(chunks: missing, strokes: loadChunks(surfaceId, missing));
  }

  @override
  Map<ChunkKey, int> chunkDensity(String surfaceId) => {
    for (final r in _db.select(
      'SELECT cx, cy, COUNT(*) AS n FROM stroke_chunks WHERE surface_id = ? GROUP BY cx, cy',
      [surfaceId],
    ))
      (x: r['cx'] as int, y: r['cy'] as int): r['n'] as int,
  };

  /// Exact bounds from the strokes in the outermost chunk rows and columns:
  /// every stroke is indexed in each chunk its ink reaches, so nothing
  /// further out can exist.
  @override
  Rect? contentBounds(String surfaceId) {
    final extent = _db.select(
      'SELECT MIN(cx) AS x0, MAX(cx) AS x1, MIN(cy) AS y0, MAX(cy) AS y1 '
      'FROM stroke_chunks WHERE surface_id = ?',
      [surfaceId],
    ).first;
    if (extent['x0'] == null) return null;
    final rows = _db.select(
      '''
      SELECT * FROM strokes WHERE deleted = 0 AND id IN (
        SELECT stroke_id FROM stroke_chunks
        WHERE surface_id = ? AND (cx = ? OR cx = ? OR cy = ? OR cy = ?)
      )''',
      [surfaceId, extent['x0'], extent['x1'], extent['y0'], extent['y1']],
    );
    Rect? bounds;
    for (final stroke in rows.map(rowToStroke).nonNulls) {
      bounds = bounds?.expandToInclude(stroke.bounds) ?? stroke.bounds;
    }
    return bounds;
  }

  /// Decodes a `strokes` row; null for corrupt rows (skipped rather than
  /// breaking the whole surface).
  static Stroke? rowToStroke(Row row) {
    try {
      final points = StrokeCodec.decode(row['points'] as Uint8List);
      if (points.isEmpty) return null;
      final tool = InkTool.parse(row['tool'] as String);
      final style = row['style'];
      return Stroke(
        id: row['id'] as String,
        surfaceId: row['surface_id'] as String,
        tool: tool,
        color: row['color'] as int,
        width: (row['width'] as num).toDouble(),
        points: points,
        createdAt: row['created_at'] as int,
        style: StrokeStyle.fromJson(
          style is String ? decodeStyle(style) : null,
          fallback: StrokeStyle.defaultsFor(tool),
        ),
      );
    } on FormatException {
      return null;
    }
  }

  /// Decodes a stored style column; malformed JSON yields null (defaults).
  static Object? decodeStyle(String json) {
    try {
      return jsonDecode(json);
    } on FormatException {
      return null;
    }
  }
}
