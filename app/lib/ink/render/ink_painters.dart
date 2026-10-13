import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../../domain/chunk_grid.dart';
import '../input/live_ink.dart';
import '../lab/perf_probe.dart';
import '../surface_model.dart';
import '../viewport.dart';
import 'chunk_picture_cache.dart';
import 'chunk_raster_cache.dart';
import 'live_stroke.dart';
import 'stroke_renderer.dart';
import 'tiles/ink_tile_cache.dart';
import 'tiles/tile_space.dart';

/// Paints [tiles] in [view] onto [canvas] (logical pixels), drawing the
/// areas without tile images from the chunk pictures.
void paintTiled(Canvas canvas, InkTileCache tiles, TileView view, double devicePixelRatio) {
  canvas
    ..save()
    ..scale(1 / devicePixelRatio);
  tiles.paint(canvas, view, (canvas, rects) {
    final clip = Path();
    final chunks = <ChunkKey>{};
    for (final rect in rects) {
      final area = view.clip == null ? rect : rect.intersect(view.clip!);
      if (area.isEmpty) continue;
      clip.addRect(area);
      chunks.addAll(tiles.model.chunksIn(ChunkGrid.rangeFor(area)));
    }
    canvas
      ..save()
      ..translate(view.origin.dx, view.origin.dy)
      ..scale(view.k)
      ..clipPath(clip, doAntiAlias: false);
    for (final key in chunks) {
      canvas.drawPicture(tiles.pictures.pictureFor(key));
    }
    PerfProbe.count('chunkDraws', chunks.length);
    canvas.restore();
  });
  canvas.restore();
}

/// Paints committed strokes: from [tiles] (images of the ink at the
/// current zoom) when given, or else from the cached pictures of the
/// populated chunks that intersect the visible area — and, when zoomed out
/// far enough and [rasters] is given, from level-of-detail chunk rasters.
class CommittedInkPainter extends CustomPainter {
  CommittedInkPainter({
    required this.model,
    required this.cache,
    required this.viewport,
    this.clip,
    this.rasters,
    this.tiles,
    this.devicePixelRatio = 1,
    this.self = const {},
  }) : super(
         repaint: Listenable.merge([
           model,
           viewport,
           rasters,
           tiles,
           ForeignLiftedChanges(model.liftedChanges, () => model.lastLiftedOwner, self),
         ]),
       );

  /// This view's own selection and text editor: what they lift out of the
  /// surface they draw themselves; other owners' (another view of it) is
  /// drawn here, over the ink.
  final Set<Object?> self;

  final SurfaceModel model;
  final ChunkPictureCache cache;
  final ViewportController viewport;

  /// Optional world-space clip (the page rectangle).
  final Rect? clip;

  /// Level-of-detail rasters for zoomed-out views; null = always vectors.
  final ChunkRasterCache? rasters;

  /// Tile raster cache; null = chunk pictures (and LOD rasters) only.
  final InkTileCache? tiles;

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
    _paintInk(canvas, size);
    if (!model.hasLiftedExcept(self)) return;
    canvas
      ..save()
      ..translate(viewport.offset.dx, viewport.offset.dy)
      ..scale(viewport.scale);
    if (clip != null) canvas.clipRect(clip!);
    model.paintLifted(canvas, except: self);
    canvas.restore();
  }

  void _paintInk(Canvas canvas, Size size) {
    final visible = viewport.visibleWorldFor(size);
    final chunks = model.chunksIn(ChunkGrid.rangeFor(visible));
    if (chunks.isEmpty) return;
    final k = viewport.scale * devicePixelRatio;
    final tiles = this.tiles;
    // Far out, LOD chunk rasters (one image per chunk) are cheaper.
    if (tiles != null &&
        (rasters == null || ChunkRasterCache.levelFor(ChunkGrid.size * k) == null)) {
      cache.setScale(viewport.scale); // Image resolution.
      paintTiled(
        canvas,
        tiles,
        TileView(k: k, origin: viewport.offset * devicePixelRatio, visible: visible, clip: clip),
        devicePixelRatio,
      );
      return;
    }

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
        final rect = ChunkGrid.rectOf(key);
        canvas.drawImageRect(image, source, rect, _imagePaint);
        final overlay = rasters!.overlayOf(key, image);
        if (overlay.isNotEmpty) {
          // Strokes committed since the raster was made, until it is redone.
          canvas
            ..save()
            ..clipRect(rect);
          for (final stroke in overlay) {
            StrokeRenderer.draw(canvas, stroke);
          }
          canvas.restore();
        }
        continue;
      }
      final picture = level == null
          ? cache.pictureFor(key)
          : cache.peek(key) ?? (fresh-- > 0 ? cache.pictureFor(key) : null);
      if (picture != null) canvas.drawPicture(picture);
    }
    PerfProbe.count('chunkDraws', chunks.length);
    canvas.restore();
  }

  @override
  bool shouldRepaint(CommittedInkPainter old) =>
      old.model != model ||
      old.cache != cache ||
      old.viewport != viewport ||
      old.clip != clip ||
      old.rasters != rasters ||
      old.tiles != tiles ||
      old.devicePixelRatio != devicePixelRatio ||
      !setEquals(old.self, self);
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
  LiveOutline? _path;
  int _pathRevision = -1;

  static final Paint _eraserFill = Paint()..color = const Color(0x22000000);
  static final Paint _eraserOutline = Paint()
    ..style = PaintingStyle.stroke
    ..color = const Color(0x99000000);

  /// Told how long each live outline took to build (the Ink Lab's stats).
  static void Function(int points, Duration took)? onBuild;

  LiveOutline _livePath() {
    if (_path == null || _pathRevision != live.revision) {
      final watch = onBuild == null ? null : (Stopwatch()..start());
      // Incremental: the builder is kept with the [LiveInk] (painters are
      // recreated on rebuilds), and hands the committed outline over at
      // pen-up.
      _path = LiveStrokeBuilder.livePath(live);
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
      final outline = _livePath();
      final paint = StrokeRenderer.paintFor(live.color, live.style);
      final frozen = outline.frozen;
      if (frozen != null && paint.color.a >= 1) {
        // Opaque ink: the frozen part and the tail overlap (the tail's cap),
        // so they can be filled separately, without copying the frozen part.
        canvas
          ..drawPath(frozen, paint)
          ..drawPath(outline.tail, paint);
      } else {
        // Translucent ink must be filled in one go.
        canvas.drawPath(outline.combined, paint);
      }
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
