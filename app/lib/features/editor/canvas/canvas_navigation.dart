import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../../data/stroke_reader.dart';
import '../../../ink/navigation/kinetic_pan.dart';
import '../../../ink/navigation/viewport_animator.dart';
import '../../../ink/viewport.dart';

/// Navigation of an infinite canvas: inertial panning, animated zoom
/// steps, "fit content", "back to the origin", jumps from the minimap, and
/// whether the minimap is shown.
class CanvasNavigation extends ChangeNotifier {
  CanvasNavigation({
    required this.viewport,
    required this.reader,
    required this.surfaceId,
    this._showMinimap = false,
    this.onMinimapChanged,
  });

  final ViewportController viewport;
  final StrokeReader reader;
  final String surfaceId;

  /// Persists the minimap choice.
  final ValueChanged<bool>? onMinimapChanged;

  late final ViewportAnimator animator = ViewportAnimator(viewport);
  late final KineticPan kinetic = KineticPan(animator);

  /// Zoom levels the zoom-in / zoom-out actions step through.
  static const List<double> zoomSteps = [
    0.05, 0.1, 0.25, 0.5, 0.75, 1, 1.5, 2, 3, 4, 6, 8, 12, 16, //
  ];

  /// "Fit content" never magnifies beyond this (a lone word would fill
  /// the screen otherwise).
  static const double fitScaleCap = 2;

  bool _showMinimap;
  bool get showMinimap => _showMinimap;

  void toggleMinimap() {
    _showMinimap = !_showMinimap;
    onMinimapChanged?.call(_showMinimap);
    notifyListeners();
  }

  /// Zooms in to the next step, about [focal] (default: the centre).
  void zoomIn({Offset? focal}) => animator.zoomTo(
    zoomSteps.firstWhere((s) => s > viewport.scale * 1.01, orElse: () => zoomSteps.last),
    focal: focal,
  );

  /// Zooms out to the previous step, about [focal] (default: the centre).
  void zoomOut({Offset? focal}) => animator.zoomTo(
    zoomSteps.lastWhere((s) => s < viewport.scale / 1.01, orElse: () => zoomSteps.first),
    focal: focal,
  );

  /// Animates to [scale] (1 = 100 %) about the centre of the view.
  void zoomTo(double scale) => animator.zoomTo(scale);

  /// Shows all the ink on the canvas, or the origin if there is none.
  Future<void> fitContent() async {
    final bounds = await reader.contentBounds(surfaceId);
    if (bounds == null) return goToOrigin();
    animator.fit(bounds, scaleCap: fitScaleCap);
  }

  /// Back to where a new canvas starts: the origin at the top left, 100 %.
  void goToOrigin() => animator.animateTo(scale: 1, offset: Offset.zero);

  /// Glides so that [world] is centred.
  void glideTo(Offset world) => animator.centreOn(world);

  /// Centres [world] immediately (dragging on the minimap).
  void jumpTo(Offset world) {
    animator.stop();
    viewport.setView(
      scale: viewport.scale,
      offset: viewport.size.center(Offset.zero) - world * viewport.scale,
    );
  }

  @override
  void dispose() {
    animator.dispose();
    super.dispose();
  }
}
