import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

import '../../domain/chunk_grid.dart';
import '../input/live_ink.dart';
import '../surface_model.dart';
import '../viewport.dart';
import 'chunk_picture_cache.dart';
import 'stroke_renderer.dart';

/// Paints committed strokes: only the populated chunks that intersect the
/// visible area, each from its cached picture.
class CommittedInkPainter extends CustomPainter {
  CommittedInkPainter({
    required this.model,
    required this.cache,
    required this.viewport,
    this.clip,
  }) : super(repaint: Listenable.merge([model, viewport]));

  final SurfaceModel model;
  final ChunkPictureCache cache;
  final ViewportController viewport;

  /// Optional world-space clip (the page rectangle).
  final Rect? clip;

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
    for (final key in chunks) {
      canvas.drawPicture(cache.pictureFor(key));
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(CommittedInkPainter old) =>
      old.model != model || old.cache != cache || old.viewport != viewport || old.clip != clip;
}

/// Paints the in-progress stroke and the eraser cursor. Repaints on every
/// pointer move, so it is kept as cheap as possible.
class LiveInkPainter extends CustomPainter {
  LiveInkPainter({required this.live, required this.viewport, this.clip})
      : super(repaint: Listenable.merge([live, viewport]));

  final LiveInk live;
  final ViewportController viewport;
  final Rect? clip;

  /// Outline of the live stroke, rebuilt only when [LiveInk.revision]
  /// changes (not when merely the viewport or eraser cursor moves).
  Path? _path;
  int _pathRevision = -1;

  static final Paint _eraserFill = Paint()..color = const Color(0x22000000);
  static final Paint _eraserOutline = Paint()
    ..style = PaintingStyle.stroke
    ..color = const Color(0x99000000);

  Path _livePath() {
    if (_path == null || _pathRevision != live.revision) {
      _path = StrokeRenderer.buildPath(
        live.points,
        tool: live.tool,
        width: live.width,
        complete: false,
      );
      _pathRevision = live.revision;
    }
    return _path!;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (!live.isDrawing && live.eraserCenter == null) return;
    canvas
      ..save()
      ..translate(viewport.offset.dx, viewport.offset.dy)
      ..scale(viewport.scale);
    if (live.isDrawing) {
      if (clip != null) canvas.clipRect(clip!);
      canvas.drawPath(_livePath(), StrokeRenderer.paintFor(live.tool, live.color));
    }
    final eraser = live.eraserCenter;
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
      old.live != live || old.viewport != viewport || old.clip != clip;
}
