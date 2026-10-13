import 'dart:math' as math;

import 'package:flutter/gestures.dart';

import '../viewport.dart';
import 'viewport_animator.dart';

/// What happens when a navigation gesture (finger pan or pinch, trackpad,
/// middle-button drag) lets go: [settle] may snap the view (e.g. to the
/// page fit), a zoom stretched past its limits springs back, and a pan
/// still moving glides on and slows down.
///
/// The input controller only reports the gesture's life cycle ([begin],
/// [track], [release]); the velocity is measured on the viewport itself, so
/// it is the same however the pan was produced. Zooming resets the
/// measurement: only a pan, not a zoom, carries on.
class KineticPan {
  KineticPan(this.animator, {this.settle});

  final ViewportAnimator animator;

  /// Called when a gesture that moved the view ends, about its last
  /// [focal] point; `zoomed` tells whether it pinched. Returns true when it
  /// animates the view somewhere (a snap), which replaces the glide.
  final bool Function(Offset focal, {required bool zoomed})? settle;

  /// A release this long after the last movement means the finger had
  /// stopped: no glide.
  static const Duration stillAfter = Duration(milliseconds: 60);

  ViewportController get _viewport => animator.viewport;

  VelocityTracker? _tracker;
  bool _moved = false;
  double _scale = 0;
  Duration _last = Duration.zero;

  /// A pointer landed: any glide stops, measuring starts afresh.
  void begin() {
    animator.stop();
    _tracker = null;
    _moved = false;
  }

  /// The view was just moved by the gesture at [time] (event timestamp).
  void track(Duration time) {
    _moved = true;
    final scale = _viewport.scale;
    if (_tracker == null || scale != _scale) {
      _tracker = VelocityTracker.withKind(PointerDeviceKind.touch);
      _scale = scale;
    }
    _tracker!.addPosition(time, _viewport.offset);
    _last = time;
  }

  /// The gesture ended at [time] about [focal] (default: the middle of the
  /// view): settle, spring back, or glide if it was still moving.
  void release(Duration time, {Offset? focal, bool zoomed = false}) {
    final tracker = _tracker;
    final moved = _moved;
    _tracker = null;
    _moved = false;
    if (!moved) return; // A tap: nothing to finish.
    final at = focal ?? _viewport.size.center(Offset.zero);
    if (settle?.call(at, zoomed: zoomed) ?? false) return;
    if (_viewport.overZoomed) {
      final limit = math.min(_viewport.maxScale, math.max(_viewport.minScale, _viewport.scale));
      animator.zoomTo(limit, focal: at);
      return;
    }
    if (tracker == null || time - _last > stillAfter) return;
    final velocity = tracker.getVelocity();
    if (velocity.pixelsPerSecond.distance < kMinFlingVelocity) return;
    animator.fling(velocity.clampMagnitude(0, kMaxFlingVelocity).pixelsPerSecond);
  }
}
