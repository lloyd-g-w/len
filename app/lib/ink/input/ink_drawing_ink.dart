part of 'ink_drawing.dart';

/// The ink path of a contact: the live stroke begun under the nib, the
/// samples it is extended by, and what the lift leaves.
extension _Inking on InkDrawing {
  /// Begins the live stroke at [e] with the active ink.
  void _beginInk(PointerDownEvent e) {
    final ink = tools.activeInk;
    final config = tools.configOf(ink);
    final style = tools.styleFor(ink);
    // The stabiliser smooths the path on the screen, before it becomes
    // points, so the outline adds none (the stroke keeps 0): a stylus's or
    // finger's with [PenStabiliser], a mouse's with [MouseSmoother] (which
    // also levels its whole-pixel steps).
    _byMouse = e.kind == PointerDeviceKind.mouse;
    final stabiliser = _byMouse ? null : StabiliserParams.of(style.streamline);
    final ms = StrokeSampler.msOf(e.timeStamp);
    _stabiliser = stabiliser == null ? null : (PenStabiliser(stabiliser)..begin(e.localPosition));
    _stabiliserMs = ms;
    final down = viewport.toWorld(e.localPosition);
    _penPath
      ..clear()
      ..add((StrokePoint(down.dx, down.dy, 0.5), ms));
    // Ink shows from the first sample, under the nib. The outline smooths
    // at the zoom it is written at (`StrokeStyle.unit`), known now.
    // A mouse's ink trails it then, by the smoothing's reach: the
    // outline's own tip would settle when the mouse lifts.
    live.begin(
      tool: ink,
      color: config.color,
      width: config.width,
      style: style.copyWith(unit: 1 / viewport.scale, streamline: 0),
      trails: _byMouse && style.streamline > 0,
      stabiliser: stabiliser == null ? 0 : style.streamline,
    );
    _endFollowsSpeed = config.ends.endFollowsSpeed;
    live.add(_sampler.first(e));
    _inkBegan = true;
    events.inkBegan?.call(model.surfaceId);
    if (_byMouse) {
      _mouse.begin(e.localPosition, ms, stabiliser: style.streamline);
      // With the stabiliser off ink is under the nib: the live ink runs on
      // to the mouse (opaque ink only: a translucent tip drawn over the
      // stroke would show where they overlap).
      _mouseTip = style.streamline == 0 && style.opacity >= 1;
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

  /// The mouse moved to [e]'s position: its smoothed path extends the ink.
  void _mouseTo(PointerEvent e) {
    _mouse.add(e.localPosition, StrokeSampler.msOf(e.timeStamp));
    _showMouseTip();
  }

  /// Shows the rest of the mouse's path, up to the mouse, as the live
  /// ink's provisional tip ([LiveInk.tip]), unless hold to snap made the
  /// stroke a line or shape.
  void _showMouseTip() {
    if (!_mouseTip || live.straightened) return live.showTip(const []);
    live.showTip([for (final p in _mouse.tip()) viewport.toWorld(p)]);
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
  /// previous point, or "hold to straighten" has taken over): with the
  /// stabiliser on, to where it puts the ink.
  void _inkTo(Offset screen, double pressure, Duration time, {bool synthesized = false}) {
    final ms = StrokeSampler.msOf(time);
    var at = screen;
    if (_stabiliser case final s?) {
      _stabiliserMs = ms;
      final w = viewport.toWorld(screen);
      _penPath.add((StrokePoint(w.dx, w.dy, pressure), ms));
      at = s.add(screen);
      // A snapped line or shape follows the pen itself (the ink caught
      // up with it before the snap read the stroke).
      if (live.straightened) at = screen;
    }
    if (_sampler.add(_lastScreen!, at, pressure, ms, synthesized: synthesized)) {
      _lastScreen = at;
    }
  }

  /// With the stabiliser on, the ink catches up with the pen: at the lift,
  /// and before hold to snap reads the stroke.
  void _catchUp() {
    final s = _stabiliser;
    if (s == null || !inking) return;
    // The pressure stays the last sample's (as the overlay keeps it).
    for (final at in s.catchUp()) {
      if (_sampler.add(_lastScreen!, at, 0.5, _stabiliserMs, synthesized: true)) {
        _lastScreen = at;
      }
    }
    live.showString(null, null);
  }

  /// Shows the stabiliser's string from the ink to the pen (`LiveInk.string`),
  /// if it is on and the setting shows it.
  void _showString() {
    final s = _stabiliser;
    if (s == null || !tools.showStabiliserString || live.straightened) return;
    live.showString(viewport.toWorld(s.ink), viewport.toWorld(s.pen));
  }

  /// A point [_sampler] kept, at [at] after [from].
  void _keep(Offset from, Offset at, StrokePoint point, int timeMs) {
    _drawTravel += (at - from).distance;
    _liftSpeed.add(at, timeMs);
    // Scribbling is the pen's gesture: read where the pen is, not the ink
    // the stabiliser's string holds back (it would cut the turns).
    _scribble.add(_stabiliser?.pen ?? at, timeMs);
    // Hold to snap watches the pen rest, not the ink the string holds back.
    if (_straighten.move(_stabiliser?.pen ?? at, point, timeMs: timeMs)) return;
    live.add(point);
    _traceChunks();
  }

  /// Traces the chunks of the live stroke as it grows, so the stroke's
  /// are ready at pen-up whatever its length ([StrokeChunkTrace]).
  void _traceChunks() {
    if (_chunks == null || _chunksGeneration != live.generation) {
      _chunks = StrokeChunkTrace(live.width);
      _chunksGeneration = live.generation;
    }
    _chunks!.add(live.points);
  }

  /// Ends the ink at the lift ([liftTime], when known) and commits it,
  /// unless it was a bounce, a tap dismissing a selection or a scribble
  /// that erased (only if [mayErase]).
  void _finishInk(Duration? liftTime, {required bool mayErase}) {
    if (_byMouse) _mouse.finish(); // The ink catches up with the mouse.
    _catchUp(); // And with the pen.
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
