import 'dart:async';
import 'dart:developer' as developer;
import 'dart:math' as math;
import 'dart:ui' as ui;

import '../../domain/chunk_grid.dart';
import '../../domain/surface_element.dart';
import '../lab/perf_probe.dart';
import '../surface_model.dart';
import 'content_painter.dart';

/// Caches one recorded [ui.Picture] per populated chunk of a surface.
///
/// Each picture contains every stroke overlapping its chunk, clipped to the
/// chunk's square. Clipping means each pixel is painted by exactly one chunk,
/// so strokes crossing chunk borders are not double-blended (which would
/// show for translucent highlighter ink). Content is layered by
/// [ContentPainter] (images beneath the ink, highlighter beneath pen ink,
/// text above). Items the model marks hidden (being edited or selected)
/// are left out. Pictures are vector recordings, so ink stays sharp at any
/// zoom; they are rebuilt only when something in that chunk changes.
///
/// Images are the exception: a picture holds a bitmap decoded for the
/// zoom it was recorded at. Painters report the zoom with [setScale]; when
/// it crosses a power of two, chunks with images are re-recorded (asking
/// for sharper or smaller bitmaps), and when a bitmap finishes decoding
/// the chunks showing it are refreshed through the model.
class ChunkPictureCache {
  ChunkPictureCache(this.model, {double? devicePixelRatio})
    : devicePixelRatio =
          devicePixelRatio ?? ui.PlatformDispatcher.instance.implicitView?.devicePixelRatio ?? 1 {
    _subscription = model.invalidations.listen(_invalidate);
    _images = model.images?.changes.listen(_onImage);
  }

  final SurfaceModel model;

  /// Device pixels per logical pixel (picks image resolutions).
  final double devicePixelRatio;

  final Map<ChunkKey, ui.Picture> _pictures = {};
  late final StreamSubscription<Set<ChunkKey>?> _subscription;
  StreamSubscription<String>? _images;

  /// Image blobs drawn into each cached picture.
  final Map<ChunkKey, Set<String>> _blobs = {};

  /// log2 of the device pixels per world unit images are recorded at.
  int _level = 0;

  ui.Picture pictureFor(ChunkKey key) => _pictures[key] ??= _record(key);

  /// The cached picture of [key], without recording one.
  ui.Picture? peek(ChunkKey key) => _pictures[key];

  /// Tells the cache the viewport scale (logical pixels per world unit)
  /// content is about to be painted at. Safe to call while painting.
  void setScale(double scale) {
    final pixels = scale * devicePixelRatio;
    if (!pixels.isFinite || pixels <= 0) return;
    final level = (math.log(pixels) / math.ln2).ceil().clamp(-16, 8);
    if (level == _level) return;
    _level = level;
    for (final key in _blobs.keys.toList()) {
      _drop(key);
    }
  }

  ui.Picture _record(ChunkKey key) {
    developer.Timeline.startSync('len.recordChunk');
    PerfProbe.count('chunkRecords');
    final recorder = ui.PictureRecorder();
    final canvas = ui.Canvas(recorder)..clipRect(ChunkGrid.rectOf(key), doAntiAlias: false);
    final elements = [
      for (final e in model.elementsInChunk(key))
        if (!model.isHidden(e.id)) e,
    ];
    ContentPainter.paint(
      canvas,
      [
        for (final s in model.strokesInChunk(key))
          if (!model.isHidden(s.id)) s,
      ],
      elements,
      images: model.images,
      pixelScale: math.pow(2, _level).toDouble(),
    );
    final blobs = {
      for (final e in elements)
        if (e.knownType == ElementType.image && e.data['blob'] is String) e.data['blob']! as String,
    };
    if (blobs.isNotEmpty) _blobs[key] = blobs;
    final picture = recorder.endRecording();
    developer.Timeline.finishSync();
    return picture;
  }

  void _onImage(String blob) => model.refresh({
    for (final entry in _blobs.entries)
      if (entry.value.contains(blob)) entry.key,
  });

  void _drop(ChunkKey key) {
    _pictures.remove(key)?.dispose();
    _blobs.remove(key);
  }

  void _invalidate(Set<ChunkKey>? keys) {
    if (keys == null) {
      for (final p in _pictures.values) {
        p.dispose();
      }
      _pictures.clear();
      _blobs.clear();
      return;
    }
    keys.forEach(_drop);
  }

  void dispose() {
    unawaited(_subscription.cancel());
    unawaited(_images?.cancel());
    _invalidate(null);
  }
}
