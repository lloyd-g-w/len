import 'dart:ui';

import '../../../ink/viewport.dart';

/// The zoom window's box as a viewport onto the frame's surface, for the
/// ink engine (`screen = surface * scale + offset`, in box pixels). The
/// window sets it ([show]); a pan or pinch in the box (fingers that
/// navigate) moves or resizes the frame instead.
class ZoomBoxViewport extends ViewportController {
  ZoomBoxViewport({required this.onPan, required this.onZoom})
    : super(minScale: 1e-3, maxScale: 1e3);

  /// Fingers dragged the box's content by a screen delta.
  final void Function(Offset screenDelta) onPan;

  /// Fingers pinched the box to [scale] about [focal] (box pixels).
  final void Function(Offset focal, double scale) onZoom;

  /// Shows the frame: [scale] box pixels per unit, [offset], a [size] box.
  void show({required double scale, required Offset offset, required Size size}) {
    super.setSize(size);
    super.setView(scale: scale, offset: offset);
  }

  @override
  void setSize(Size size) {} // The window lays the box out.

  @override
  void panBy(Offset screenDelta) {
    if (screenDelta != Offset.zero && screenDelta.isFinite) onPan(screenDelta);
  }

  @override
  void zoomAt(Offset focal, double factor) {
    if (factor.isFinite && factor > 0) onZoom(focal, scale * factor);
  }

  @override
  void stretchAt(Offset focal, double scale) {
    if (scale.isFinite && scale > 0) onZoom(focal, scale);
  }

  @override
  void fitWidth({double padding = 24}) {}
}
