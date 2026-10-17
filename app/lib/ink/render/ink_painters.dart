import 'dart:math' as math;

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
import 'lod_painting.dart';
import 'stroke_renderer.dart';
import 'tiles/ink_tile_cache.dart';
import 'tiles/tile_space.dart';

/// Paints [tiles] in [view] onto [canvas] (logical pixels), drawing the
/// areas without tile images from the chunk pictures.
void paintTiled(Canvas canvas, InkTileCache tiles, TileView view, double devicePixelRatio) {
  canvas
    ..save()
    ..scale(1 / devicePixelRatio);
  tiles.paint(canvas, view, (canvas, view, rects) {
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

  /// Chunks without a raster that one frame may record as vectors.
  static const int freshRecordingsPerFrame = lodFreshRecordingsPerFrame;

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
    final k = viewport.scale * devicePixelRatio;
    // Far out, LOD chunk rasters (one image per chunk) are cheaper; they
    // may show chunks not in memory (see `SurfaceModel.showStored`).
    final level = rasters == null ? null : ChunkRasterCache.levelFor(ChunkGrid.size * k);
    final chunks = level != null ? null : model.chunksIn(ChunkGrid.rangeFor(visible));
    if (chunks != null && chunks.isEmpty) return;
    cache.setScale(viewport.scale); // Image resolution.
    final view = TileView(
      k: k,
      origin: viewport.offset * devicePixelRatio,
      visible: visible,
      clip: clip,
    );
    if (level != null) {
      paintLod(
        canvas,
        rasters: rasters!,
        view: view,
        level: level,
        devicePixelRatio: devicePixelRatio,
        tiles: tiles,
      );
    } else if (tiles != null) {
      paintTiled(canvas, tiles!, view, devicePixelRatio);
    } else {
      canvas
        ..save()
        ..translate(viewport.offset.dx, viewport.offset.dy)
        ..scale(viewport.scale);
      if (clip != null) canvas.clipRect(clip!);
      for (final key in chunks!) {
        canvas.drawPicture(cache.pictureFor(key));
      }
      PerfProbe.count('chunkDraws', chunks.length);
      canvas.restore();
    }
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

  // The eraser's ring is two-tone, a dark line inside a light one, and its
  // fill a neutral grey, so it shows on any paper and ink (dark paper too).
  static final Paint _eraserFill = Paint()..color = const Color(0x2A808080);
  static final Paint _eraserOutline = Paint()
    ..style = PaintingStyle.stroke
    ..color = const Color(0x99000000);
  static final Paint _eraserHalo = Paint()
    ..style = PaintingStyle.stroke
    ..color = const Color(0x99FFFFFF);
  static final Paint _penPreview = Paint()..isAntiAlias = true;

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
    final pen = belowInk || live.isDrawing ? null : live.penCenter;
    if (!drawing && eraser == null && pen == null) return;
    canvas
      ..save()
      ..translate(viewport.offset.dx, viewport.offset.dy)
      ..scale(viewport.scale);
    if (drawing) {
      if (clip != null) canvas.clipRect(clip!);
      final outline = _livePath();
      // A filled shape: its fill beneath the outline, as once committed.
      final fill = live.style.fill;
      if (fill != null && live.points.length >= 4) {
        canvas.drawPath(StrokeRenderer.fillPath(live.points), StrokeRenderer.fillPaint(fill));
      }
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
      if (live.tip.isNotEmpty) _paintTip(canvas, paint.color);
    }
    if (eraser != null) {
      final px = 1 / viewport.scale; // One screen pixel.
      _eraserOutline.strokeWidth = px;
      _eraserHalo.strokeWidth = px;
      canvas
        ..drawCircle(eraser, live.eraserRadius, _eraserFill)
        ..drawCircle(eraser, live.eraserRadius + px, _eraserHalo)
        ..drawCircle(eraser, live.eraserRadius, _eraserOutline);
    }
    if (pen != null) {
      // At least a dot two screen pixels wide, so the finest pen shows.
      final radius = math.max(live.penRadius, 1 / viewport.scale);
      canvas.drawCircle(pen, radius, _penPreview..color = live.penColor);
    }
    canvas.restore();
  }

  /// A mouse stroke's provisional tip ([LiveInk.tip]): a line as wide as the
  /// stroke's last point (a mouse has no pressure) on from it, with the
  /// stroke's end.
  void _paintTip(Canvas canvas, Color color) {
    final spec = StrokeRenderer.specFor(live.width, live.style);
    final from = live.points.last;
    final line = Path()..moveTo(from.x, from.y);
    for (final p in live.tip) {
      line.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
      line,
      _tip
        ..color = color
        ..strokeWidth = 2 * spec.radiusFor(from.pressure)
        ..strokeCap = spec.flatCaps ? StrokeCap.butt : StrokeCap.round,
    );
  }

  static final Paint _tip = Paint()
    ..style = PaintingStyle.stroke
    ..strokeJoin = StrokeJoin.round
    ..isAntiAlias = true;

  @override
  bool shouldRepaint(LiveInkPainter old) =>
      old.live != live || old.viewport != viewport || old.clip != clip || old.belowInk != belowInk;
}
