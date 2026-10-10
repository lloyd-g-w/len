import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../domain/paper.dart';
import 'input/ink_input_controller.dart';
import 'input/live_ink.dart';
import 'render/chunk_picture_cache.dart';
import 'render/ink_painters.dart';
import 'render/paper_painter.dart';
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
    required this.paper,
    this.page,
  });

  final SurfaceModel model;
  final ViewportController viewport;
  final InkInputController input;
  final LiveInk live;
  final PaperStyle paper;

  /// The page rectangle for paged notebooks; null for an infinite canvas.
  final Rect? page;

  @override
  State<InkSurface> createState() => _InkSurfaceState();
}

class _InkSurfaceState extends State<InkSurface> {
  late ChunkPictureCache _cache;

  @override
  void initState() {
    super.initState();
    _cache = ChunkPictureCache(widget.model);
    widget.viewport.addListener(_loadVisible);
    _loadVisibleAfterFrame();
  }

  @override
  void didUpdateWidget(InkSurface old) {
    super.didUpdateWidget(old);
    if (old.model != widget.model) {
      _cache.dispose();
      _cache = ChunkPictureCache(widget.model);
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
    _cache.dispose();
    super.dispose();
  }

  void _loadVisible() => widget.model.ensureLoaded(widget.viewport.visibleWorld);

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
            child: Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(
                  child: CustomPaint(
                    painter: PaperPainter(
                      viewport: widget.viewport,
                      style: widget.paper,
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
