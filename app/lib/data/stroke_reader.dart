import 'dart:async';
import 'dart:ui';

import '../domain/chunk_digest.dart';
import '../domain/chunk_grid.dart';
import '../domain/stroke.dart';
import '../domain/surface_element.dart';

/// The result of reading part of a surface: the populated chunks that were
/// read and every live stroke and element touching them.
class ChunkLoad {
  const ChunkLoad({required this.chunks, required this.strokes, this.elements = const []});

  static const ChunkLoad empty = ChunkLoad(chunks: [], strokes: []);

  final List<ChunkKey> chunks;
  final List<Stroke> strokes;
  final List<SurfaceElement> elements;
}

/// Read-only access to a surface's stored strokes and elements, used for lazy loading and for
/// overviews of a whole surface ("fit to content").
///
/// Results may arrive synchronously (a reader on the UI isolate's
/// connection, as in tests) or asynchronously (a background isolate), so
/// callers must handle both shapes of [FutureOr].
abstract interface class StrokeReader {
  /// Populated chunks of [surfaceId] within [range] except those in [skip],
  /// with every live stroke and element touching them.
  FutureOr<ChunkLoad> read(String surfaceId, ChunkRange range, {Set<ChunkKey> skip});

  /// The content digest of every populated chunk of [surfaceId] within
  /// [range] (see `ChunkDigest`), without loading any of it.
  FutureOr<Map<ChunkKey, ChunkDigest>> chunkDigests(String surfaceId, ChunkRange range);

  /// Number of strokes and elements indexed in each populated chunk of [surfaceId].
  FutureOr<Map<ChunkKey, int>> chunkDensity(String surfaceId);

  /// Bounds of all live content on [surfaceId], or null if it is empty.
  FutureOr<Rect?> contentBounds(String surfaceId);
}
