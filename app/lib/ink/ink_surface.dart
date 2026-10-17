import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../domain/chunk_grid.dart';
import '../domain/paper.dart';
import 'input/ink_input_controller.dart';
import 'input/live_ink.dart';
import 'remote_ink.dart';
import 'render/chunk_picture_cache.dart';
import 'render/chunk_raster_cache.dart';
import 'render/ink_painters.dart';
import 'render/paper_painter.dart';
import 'render/remote_ink_painter.dart';
import 'render/stored_rasters.dart';
import 'render/tiles/ink_tile_cache.dart';
import 'surface_model.dart';
import 'viewport.dart';

/// An interactive drawing surface: paper, committed ink and live ink in
/// three layers, fed by raw pointer events (for pressure and low latency —
/// no gesture-arena delay).
class InkSurface extends StatefulWidget {
  const InkSurface({
    super.key,
    required this.model,
    required this.viewport,
    required this.input,
    required this.live,
    this.remote,
    required this.paper,
    this.paperColor = PaperColor.white,
    this.page,
  });

  final SurfaceModel model;
  final ViewportController viewport;
  final InkInputController input;
  final LiveInk live;

  /// Strokes other devices are writing here right now (live sync).
  final RemoteInk? remote;
  final Paper paper;
  final PaperColor paperColor;

  /// The page rectangle for paged notebooks; null for an infinite canvas.
  final Rect? page;

  @override
  State<InkSurface> createState() => _InkSurfaceState();
}

class _InkSurfaceState extends State<InkSurface> {
  late ChunkPictureCache _cache;
  late ChunkRasterCache _rasters;
  late InkTileCache _tiles;

  @override
  void initState() {
    super.initState();
    _cache = ChunkPictureCache(widget.model);
    _rasters = ChunkRasterCache(_cache);
    _tiles = InkTileCache(_cache);
    widget.viewport.addListener(_loadVisible);
    _loadVisibleAfterFrame();
  }

  @override
  void didUpdateWidget(InkSurface old) {
    super.didUpdateWidget(old);
    if (old.model != widget.model || old.viewport != widget.viewport) {
      old.model.forgetView(old.viewport);
    }
    if (old.model != widget.model) {
      _tiles.dispose();
      _rasters.dispose();
      _cache.dispose();
      _cache = ChunkPictureCache(widget.model);
      _rasters = ChunkRasterCache(_cache);
      _tiles = InkTileCache(_cache);
      _loadVisibleAfterFrame();
    }
    if (old.viewport != widget.viewport) {
      old.viewport.removeListener(_loadVisible);
      widget.viewport.addListener(_loadVisible);
    }
  }

  @override
  void dispose() {
    widget.viewport.removeListener(_loadVisible);
    widget.model.forgetView(widget.viewport);
    _tiles.dispose();
    _rasters.dispose();
    _cache.dispose();
    super.dispose();
  }

  /// Device pixels per logical pixel, as last built.
  double _devicePixelRatio = 1;

  /// Loads what is visible — or, zoomed out so far that chunks are drawn
  /// from rasters a store keeps, only what has no stored raster.
  void _loadVisible() {
    final model = widget.model, viewport = widget.viewport;
    if (model.rasterStore != null &&
        ChunkGrid.size * viewport.scale * _devicePixelRatio <= StoredRasters.maxLevel) {
      model.showStored(viewport.visibleWorld, view: viewport);
    } else {
      model.ensureLoaded(viewport.visibleWorld, view: viewport);
    }
  }

  /// Loading notifies model listeners, which must not happen during build.
  void _loadVisibleAfterFrame() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _loadVisible();
    });
  }

  void _onLayout(Size size) {
    if (size == widget.viewport.size) return;
    // Viewport listeners may rebuild other widgets; never notify mid-build.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.viewport.setSize(size);
    });
  }

  @override
  Widget build(BuildContext context) {
    _devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    final input = widget.input;
    return LayoutBuilder(
      builder: (context, constraints) {
        _onLayout(constraints.biggest);
        return MouseRegion(
          cursor: SystemMouseCursors.precise,
          onExit: (_) => input.handleExit(),
          child: Listener(
            behavior: HitTestBehavior.opaque,
            onPointerDown: input.handleDown,
            onPointerMove: input.handleMove,
            onPointerUp: input.handleUp,
            onPointerCancel: input.handleCancel,
            onPointerHover: input.handleHover,
            onPointerSignal: (e) {
              // Claim the event so enclosing scrollables don't also react.
              GestureBinding.instance.pointerSignalResolver.register(e, input.handleSignal);
            },
            onPointerPanZoomStart: input.handlePanZoomStart,
            onPointerPanZoomUpdate: input.handlePanZoomUpdate,
            onPointerPanZoomEnd: input.handlePanZoomEnd,
            child: Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(
                  child: CustomPaint(
                    painter: PaperPainter(
                      viewport: widget.viewport,
                      paper: widget.paper,
                      paperColor: widget.paperColor,
                      page: widget.page,
                    ),
                  ),
                ),
                RepaintBoundary(
                  child: CustomPaint(
                    painter: LiveInkPainter(
                      live: widget.live,
                      viewport: widget.viewport,
                      clip: widget.page,
                      belowInk: true,
                    ),
                  ),
                ),
                RepaintBoundary(
                  child: CustomPaint(
                    painter: CommittedInkPainter(
                      model: widget.model,
                      cache: _cache,
                      viewport: widget.viewport,
                      clip: widget.page,
                      rasters: _rasters,
                      tiles: _tiles,
                      devicePixelRatio: _devicePixelRatio,
                      self: {input.content?.selection, input.content?.text},
                    ),
                  ),
                ),
                if (widget.remote case final remote?)
                  RepaintBoundary(
                    child: CustomPaint(
                      painter: RemoteInkPainter(
                        remote: remote,
                        viewport: widget.viewport,
                        frameOf: (id) => id == widget.model.surfaceId ? Rect.largest : null,
                      ),
                    ),
                  ),
                RepaintBoundary(
                  child: CustomPaint(
                    painter: LiveInkPainter(
                      live: widget.live,
                      viewport: widget.viewport,
                      clip: widget.page,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
