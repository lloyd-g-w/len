import 'dart:async';

import 'package:flutter/material.dart';

import '../../../domain/chunk_grid.dart';
import '../../../domain/paper.dart';
import '../../../ink/surface_model.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/floating_panel.dart';
import 'canvas_navigation.dart';
import 'minimap_painter.dart';

/// An overview of the whole canvas: where there is ink and which part is
/// on screen. Tap to glide there, drag to move the view.
///
/// The populated chunks come from storage (not just what is loaded), read
/// in the background, and are refreshed shortly after edits.
class CanvasMinimap extends StatefulWidget {
  const CanvasMinimap({
    super.key,
    required this.navigation,
    required this.model,
    this.paperColor = PaperColor.white,
    this.size,
  });

  final CanvasNavigation navigation;
  final SurfaceModel model;

  /// The canvas background, mirrored by the map.
  final PaperColor paperColor;

  /// Size of the map; defaults to [defaultSize].
  final Size? size;

  static const Size defaultSize = Size(200, 136);

  /// Delay after an edit before the overview is re-read.
  static const Duration refreshDelay = Duration(milliseconds: 400);

  @override
  State<CanvasMinimap> createState() => _CanvasMinimapState();
}

class _CanvasMinimapState extends State<CanvasMinimap> {
  Map<ChunkKey, int> _density = const {};
  Timer? _refresh;
  int _request = 0;
  MinimapProjection? _dragProjection;

  @override
  void initState() {
    super.initState();
    widget.model.addListener(_scheduleRefresh);
    unawaited(_load());
  }

  @override
  void didUpdateWidget(CanvasMinimap old) {
    super.didUpdateWidget(old);
    if (old.model != widget.model) {
      old.model.removeListener(_scheduleRefresh);
      widget.model.addListener(_scheduleRefresh);
      unawaited(_load());
    }
  }

  @override
  void dispose() {
    widget.model.removeListener(_scheduleRefresh);
    _refresh?.cancel();
    super.dispose();
  }

  void _scheduleRefresh() {
    _refresh?.cancel();
    _refresh = Timer(CanvasMinimap.refreshDelay, () => unawaited(_load()));
  }

  Future<void> _load() async {
    final request = ++_request;
    final nav = widget.navigation;
    final density = await nav.reader.chunkDensity(nav.surfaceId);
    if (!mounted || request != _request) return;
    setState(() => _density = density);
  }

  Size get _size => widget.size ?? CanvasMinimap.defaultSize;

  MinimapProjection _projection() => MinimapProjection(
    MinimapProjection.extentOf(_density.keys, widget.navigation.viewport.visibleWorld),
    _size,
  );

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final nav = widget.navigation;
    return FloatingPanel(
      padding: const EdgeInsets.all(Gaps.xs),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(Radii.cover),
        child: Semantics(
          label: 'Canvas overview',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTapUp: (d) => nav.glideTo(_projection().toWorld(d.localPosition)),
            onPanStart: (d) => setState(() => _dragProjection = _projection()),
            onPanUpdate: (d) => nav.jumpTo(_dragProjection!.toWorld(d.localPosition)),
            onPanEnd: (_) => setState(() => _dragProjection = null),
            onPanCancel: () => setState(() => _dragProjection = null),
            child: ColoredBox(
              color: widget.paperColor.paper,
              child: CustomPaint(
                size: _size,
                painter: MinimapPainter(
                  density: _density,
                  viewport: nav.viewport,
                  frozen: _dragProjection,
                  colors: MinimapColors(
                    ink: widget.paperColor.isDark ? Colors.white60 : Colors.black54,
                    // The frame sits on the paper: the accent for its brightness.
                    view: widget.paperColor.isDark == (scheme.brightness == Brightness.dark)
                        ? scheme.primary
                        : scheme.inversePrimary,
                    origin: scheme.outline,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
