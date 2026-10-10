import 'dart:async';
import 'dart:ui' as ui;

import '../../domain/chunk_grid.dart';
import '../surface_model.dart';
import 'stroke_renderer.dart';

/// Caches one recorded [ui.Picture] per populated chunk of a surface.
///
/// Each picture contains every stroke overlapping its chunk, clipped to the
/// chunk's square. Clipping means each pixel is painted by exactly one chunk,
/// so strokes crossing chunk borders are not double-blended (which would
/// show for translucent highlighter ink). Highlighter strokes are drawn
/// beneath all other ink of the chunk. Pictures are vector recordings, so
/// they stay sharp at any zoom; they are rebuilt only when a stroke in that
/// chunk changes.
class ChunkPictureCache {
  ChunkPictureCache(this.model) {
    _subscription = model.invalidations.listen(_invalidate);
  }

  final SurfaceModel model;
  final Map<ChunkKey, ui.Picture> _pictures = {};
  late final StreamSubscription<Set<ChunkKey>?> _subscription;

  ui.Picture pictureFor(ChunkKey key) => _pictures[key] ??= _record(key);

  /// The cached picture of [key], without recording one.
  ui.Picture? peek(ChunkKey key) => _pictures[key];

  ui.Picture _record(ChunkKey key) {
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)..clipRect(ChunkGrid.rectOf(key), doAntiAlias: false);
    // Highlighter ink goes underneath pen ink, like a real highlighter
    // pass over printed text; within each group paint order is kept.
    final strokes = model.strokesInChunk(key);
    for (final stroke in strokes) {
      if (stroke.tool.isHighlighter) StrokeRenderer.draw(canvas, stroke);
    }
    for (final stroke in strokes) {
      if (!stroke.tool.isHighlighter) StrokeRenderer.draw(canvas, stroke);
    }
    return recorder.endRecording();
  }

  void _invalidate(Set<ChunkKey>? keys) {
    if (keys == null) {
      for (final p in _pictures.values) {
        p.dispose();
      }
      _pictures.clear();
      return;
    }
    for (final key in keys) {
      _pictures.remove(key)?.dispose();
    }
  }

  void dispose() {
    unawaited(_subscription.cancel());
    _invalidate(null);
  }
}
