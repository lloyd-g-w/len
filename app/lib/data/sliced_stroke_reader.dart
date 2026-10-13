import 'dart:async';
import 'dart:ui';

import '../domain/chunk_digest.dart';
import '../domain/chunk_grid.dart';
import '../domain/stroke.dart';
import '../domain/surface_element.dart';
import 'stroke_queries.dart';
import 'stroke_reader.dart';

/// Reads surfaces on the UI thread in time-budgeted slices: the web's
/// reader, where no isolate can share the database (see ARCHITECTURE,
/// *Platforms*).
///
/// Finding the populated chunks of a range is one indexed query; loading
/// them is the expensive part (decoding strokes). Up to [sliceChunks]
/// missing chunks load at once and synchronously, as before (panning and
/// normal zoom levels). Larger reads (zooming far out, a first view of a
/// dense canvas) load [sliceChunks] chunks at a time and yield to the event
/// loop whenever [budget] is spent, so frames keep coming; the result then
/// arrives as a `Future` (handled by `SurfaceLoader` like a background read).
class SlicedStrokeReader implements StrokeReader {
  SlicedStrokeReader(
    this._queries, {
    this.sliceChunks = 32,
    this.budget = const Duration(milliseconds: 6),
    Future<void> Function()? yieldToFrame,
  }) : _yield = yieldToFrame ?? (() => Future<void>.delayed(Duration.zero));

  final StrokeQueries _queries;

  /// Chunks loaded per slice.
  final int sliceChunks;

  /// UI-thread time spent reading before yielding.
  final Duration budget;

  final Future<void> Function() _yield;

  @override
  FutureOr<ChunkLoad> read(String surfaceId, ChunkRange range, {Set<ChunkKey> skip = const {}}) {
    final missing = _queries.missingChunks(surfaceId, range, skip: skip);
    if (missing.isEmpty) return ChunkLoad.empty;
    if (missing.length <= sliceChunks) {
      return ChunkLoad(
        chunks: missing,
        strokes: _queries.loadChunks(surfaceId, missing),
        elements: _queries.loadElementChunks(surfaceId, missing),
      );
    }
    return _readSliced(surfaceId, missing);
  }

  Future<ChunkLoad> _readSliced(String surfaceId, List<ChunkKey> missing) async {
    final strokes = <String, Stroke>{};
    final elements = <String, SurfaceElement>{};
    final clock = Stopwatch()..start();
    for (var i = 0; i < missing.length; i += sliceChunks) {
      final slice = missing.sublist(i, (i + sliceChunks).clamp(0, missing.length));
      // A stroke reaching several slices is decoded more than once; the
      // last copy wins (they are identical).
      for (final s in _queries.loadChunks(surfaceId, slice)) {
        strokes[s.id] = s;
      }
      for (final e in _queries.loadElementChunks(surfaceId, slice)) {
        elements[e.id] = e;
      }
      if (clock.elapsed >= budget && i + sliceChunks < missing.length) {
        await _yield();
        clock.reset();
      }
    }
    return ChunkLoad(
      chunks: missing,
      strokes: strokes.values.toList(),
      elements: elements.values.toList(),
    );
  }

  @override
  Map<ChunkKey, ChunkDigest> chunkDigests(String surfaceId, ChunkRange range) =>
      _queries.chunkDigests(surfaceId, range);

  @override
  Map<ChunkKey, int> chunkDensity(String surfaceId) => _queries.chunkDensity(surfaceId);

  @override
  Rect? contentBounds(String surfaceId) => _queries.contentBounds(surfaceId);
}
