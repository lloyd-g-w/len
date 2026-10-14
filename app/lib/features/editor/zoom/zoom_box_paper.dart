import 'package:flutter/material.dart';

import '../../../domain/paper.dart';
import '../../../ink/render/chunk_picture_cache.dart';
import '../../../ink/render/ink_painters.dart';
import '../../../ink/render/tiles/ink_tile_cache.dart';
import '../../../ink/surface_model.dart';
import '../editor_session.dart';
import 'zoom_box_grip.dart';
import 'zoom_box_painters.dart';
import 'zoom_window.dart';

/// What the zoom box shows: the frame's paper, the advance zone, the ink
/// (committed, and live while the frame's page takes the input) and the
/// grip on its inner edge. Pointers are the box's.
class ZoomBoxPaper extends StatefulWidget {
  const ZoomBoxPaper({
    super.key,
    required this.session,
    required this.gripAtBottom,
    required this.onStep,
  });

  final EditorSession session;

  /// Whether the grip lies along the bottom edge (the box docks at the top).
  final bool gripAtBottom;

  /// Grows or shrinks the box by a step (the grip's semantic actions).
  final ValueChanged<double> onStep;

  @override
  State<ZoomBoxPaper> createState() => _ZoomBoxPaperState();
}

class _ZoomBoxPaperState extends State<ZoomBoxPaper> {
  ZoomWindow get _zoom => widget.session.zoomWindow;

  /// This view's render caches of the frame's surface.
  SurfaceModel? _cached;
  ChunkPictureCache? _cache;
  InkTileCache? _tiles;

  @override
  void dispose() {
    _dropCaches();
    super.dispose();
  }

  void _dropCaches() {
    _tiles?.dispose();
    _cache?.dispose();
    _tiles = null;
    _cache = null;
    _cached = null;
  }

  void _cachesFor(SurfaceModel model) {
    if (identical(model, _cached)) return;
    _dropCaches();
    _cached = model;
    _cache = ChunkPictureCache(model);
    _tiles = InkTileCache(_cache!);
  }

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final host = _zoom.host;
    return ListenableBuilder(
      listenable: Listenable.merge([_zoom, host.changes]),
      builder: (context, _) {
        final frame = _zoom.frame;
        final model = _zoom.model;
        if (frame == null || model == null) return const SizedBox.expand();
        _cachesFor(model);
        final page = host.boundsOf(frame.surfaceId);
        final live = host.isActive(frame.surfaceId);
        final view = _zoom.view;
        final zone = _zoom.zoneStart;
        return Stack(
          fit: StackFit.expand,
          children: [
            RepaintBoundary(
              child: CustomPaint(
                painter: zoomPaperPainter(context, session, frame.surfaceId, view),
              ),
            ),
            if (zone != null)
              ZoneBand(
                armed: _zoom.armed,
                start: view.toScreen(Offset(zone, 0)).dx,
                paper: _paperColour(frame.surfaceId),
              ),
            if (live)
              RepaintBoundary(
                child: CustomPaint(
                  painter: LiveInkPainter(
                    live: session.live,
                    viewport: view,
                    clip: page,
                    belowInk: true,
                  ),
                ),
              ),
            RepaintBoundary(
              child: CustomPaint(
                painter: CommittedInkPainter(
                  model: model,
                  cache: _cache!,
                  viewport: view,
                  clip: page,
                  tiles: _tiles,
                  devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
                  self: {session.content.selection, session.content.text},
                ),
              ),
            ),
            if (live)
              RepaintBoundary(
                child: CustomPaint(
                  painter: LiveInkPainter(live: session.live, viewport: view, clip: page),
                ),
              ),
            Positioned(
              left: 0,
              right: 0,
              top: widget.gripAtBottom ? null : 0,
              bottom: widget.gripAtBottom ? 0 : null,
              child: ZoomBoxGrip(
                atBottom: widget.gripAtBottom,
                color: _paperColour(frame.surfaceId).pattern,
                onStep: widget.onStep,
              ),
            ),
          ],
        );
      },
    );
  }

  PaperColor _paperColour(String surfaceId) {
    final doc = widget.session.doc;
    if (doc == null) return widget.session.notebook.paperColor;
    final page = doc.pages.where((p) => p.id == surfaceId).firstOrNull;
    return page?.paperColor ?? widget.session.notebook.paperColor;
  }
}
