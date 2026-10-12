import 'package:flutter/material.dart';

import '../../../domain/paper.dart';
import '../../../ink/ink_surface.dart';
import '../../../ink/input/ink_input_controller.dart';
import '../../../ink/input/live_ink.dart';
import '../../../ink/surface_model.dart';
import '../../../ui/app_theme.dart';
import '../../../ui/floating_panel.dart';
import 'canvas_navigation.dart';
import 'zoom_indicator.dart';

/// An infinite canvas with its navigation overlays: the zoom indicator
/// (shown while zooming) and a button to fit the content.
class CanvasView extends StatelessWidget {
  const CanvasView({
    super.key,
    required this.model,
    required this.navigation,
    required this.input,
    required this.live,
    required this.paper,
    required this.paperColor,
    this.insets = EdgeInsets.zero,
  });

  final SurfaceModel model;
  final CanvasNavigation navigation;
  final InkInputController input;
  final LiveInk live;
  final PaperStyle paper;
  final PaperColor paperColor;

  /// Screen edges covered by the editor's chrome (top bar, toolbar, safe
  /// areas); the overlays keep clear of them.
  final EdgeInsets insets;

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
          top: false,
          bottom: false,
          child: Padding(
            padding: insets + const EdgeInsets.fromLTRB(Gaps.md, Gaps.sm, Gaps.md, Gaps.md),
            child: Stack(
              children: [
                Align(
                  alignment: Alignment.topCenter,
                  child: ZoomIndicator(
                    viewport: nav.viewport,
                    onZoomTo: nav.zoomTo,
                    onFit: nav.fitContent,
                    quiet: () => nav.opening,
                  ),
                ),
                Align(
                  alignment: Alignment.bottomRight,
                  child: FloatingPanel(
                    child: IconButton(
                      tooltip: 'Fit content (Shift+1)',
                      onPressed: nav.fitContent,
                      icon: const Icon(Icons.fit_screen_outlined),
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
