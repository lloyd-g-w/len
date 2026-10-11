import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../../domain/chunk_grid.dart';
import '../input/live_ink.dart';
import '../surface_model.dart';
import '../viewport.dart';
import 'chunk_picture_cache.dart';
import 'chunk_raster_cache.dart';
import 'live_stroke.dart';
import 'stroke_renderer.dart';

/// Paints committed strokes: only the populated chunks that intersect the
/// visible area, each from its cached picture — or, when zoomed out far
/// enough and [rasters] is given, from a level-of-detail raster.
class CommittedInkPainter extends CustomPainter {
  CommittedInkPainter({
    required this.model,
    required this.cache,
    required this.viewport,
    this.clip,
    this.rasters,
    this.devicePixelRatio = 1,
  }) : super(repaint: Listenable.merge([model, viewport, rasters]));

  final SurfaceModel model;
  final ChunkPictureCache cache;
  final ViewportController viewport;

  /// Optional world-space clip (the page rectangle).
  final Rect? clip;

  /// Level-of-detail rasters for zoomed-out views; null = always vectors.
  final ChunkRasterCache? rasters;

  /// Device pixels per logical pixel (picks the raster resolution).
  final double devicePixelRatio;

  /// Chunks without a raster or cached picture that one frame may record
  /// as vectors (so a fresh edit shows at once while zoomed out, but a
  /// whole screen of uncached chunks never stalls a frame).
  static const int freshRecordingsPerFrame = 8;

  static final Paint _imagePaint = Paint()
    ..filterQuality = FilterQuality.medium
    // Unsmoothed edges: neighbouring chunks tile without seams.
    ..isAntiAlias = false;

  @override
  void paint(Canvas canvas, Size size) {
    final visible = viewport.visibleWorldFor(size);
    final chunks = model.chunksIn(ChunkGrid.rangeFor(visible));
    if (chunks.isEmpty) return;

    canvas
      ..save()
      ..translate(viewport.offset.dx, viewport.offset.dy)
      ..scale(viewport.scale);
    if (clip != null) canvas.clipRect(clip!);
    cache.setScale(viewport.scale); // Image resolution.
    final level = rasters == null
        ? null
        : ChunkRasterCache.levelFor(ChunkGrid.size * viewport.scale * devicePixelRatio);
    var fresh = freshRecordingsPerFrame;
    for (final key in chunks) {
      final image = level == null ? null : rasters!.imageFor(key, level);
      if (image != null) {
        final source = Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble());
        canvas.drawImageRect(image, source, ChunkGrid.rectOf(key), _imagePaint);
        continue;
      }
      final picture = level == null
          ? cache.pictureFor(key)
          : cache.peek(key) ?? (fresh-- > 0 ? cache.pictureFor(key) : null);
      if (picture != null) canvas.drawPicture(picture);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(CommittedInkPainter old) =>
      old.model != model ||
      old.cache != cache ||
      old.viewport != viewport ||
      old.clip != clip ||
      old.rasters != rasters ||
      old.devicePixelRatio != devicePixelRatio;
}

/// Paints the in-progress stroke and the eraser cursor. Repaints on every
/// pointer move, so it is kept as cheap as possible.
///
/// A live highlighter stroke is painted by a second instance with
/// [belowInk] set, placed under the committed ink, so it already appears
/// behind pen ink while it is drawn (matching how it is committed).
class LiveInkPainter extends CustomPainter {
  LiveInkPainter({required this.live, required this.viewport, this.clip, this.belowInk = false})
    : super(repaint: Listenable.merge([live, viewport]));

  final LiveInk live;
  final ViewportController viewport;
  final Rect? clip;

  /// Paint only highlighter strokes (and no eraser cursor); otherwise
  /// paint everything except highlighter strokes.
  final bool belowInk;

  /// Outline of the live stroke, rebuilt only when [LiveInk.revision]
  /// changes (not when merely the viewport or eraser cursor moves).
  Path? _path;
  int _pathRevision = -1;

  static final Paint _eraserFill = Paint()..color = const Color(0x22000000);
  static final Paint _eraserOutline = Paint()
    ..style = PaintingStyle.stroke
    ..color = const Color(0x99000000);

  /// Told how long each live outline took to build (the Ink Lab's stats).
  static void Function(int points, Duration took)? onBuild;

  /// Incremental outline builders, one per live stroke (kept with the
  /// [LiveInk], since painters are recreated on rebuilds).
  static final Expando<LiveStrokeBuilder> _builders = Expando('live stroke builders');

  Path _livePath() {
    if (_path == null || _pathRevision != live.revision) {
      final watch = onBuild == null ? null : (Stopwatch()..start());
      final built = LiveStrokeBuilder.build(
        _builders[live],
        live.points,
        tool: live.tool,
        width: live.width,
        style: live.style,
      );
      _builders[live] = built.builder;
      _path = built.path;
      _pathRevision = live.revision;
      if (watch != null) onBuild?.call(live.points.length, watch.elapsed);
    }
    return _path!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final drawing = live.isDrawing && live.tool.isHighlighter == belowInk;
    final eraser = belowInk ? null : live.eraserCenter;
    if (!drawing && eraser == null) return;
    canvas
      ..save()
      ..translate(viewport.offset.dx, viewport.offset.dy)
      ..scale(viewport.scale);
    if (drawing) {
      if (clip != null) canvas.clipRect(clip!);
      canvas.drawPath(_livePath(), StrokeRenderer.paintFor(live.tool, live.color, live.style));
    }
    if (eraser != null) {
      _eraserOutline.strokeWidth = 1 / viewport.scale; // One screen pixel.
      canvas
        ..drawCircle(eraser, live.eraserRadius, _eraserFill)
        ..drawCircle(eraser, live.eraserRadius, _eraserOutline);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(LiveInkPainter old) =>
      old.live != live || old.viewport != viewport || old.clip != clip || old.belowInk != belowInk;
}
