part of 'ink_drawing.dart';

/// The ink path of a contact: the live stroke begun under the nib, the
/// samples it is extended by, and what the lift leaves.
extension _Inking on InkDrawing {
  /// Begins the live stroke at [e] with the active ink.
  void _beginInk(PointerDownEvent e) {
    final ink = tools.activeInk;
    final config = tools.configOf(ink);
    // Ink shows from the first sample, under the nib. The outline smooths
    // at the zoom it is written at (`StrokeStyle.unit`), known now.
    live.begin(
      tool: ink,
      color: config.color,
      width: config.width,
      style: tools.styleFor(ink).copyWith(unit: 1 / viewport.scale),
    );
    _endFollowsSpeed = config.ends.endFollowsSpeed;
    live.add(_sampler.first(e));
    _inkBegan = true;
    events.inkBegan?.call(model.surfaceId);
    _byMouse = e.kind == PointerDeviceKind.mouse;
    if (_byMouse) {
      final ms = StrokeSampler.msOf(e.timeStamp);
      _mouse.begin(e.localPosition, ms, width: config.width * viewport.scale);
    }
    _liftSpeed.add(e.localPosition, StrokeSampler.msOf(e.timeStamp));
    _scribble.begin(model, e.localPosition, StrokeSampler.msOf(e.timeStamp));
    _straighten.begin(
      e.localPosition,
      enabled: tools.holdToStraighten,
      scale: viewport.scale,
      straight: config.straight,
      timeMs: StrokeSampler.msOf(e.timeStamp),
    );
  }

  /// Adds the samples the platform saw since the previous event of [e]'s
  /// contact (dense stylus input), in order, before [e] itself.
  void _addSamplesBefore(PointerEvent e) {
    final extra = samples?.between(e);
    if (extra == null) return;
    for (final s in extra) {
      _inkTo(s.localPosition, StrokeSampler.normalisedPressure(e, s.pressure), s.timeStamp);
    }
  }

  /// Extends the live stroke to [screen] (unless it is too close to the
  /// previous point, or "hold to straighten" has taken over).
  void _inkTo(Offset screen, double pressure, Duration time, {bool synthesized = false}) {
    final ms = StrokeSampler.msOf(time);
    if (_sampler.add(_lastScreen!, screen, pressure, ms, synthesized: synthesized)) {
      _lastScreen = screen;
    }
  }

  /// A point [_sampler] kept, at [at] after [from].
  void _keep(Offset from, Offset at, StrokePoint point, int timeMs) {
    _drawTravel += (at - from).distance;
    _liftSpeed.add(at, timeMs);
    _scribble.add(at, timeMs);
    if (_straighten.move(at, point, timeMs: timeMs)) return;
    live.add(point);
  }

  /// Ends the ink at the lift ([liftTime], when known) and commits it,
  /// unless it was a bounce, a tap dismissing a selection or a scribble
  /// that erased (only if [mayErase]).
  void _finishInk(Duration? liftTime, {required bool mayErase}) {
    if (_byMouse) _mouse.finish(); // The ink catches up with the mouse.
    // A snapped shape's end follows no speed (the pen rested to snap it),
    // and it is no scribble.
    final snapped = live.straightened;
    final shape = live.shape;
    if (snapped) _endFollowsSpeed = false;
    // A shape's points are its outline, as shown.
    final finished = live.finish();
    final points = shape != null ? finished : StrokeSampler.settleEnd(finished);
    // A bounce was shown while it touched (under the nib, where the pen
    // just lifted, for less than `BounceFilter.maxContact`) and goes now.
    final dismissTap = (_dropReach ?? double.infinity) < kTouchSlop;
    if (points.isNotEmpty &&
        !dismissTap &&
        !_isBounce(liftTime) &&
        !(mayErase && _scribble.erase(model, snapped: snapped))) {
      _commit(points, liftTime, snapped: snapped, shape: shape);
      _inked = true;
    }
    _recordLift(liftTime);
  }
}
