import 'package:flutter/material.dart';

import '../../../domain/paper.dart';
import '../../../ink/ink_surface.dart';
import '../../../ink/input/ink_input_controller.dart';
import '../../../ink/input/live_ink.dart';
import '../../../ink/surface_model.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/floating_panel.dart';
import 'canvas_minimap.dart';
import 'canvas_navigation.dart';
import 'zoom_indicator.dart';

/// An infinite canvas with its navigation overlays: the zoom indicator
/// (shown while zooming), the minimap (optional) and buttons to fit the
/// content and toggle the minimap.
class CanvasView extends StatelessWidget {
  const CanvasView({
    super.key,
    required this.model,
    required this.navigation,
    required this.input,
    required this.live,
    required this.paper,
    required this.paperColor,
    this.topInset = 72,
    this.bottomInset = 12,
  });

  final SurfaceModel model;
  final CanvasNavigation navigation;
  final InkInputController input;
  final LiveInk live;
  final PaperStyle paper;
  final PaperColor paperColor;

  /// Space kept free for the editor's top bar.
  final double topInset;

  /// Space kept free below the overlays (e.g. a bottom toolbar).
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final nav = navigation;
    return Stack(
      children: [
        Positioned.fill(
          child: InkSurface(
            model: model,
            viewport: nav.viewport,
            input: input,
            live: live,
            paper: paper,
            paperColor: paperColor,
          ),
        ),
        SafeArea(
          child: Padding(
            padding: EdgeInsets.fromLTRB(Gaps.md, topInset, Gaps.md, bottomInset),
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: ZoomIndicator(
                    viewport: nav.viewport,
                    onZoomTo: nav.zoomTo,
                    onFit: nav.fitContent,
                  ),
                ),
                Align(
                  alignment: Alignment.bottomRight,
                  child: ListenableBuilder(
                    listenable: nav,
                    builder: (context, _) => Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        if (nav.showMinimap) ...[
                          CanvasMinimap(navigation: nav, model: model, paperColor: paperColor),
                          const SizedBox(height: Gaps.sm),
                        ],
                        _Buttons(navigation: nav),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _Buttons extends StatelessWidget {
  const _Buttons({required this.navigation});

  final CanvasNavigation navigation;

  @override
  Widget build(BuildContext context) {
    final nav = navigation;
    return FloatingPanel(
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Fit content (Shift+1)',
            onPressed: nav.fitContent,
            icon: const Icon(Icons.fit_screen_outlined),
          ),
          IconButton(
            tooltip: nav.showMinimap ? 'Hide overview' : 'Show overview',
            isSelected: nav.showMinimap,
            onPressed: nav.toggleMinimap,
            icon: const Icon(Icons.map_outlined),
            selectedIcon: const Icon(Icons.map_rounded),
          ),
        ],
      ),
    );
  }
}
