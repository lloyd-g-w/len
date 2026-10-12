import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:len/data/stroke_reader.dart';
import 'package:len/domain/chunk_grid.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/domain/stroke_chunks.dart';
import 'package:len/ink/pen/pen_config.dart';

/// Serves strokes from memory, indexed exactly like storage (synchronous).
class MemoryStrokeReader implements StrokeReader {
  MemoryStrokeReader(Iterable<Stroke> strokes) {
    for (final s in strokes) {
      for (final key in StrokeChunks.of(s)) {
        (_chunks[key] ??= []).add(s);
      }
    }
  }

  final Map<ChunkKey, List<Stroke>> _chunks = {};

  int get chunkCount => _chunks.length;

  @override
  ChunkLoad read(String surfaceId, ChunkRange range, {Set<ChunkKey> skip = const {}}) {
    final keys = [
      for (final key in _chunks.keys)
        if (range.contains(key) && !skip.contains(key)) key,
    ];
    return ChunkLoad(chunks: keys, strokes: {for (final k in keys) ..._chunks[k]!}.toList());
  }

  @override
  Map<ChunkKey, int> chunkDensity(String surfaceId) => {
    for (final e in _chunks.entries) e.key: e.value.length,
  };

  @override
  Rect? contentBounds(String surfaceId) {
    Rect? bounds;
    for (final list in _chunks.values) {
      for (final s in list) {
        bounds = bounds?.expandToInclude(s.bounds) ?? s.bounds;
      }
    }
    return bounds;
  }
}

/// [count] short handwriting-like scribbles scattered over [area], with
/// pen ink and some highlighter.
List<Stroke> scribbles(int count, Rect area, {int seed = 1, int points = 10}) {
  final random = math.Random(seed);
  final strokes = <Stroke>[];
  for (var n = 0; n < count; n++) {
    final tool = n % 9 == 0 ? InkTool.highlighter : InkTool.ballpoint;
    final config = PenConfig.defaultsFor(tool);
    final width = config.width;
    var x = area.left + random.nextDouble() * area.width;
    final y = area.top + random.nextDouble() * area.height;
    final pts = <StrokePoint>[];
    for (var i = 0; i < points; i++) {
      x += 4 + random.nextDouble() * 6;
      pts.add(StrokePoint(x, y + 14 * math.sin(i * 0.9 + n), 0.3 + 0.5 * random.nextDouble()));
    }
    strokes.add(
      Stroke(
        id: 'b$n',
        surfaceId: 's',
        tool: tool,
        color: [0xFF1B1F3B, 0xFF1565C0, 0xFFC62828, 0xFF2E7D32][n % 4],
        width: width,
        points: pts,
        createdAt: n,
        style: config.styleFor(tool, width),
      ),
    );
  }
  return strokes;
}

/// Lets real asynchronous work (isolates, `toImage`) progress until [done].
Future<void> settle(bool Function() done, {Duration limit = const Duration(seconds: 60)}) async {
  final watch = Stopwatch()..start();
  while (!done()) {
    if (watch.elapsed > limit) throw TimeoutException('did not settle', limit);
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
}
