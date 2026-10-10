import 'package:flutter/gestures.dart';

import '../viewport.dart';
import 'viewport_animator.dart';

/// Inertial panning: follows how the view moves during a navigation
/// gesture (finger pan, trackpad, middle-button drag) and, when the gesture
/// ends while still moving, lets the view glide on and slow down.
///
/// The input controller only reports the gesture's life cycle ([begin],
/// [track], [release]); the velocity is measured on the viewport itself, so
/// it is the same however the pan was produced. Pinching resets the
/// measurement: only a pan, not a zoom, carries on.
class KineticPan {
  KineticPan(this.animator, {this.enabled});

  final ViewportAnimator animator;

  /// Whether gliding is currently wanted (e.g. not in single-page flow).
  final bool Function()? enabled;

  /// A release this long after the last movement means the finger had
  /// stopped: no glide.
  static const Duration stillAfter = Duration(milliseconds: 60);

  ViewportController get _viewport => animator.viewport;

  VelocityTracker? _tracker;
  double _scale = 0;
  Duration _last = Duration.zero;

  /// A pointer landed: any glide stops, measuring starts afresh.
  void begin() {
    animator.stop();
    _tracker = null;
  }

  /// The view was just moved by the gesture at [time] (event timestamp).
  void track(Duration time) {
    final scale = _viewport.scale;
    if (_tracker == null || scale != _scale) {
      _tracker = VelocityTracker.withKind(PointerDeviceKind.touch);
      _scale = scale;
    }
    _tracker!.addPosition(time, _viewport.offset);
    _last = time;
  }

  /// The gesture ended at [time]; glide if it was still moving.
  void release(Duration time) {
    final tracker = _tracker;
    _tracker = null;
    if (tracker == null || time - _last > stillAfter) return;
    if (!(enabled?.call() ?? true)) return;
    final velocity = tracker.getVelocity();
    if (velocity.pixelsPerSecond.distance < kMinFlingVelocity) return;
    animator.fling(velocity.clampMagnitude(0, kMaxFlingVelocity).pixelsPerSecond);
  }
}
