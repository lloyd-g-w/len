import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../domain/paper.dart';
import '../../../ink/input/stylus_buttons.dart';
import '../../../ink/render/chunk_picture_cache.dart';
import '../../../ink/render/ink_painters.dart';
import '../../../ink/render/tiles/ink_tile_cache.dart';
import '../../../ink/surface_model.dart';
import '../../../ink/tool_settings.dart';
import '../../../ui/app_theme.dart';
import '../chrome/bar_button.dart';
import '../editor_session.dart';
import 'zoom_box_painters.dart';
import 'zoom_window.dart';

/// The zoom window's box, docked at the bottom of the editor: the frame's
/// part of the page, magnified, to write in, and a rail with ✕ (close) and
/// ↵ (next line). Pointers go to the window's own input controller, so
/// ink is made exactly as on the page, at the box's zoom.
class ZoomBox extends StatefulWidget {
  const ZoomBox({super.key, required this.session, this.padding = EdgeInsets.zero});

  final EditorSession session;

  /// Room kept clear at the sides (a phone's notch, held sideways).
  final EdgeInsets padding;

  /// The box's height in an editor with [free] pixels of height between
  /// its top and bottom chrome: about a third, leaving the page room.
  static double heightFor(double free) {
    const share = 0.36, least = 112.0, most = 300.0, page = 120.0;
    final h = (free * share).clamp(least, most);
    return h.clamp(0, (free - page).clamp(0, most)).toDouble();
  }

  @override
  State<ZoomBox> createState() => _ZoomBoxState();
}

class _ZoomBoxState extends State<ZoomBox> {
  ZoomWindow get _zoom => widget.session.zoomWindow;
  ToolSettings get _tools => widget.session.tools;

  /// This view's render caches of the frame's surface.
  SurfaceModel? _cached;
  ChunkPictureCache? _cache;
  InkTileCache? _tiles;

  /// The contact writing in the box, and the ink it made (surface units).
  int? _pointer;
  bool _inking = false;
  Rect? _ink;
  final Set<int> _ignored = {};

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

  void _onLayout(Size size) {
    if (size == _zoom.box) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _zoom.setBox(size);
    });
  }

  /// The box writes with the pen and highlighter and erases; the lasso,
  /// shapes, text and laser work on the page.
  bool _accepts(PointerDownEvent e) {
    final input = _zoom.input;
    if (input == null) return false;
    final route = routeStylus(e.kind, e.buttons, input.penButtonAction);
    if (route == StylusRoute.lasso) return false;
    if (route == StylusRoute.eraser) return true;
    return switch (_tools.tool) {
      EditorTool.pen || EditorTool.highlighter || EditorTool.eraser => true,
      _ => false,
    };
  }

  bool _inks(PointerDownEvent e) =>
      _tools.tool != EditorTool.eraser &&
      routeStylus(e.kind, e.buttons, _zoom.input!.penButtonAction) == StylusRoute.tool;

  void _down(PointerDownEvent e) {
    if (!_accepts(e)) {
      _ignored.add(e.pointer);
      return;
    }
    // Where the box lies on the screen now (the platform's low-latency ink
    // draws in screen pixels).
    _zoom.boxOrigin = e.position - e.localPosition;
    final first = _pointer == null;
    if (first || isStylusKind(e.kind)) {
      _pointer = e.pointer;
      _inking = _inks(e);
      _ink = null;
      _zoom.penDown();
    }
    _zoom.input!.handleDown(e);
    _note(e);
  }

  void _move(PointerMoveEvent e) {
    if (_ignored.contains(e.pointer)) return;
    _zoom.input?.handleMove(e);
    _note(e);
  }

  void _note(PointerEvent e) {
    if (e.pointer != _pointer || !_inking) return;
    final at = _zoom.view.toWorld(e.localPosition);
    final dot = Rect.fromCenter(center: at, width: 0, height: 0);
    _ink = _ink?.expandToInclude(dot) ?? dot;
  }

  void _up(PointerUpEvent e) {
    if (_ignored.remove(e.pointer)) return;
    final input = _zoom.input;
    if (input == null) return;
    // A finger that turned into a pan or pinch wrote nothing.
    final navigated = input.navigates(e.pointer);
    input.handleUp(e);
    if (e.pointer != _pointer) return;
    _pointer = null;
    _zoom.penUp(_inking && !navigated ? _ink : null);
  }

  void _cancel(PointerCancelEvent e) {
    if (_ignored.remove(e.pointer)) return;
    _zoom.input?.handleCancel(e);
    if (e.pointer != _pointer) return;
    _pointer = null;
    _zoom.penUp(null);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    _zoom.reducedMotion = Motion.reduced(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Surfaces.chrome(scheme),
        border: Border(top: Surfaces.chromeEdge(scheme)),
      ),
      child: Padding(
        padding: widget.padding.copyWith(top: Hairline.width),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  _onLayout(constraints.biggest);
                  return ClipRect(child: _paper(context));
                },
              ),
            ),
            _rail(scheme),
          ],
        ),
      ),
    );
  }

  Widget _paper(BuildContext context) {
    final session = widget.session;
    final host = _zoom.host;
    return MouseRegion(
      cursor: SystemMouseCursors.precise,
      onExit: (_) => _zoom.input?.handleExit(),
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: _down,
        onPointerMove: _move,
        onPointerUp: _up,
        onPointerCancel: _cancel,
        onPointerHover: (e) => _zoom.input?.handleHover(e),
        onPointerSignal: (e) {
          final input = _zoom.input;
          if (input == null) return;
          GestureBinding.instance.pointerSignalResolver.register(e, input.handleSignal);
        },
        onPointerPanZoomStart: (e) => _zoom.input?.handlePanZoomStart(e),
        onPointerPanZoomUpdate: (e) => _zoom.input?.handlePanZoomUpdate(e),
        onPointerPanZoomEnd: (e) => _zoom.input?.handlePanZoomEnd(e),
        child: ListenableBuilder(
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
                  CustomPaint(
                    painter: ZoneBandPainter(
                      start: view.toScreen(Offset(zone, 0)).dx,
                      paper: _paperColour(frame.surfaceId),
                    ),
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
              ],
            );
          },
        ),
      ),
    );
  }

  PaperColor _paperColour(String surfaceId) {
    final doc = widget.session.doc;
    if (doc == null) return widget.session.notebook.paperColor;
    final page = doc.pages.where((p) => p.id == surfaceId).firstOrNull;
    return page?.paperColor ?? widget.session.notebook.paperColor;
  }

  Widget _rail(ColorScheme scheme) => DecoratedBox(
    decoration: BoxDecoration(border: Border(left: Surfaces.chromeEdge(scheme))),
    child: Padding(
      padding: const EdgeInsets.symmetric(horizontal: Gaps.xs, vertical: Gaps.xs),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          BarButton(
            icon: Symbols.close_sharp,
            tooltip: 'Close zoom window',
            onPressed: _zoom.close,
          ),
          BarButton(
            icon: Symbols.keyboard_return_sharp,
            tooltip: 'Next line',
            onPressed: _zoom.newLine,
          ),
        ],
      ),
    ),
  );
}
