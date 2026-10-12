import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui';

import 'package:sqlite3/common.dart';

import '../domain/chunk_grid.dart';
import '../domain/stroke.dart';
import '../domain/surface_element.dart';
import 'stroke_codec.dart';
import 'stroke_reader.dart';

/// Read-only queries for a surface's content (strokes and elements) on a
/// SQLite connection.
///
/// Used by `StrokeRepository` on the UI isolate's connection and by
/// `BackgroundStrokeReader` on its own read-only connection in a worker
/// isolate (WAL lets readers run alongside the writer).
class StrokeQueries implements StrokeReader {
  StrokeQueries(this._db);

  final CommonDatabase _db;

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

  /// Chunks within [range] that contain at least one live element.
  List<ChunkKey> populatedElementChunks(String surfaceId, ChunkRange range) => _db
      .select(
        'SELECT DISTINCT cx, cy FROM element_chunks '
        'WHERE surface_id = ? AND cx BETWEEN ? AND ? AND cy BETWEEN ? AND ?',
        [surfaceId, range.minX, range.maxX, range.minY, range.maxY],
      )
      .map((r) => (x: r['cx'] as int, y: r['cy'] as int))
      .toList();

  /// Live elements on [surfaceId] touching any of [keys].
  List<SurfaceElement> loadElementChunks(String surfaceId, List<ChunkKey> keys) {
    final byId = <String, SurfaceElement>{};
    for (var i = 0; i < keys.length; i += _batch) {
      final slice = keys.sublist(i, (i + _batch).clamp(0, keys.length));
      final tuples = List.filled(slice.length, '(?, ?)').join(', ');
      final rows = _db.select(
        '''
        SELECT * FROM elements WHERE deleted = 0 AND id IN (
          SELECT element_id FROM element_chunks
          WHERE surface_id = ? AND (cx, cy) IN (VALUES $tuples)
        )''',
        [
          surfaceId,
          for (final k in slice) ...[k.x, k.y],
        ],
      );
      for (final element in rows.map(rowToElement).nonNulls) {
        byId[element.id] = element;
      }
    }
    return byId.values.toList();
  }

  /// Chunks within [range] holding a stroke or an element, except [skip].
  List<ChunkKey> missingChunks(
    String surfaceId,
    ChunkRange range, {
    Set<ChunkKey> skip = const {},
  }) => [
    for (final key in {
      ...populatedChunks(surfaceId, range),
      ...populatedElementChunks(surfaceId, range),
    })
      if (!skip.contains(key)) key,
  ];

  /// Reads strokes and elements alike: a chunk is populated if either kind
  /// is indexed in it.
  @override
  ChunkLoad read(String surfaceId, ChunkRange range, {Set<ChunkKey> skip = const {}}) {
    final missing = missingChunks(surfaceId, range, skip: skip);
    if (missing.isEmpty) return ChunkLoad.empty;
    return ChunkLoad(
      chunks: missing,
      strokes: loadChunks(surfaceId, missing),
      elements: loadElementChunks(surfaceId, missing),
    );
  }

  /// Strokes plus elements indexed in each populated chunk.
  @override
  Map<ChunkKey, int> chunkDensity(String surfaceId) {
    final density = <ChunkKey, int>{};
    for (final table in const ['stroke_chunks', 'element_chunks']) {
      for (final r in _db.select(
        'SELECT cx, cy, COUNT(*) AS n FROM $table WHERE surface_id = ? GROUP BY cx, cy',
        [surfaceId],
      )) {
        final key = (x: r['cx'] as int, y: r['cy'] as int);
        density[key] = (density[key] ?? 0) + (r['n'] as int);
      }
    }
    return density;
  }

  /// Bounds of all live strokes and elements.
  @override
  Rect? contentBounds(String surfaceId) {
    final strokes = _strokeBounds(surfaceId);
    final elements = _elementBounds(surfaceId);
    if (strokes == null || elements == null) return strokes ?? elements;
    return strokes.expandToInclude(elements);
  }

  /// Bounds of all live elements (their axis-aligned, rotated bounds).
  Rect? _elementBounds(String surfaceId) {
    Rect? bounds;
    final rows = _db.select('SELECT * FROM elements WHERE surface_id = ? AND deleted = 0', [
      surfaceId,
    ]);
    for (final element in rows.map(rowToElement).nonNulls) {
      bounds = bounds?.expandToInclude(element.bounds) ?? element.bounds;
    }
    return bounds;
  }

  /// Exact bounds from the strokes in the outermost chunk rows and columns:
  /// every stroke is indexed in each chunk its ink reaches, so nothing
  /// further out can exist.
  Rect? _strokeBounds(String surfaceId) {
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
      final style = row['style'];
      return Stroke(
        id: row['id'] as String,
        surfaceId: row['surface_id'] as String,
        tool: InkTool.parse(row['tool'] as String),
        color: row['color'] as int,
        width: (row['width'] as num).toDouble(),
        points: points,
        createdAt: row['created_at'] as int,
        style: StrokeStyle.fromJson(style is String ? decodeStyle(style) : null),
      );
    } on FormatException {
      return null;
    }
  }

  /// Decodes a stored style column; malformed JSON yields null.
  static Object? decodeStyle(String json) {
    try {
      return jsonDecode(json);
    } on FormatException {
      return null;
    }
  }

  /// Decodes an `elements` row; null for corrupt rows (skipped rather than
  /// breaking the whole surface).
  static SurfaceElement? rowToElement(Row row) {
    final data = decodeElementData(row['data'] as String);
    if (data == null) return null;
    return SurfaceElement(
      id: row['id'] as String,
      surfaceId: row['surface_id'] as String,
      type: row['type'] as String,
      rect: Rect.fromLTWH(
        (row['x'] as num).toDouble(),
        (row['y'] as num).toDouble(),
        (row['w'] as num).toDouble(),
        (row['h'] as num).toDouble(),
      ),
      rotation: (row['rotation'] as num).toDouble(),
      z: (row['z'] as num).toDouble(),
      createdAt: row['created_at'] as int,
      data: data,
    );
  }

  /// Decodes a stored element payload; malformed JSON yields null.
  static Map<String, Object?>? decodeElementData(String json) {
    try {
      final decoded = jsonDecode(json);
      return decoded is Map<String, Object?> ? decoded : null;
    } on FormatException {
      return null;
    }
  }
}
