import 'dart:math' as math;

import 'package:flutter/animation.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/scheduler.dart';

import '../viewport.dart';

/// Animates a [ViewportController]: inertial glides after a fling and
/// smooth zooms to a target view. Any new animation (or [stop], e.g. when
/// a finger lands) replaces the running one.
class ViewportAnimator {
  ViewportAnimator(this.viewport) {
    _ticker = Ticker(_tick, debugLabel: 'ViewportAnimator');
  }

  final ViewportController viewport;
  late final Ticker _ticker;

  /// Per-second velocity factor of a glide: it keeps `drag^t` of its speed
  /// after t seconds (≈ iOS scroll deceleration), so it travels v/2.
  static const double drag = 0.135;

  /// Glides end below this speed (logical pixels per second).
  static const double restSpeed = 12;

  /// Duration of animated zooms.
  static const Duration zoomDuration = Duration(milliseconds: 280);

  void Function(Duration elapsed)? _step;

  bool get isAnimating => _ticker.isActive;

  /// Whether the platform asks for reduced motion: zooms and travels then
  /// jump to their view (DESIGN §5). Glides after a fling stay: they follow
  /// the finger's own movement.
  static bool get reducedMotion =>
      SchedulerBinding.instance.platformDispatcher.accessibilityFeatures.disableAnimations;

  /// Glides on with [velocity] (screen pixels per second), slowing down.
  void fling(Offset velocity) {
    stop();
    final speed = velocity.distance;
    if (speed <= restSpeed) return;
    final direction = velocity / speed;
    final sim = FrictionSimulation(drag, 0, speed, tolerance: const Tolerance(velocity: restSpeed));
    var travelled = 0.0;
    _start((elapsed) {
      final t = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
      final distance = sim.x(t);
      final step = direction * (distance - travelled);
      final before = viewport.offset;
      viewport.panBy(step);
      travelled = distance;
      // Done when slow enough, or blocked (a page edge). A step under a
      // pixel may not move a view that moves in whole device pixels.
      final blocked = step.distance > 1 && viewport.offset == before;
      if (sim.isDone(t) || blocked) stop();
    });
  }

  /// Animates to the view with [scale] and [offset]. The world point under
  /// [anchor] (screen) moves smoothly from where it is now to where it will
  /// be, while the scale changes geometrically — so zooming about a focal
  /// point keeps that point still.
  void animateTo({required double scale, required Offset offset, Offset? anchor}) {
    stop();
    final s0 = viewport.scale;
    final s1 = scale.clamp(viewport.minScale, viewport.maxScale);
    final a = anchor ?? viewport.size.center(Offset.zero);
    final w0 = viewport.toWorld(a);
    final w1 = (a - offset) / s1;
    if (reducedMotion || (s1 - s0).abs() < 1e-9 && (w1 - w0).distance * s0 < 0.5) {
      viewport.setView(scale: s1, offset: offset);
      return;
    }
    _start((elapsed) {
      final raw = elapsed.inMicroseconds / zoomDuration.inMicroseconds;
      final t = Curves.easeOutCubic.transform(math.min(1, raw));
      final s = s0 * math.pow(s1 / s0, t);
      final w = Offset.lerp(w0, w1, t)!;
      viewport.setView(scale: s, offset: a - w * s, stretched: true);
      if (raw >= 1) stop();
    });
  }

  /// Animates to [scale] keeping the point under [focal] (default: the
  /// centre of the view) still.
  void zoomTo(double scale, {Offset? focal}) {
    final f = focal ?? viewport.size.center(Offset.zero);
    final s1 = scale.clamp(viewport.minScale, viewport.maxScale);
    final world = viewport.toWorld(f);
    animateTo(scale: s1, offset: f - world * s1, anchor: f);
  }

  /// Animates to show [world] as large as fits (at most [scaleCap]).
  void fit(Rect world, {double padding = 48, double scaleCap = double.infinity}) {
    final view = viewport.viewFitting(world, padding: padding, scaleCap: scaleCap);
    animateTo(scale: view.scale, offset: view.offset);
  }

  void stop() {
    _step = null;
    if (_ticker.isActive) _ticker.stop();
  }

  void _start(void Function(Duration elapsed) step) {
    _step = step;
    _ticker.start();
  }

  void _tick(Duration elapsed) => _step?.call(elapsed);

  void dispose() => _ticker.dispose();
}
