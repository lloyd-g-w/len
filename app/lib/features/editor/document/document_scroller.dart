import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/animation.dart';
import 'package:flutter/scheduler.dart';

import '../../../ink/viewport.dart';

/// Smoothly animates a viewport to a target zoom and pan, e.g. scrolling
/// to a page. The point at the centre of the screen glides in a straight
/// line while the zoom eases, so the motion reads as one scroll. Jumps of
/// more than a few screens start close to the target, so a scroll from
/// page 1 to page 200 does not race through (and load) every page.
class DocumentScroller {
  DocumentScroller(this.viewport, {required this.apply});

  final ViewportController viewport;

  /// Applies a zoom and pan (e.g. `DocumentController.applyView`).
  final void Function(double scale, Offset offset) apply;

  static const Duration duration = Duration(milliseconds: 420);
  static const Curve curve = Curves.easeInOutCubic;

  /// Longest distance (in screen heights) actually animated.
  static const double maxScreens = 2;

  Ticker? _ticker;
  double _fromScale = 1, _toScale = 1;
  Offset _fromCentre = Offset.zero, _toCentre = Offset.zero;
  VoidCallback? _onDone;

  /// Animates to [scale] and [offset], then calls [onDone].
  void animateTo(double scale, Offset offset, {VoidCallback? onDone}) {
    stop();
    final size = viewport.size;
    final half = size.center(Offset.zero);
    _fromScale = viewport.scale;
    _toScale = scale;
    _fromCentre = viewport.toWorld(half);
    _toCentre = (half - offset) / scale;
    final screens = (_toCentre.dy - _fromCentre.dy).abs() * scale / math.max(1, size.height);
    if (screens > maxScreens) {
      final dir = (_toCentre.dy - _fromCentre.dy).sign;
      _fromCentre = Offset(_fromCentre.dx, _toCentre.dy - dir * maxScreens * size.height / scale);
      _fromScale = scale;
    }
    _onDone = onDone;
    _ticker = Ticker(_tick, debugLabel: 'DocumentScroller')..start();
  }

  void _tick(Duration elapsed) {
    final t = math.min(1.0, elapsed.inMicroseconds / duration.inMicroseconds);
    final e = curve.transform(t);
    final scale = lerpDouble(_fromScale, _toScale, e)!;
    final centre = Offset.lerp(_fromCentre, _toCentre, e)!;
    apply(scale, viewport.size.center(Offset.zero) - centre * scale);
    if (t >= 1) {
      final done = _onDone;
      stop();
      done?.call();
    }
  }

  /// Stops where it is (e.g. the user touched the screen).
  void stop() {
    _ticker?.dispose();
    _ticker = null;
    _onDone = null;
  }

  void dispose() => stop();
}
