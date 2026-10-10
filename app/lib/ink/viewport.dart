import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';

/// Maps between world coordinates (where ink lives) and screen coordinates:
/// `screen = world * scale + offset`.
///
/// When [contentBounds] is set (a page), panning and zooming are constrained
/// so the content cannot be lost off-screen.
class ViewportController extends ChangeNotifier {
  ViewportController({this.minScale = 0.05, this.maxScale = 16, this._contentBounds});

  final double minScale;
  final double maxScale;

  Rect? _contentBounds;

  /// Bounded content (a page), or null for an infinite canvas.
  Rect? get contentBounds => _contentBounds;
  set contentBounds(Rect? value) {
    if (value == _contentBounds) return;
    _contentBounds = value;
    _constrain();
    notifyListeners();
  }

  double _scale = 1;
  Offset _offset = Offset.zero;
  Size _size = Size.zero;

  double get scale => _scale;
  Offset get offset => _offset;
  Size get size => _size;

  /// The world rectangle currently visible on screen.
  Rect get visibleWorld => visibleWorldFor(_size);

  Rect visibleWorldFor(Size size) =>
      Rect.fromPoints(toWorld(Offset.zero), toWorld(Offset(size.width, size.height)));

  Offset toWorld(Offset screen) => (screen - _offset) / _scale;

  Offset toScreen(Offset world) => world * _scale + _offset;

  /// Updates the size of the viewport widget.
  void setSize(Size size) {
    if (size == _size) return;
    _size = size;
    _constrain();
    notifyListeners();
  }

  void panBy(Offset screenDelta) {
    if (screenDelta == Offset.zero) return;
    _offset += screenDelta;
    _constrain();
    notifyListeners();
  }

  /// Zooms by [factor] keeping the world point under [focal] fixed.
  void zoomAt(Offset focal, double factor) {
    if (!factor.isFinite || factor <= 0) return; // Bad device data.
    final newScale = (_scale * factor).clamp(minScale, maxScale);
    if (newScale == _scale) return;
    final world = toWorld(focal);
    _scale = newScale;
    _offset = focal - world * _scale;
    _constrain();
    notifyListeners();
  }

  /// Fits the content's width to the viewport, aligned to the top.
  void fitWidth({double padding = 24}) {
    final content = contentBounds;
    if (content == null || _size.isEmpty) return;
    _scale = ((_size.width - 2 * padding) / content.width).clamp(minScale, maxScale);
    _offset = Offset(
      (_size.width - content.width * _scale) / 2 - content.left * _scale,
      padding - content.top * _scale,
    );
    _constrain();
    notifyListeners();
  }

  /// Keeps bounded content reachable: centred along an axis when it fits,
  /// otherwise never scrolled further than [_overscroll] past its edges.
  void _constrain() {
    final content = contentBounds;
    if (content == null || _size.isEmpty) return;
    _offset = Offset(
      _constrainAxis(_offset.dx, content.left, content.right, _size.width),
      _constrainAxis(_offset.dy, content.top, content.bottom, _size.height),
    );
  }

  static const double _overscroll = 48;

  double _constrainAxis(double offset, double start, double end, double viewport) {
    final extent = (end - start) * _scale;
    if (extent <= viewport - 2 * _overscroll) {
      return (viewport - extent) / 2 - start * _scale; // centre
    }
    final maxOffset = _overscroll - start * _scale;
    final minOffset = viewport - _overscroll - end * _scale;
    return math.min(maxOffset, math.max(minOffset, offset));
  }
}
