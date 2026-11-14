part of 'canvas_minimap.dart';

/// The minimap's panel: the map over its buttons (with a button above it
/// to fit it again while it is zoomed or panned), or folded into one
/// button; its colours from the paper.
extension _MinimapLayout on _CanvasMinimapState {
  Widget _folded() => FloatingPanel(
    padding: EdgeInsets.zero,
    child: MinimapFoldedButton(onUnfold: () => _setCollapsed(false)),
  );

  Widget _unfolded(BuildContext context) {
    // A window onto the paper: the panel's hairline and shadow, no rim.
    final panel = FloatingPanel(
      padding: EdgeInsets.zero,
      child: SizedBox(
        width: widget.size.width,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _MinimapGestures(
              state: this,
              // It repaints with every frame of a pan: alone, not the editor.
              child: RepaintBoundary(
                child: CustomPaint(
                  size: widget.size,
                  painter: MinimapPainter(
                    content: _sketch.blocks,
                    raster: _sketch.overBudget ? null : _raster,
                    frame: () => _frame,
                    view: () => _nav.visibleArea,
                    colors: _colors(Theme.of(context).colorScheme),
                    blocks: _blocks,
                    handles: true,
                    repaint: Listenable.merge([_nav.viewport, _glide, _moved, _painted]),
                  ),
                ),
              ),
            ),
            MinimapControls(
              onZoomOut: () => _nav.zoomStep(-1),
              onZoomIn: () => _nav.zoomStep(1),
              onFit: () => unawaited(_nav.fitContent()),
              onFold: () => _setCollapsed(true),
            ),
          ],
        ),
      ),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        // Above the map while it is zoomed or panned: fit it again.
        ChromeFade(
          visible: _custom != null,
          edge: const Offset(0, 1),
          child: FloatingPanel(
            radius: Radii.pill,
            padding: EdgeInsets.zero,
            child: BarButton(
              icon: Symbols.fit_screen_rounded,
              tooltip: CanvasMinimap.fitLabel,
              onPressed: _custom == null ? null : _fitMap,
            ),
          ),
        ),
        const SizedBox(height: Gaps.xs),
        panel,
      ],
    );
  }

  MinimapColors _colors(ColorScheme scheme) {
    final paper = widget.paperColor;
    // The frame sits on the paper: the accent for the paper's brightness.
    final view = paper.isDark == (scheme.brightness == Brightness.dark)
        ? scheme.primary
        : scheme.inversePrimary;
    // Dimming outside the view: a touch of the ink on light paper, a
    // deeper shade on dark paper (lightening it would read as focus).
    final veil = paper.isDark
        ? Surfaces.scrim(Brightness.light)
        : paper.text.withValues(alpha: paper.text.a * 0.1);
    return MinimapColors(paper: paper.paper, ink: paper.text, view: view, veil: veil);
  }
}
