import 'dart:developer' as developer;

import 'package:flutter/gestures.dart';

import '../../core/clock.dart';
import '../../domain/stroke.dart';
import '../lab/perf_probe.dart';
import '../render/live_stroke.dart';
import '../render/stroke_renderer.dart';
import '../surface_model.dart';
import '../tool_settings.dart';
import '../tools/content_tools.dart';
import '../tools/pointer_tool.dart';
import '../undo_history.dart';
import '../viewport.dart';
import 'bounce_filter.dart';
import 'highlight_snap.dart';
import 'hold_to_straighten.dart';
import 'ink_events.dart';
import 'lift_speed.dart';
import 'live_ink.dart';
import 'mouse_smoother.dart';
import 'sample_source.dart';
import 'scribble_erase.dart';
import 'stroke_sampler.dart';
import 'stylus_buttons.dart';

part 'ink_drawing_commit.dart';

/// The drawing contact of `InkInputController`: one pointer at a time that
/// inks, erases or drives a pointer tool from [content].
///
/// Ink goes pen-down → points (a mouse's whole-pixel steps levelled,
/// [MouseSmoother]; [StrokeSampler]: thinned, pressure normalised and
/// smoothed, end settled) → commit at pen-up, with stylus
/// bounces dropped, [HoldToStraighten] snapping a resting pen, a pen
/// scribble over ink erasing it ([ScribbleErase]) and highlights over
/// PDF text snapping to it ([highlightSnap]).
class InkDrawing {
  InkDrawing({
    required this.model,
    required this.viewport,
    required this.tools,
    required this.live,
    required this.clock,
    this.content,
    this.samples,
  }) : _straighten = HoldToStraighten(live);

  /// The surface strokes are committed to and erased from.
  SurfaceModel model;

  final ViewportController viewport;
  final ToolSettings tools;
  final LiveInk live;
  final Clock clock;
  final ContentTools? content;
  final SampleSource? samples;

  final HoldToStraighten _straighten;

  /// Snaps highlighter strokes over text to it.
  HighlightSnap? highlightSnap;

  /// Moments the editor may react to.
  final InkEvents events = InkEvents();

  /// The pointer tool handling the current drawing pointer, if any.
  PointerTool? _tool;

  /// Drops accidental stylus re-contacts right after a lift.
  final BounceFilter _bounces = BounceFilter();

  /// Thins and pressure-filters the ink's samples.
  late final StrokeSampler _sampler = StrokeSampler(viewport, _keep);

  /// Levels a mouse's whole-pixel steps before they are sampled.
  late final MouseSmoother _mouse = MouseSmoother(
    (at, ms) => _inkTo(at, 0.5, Duration(milliseconds: ms)),
  );
  bool _byMouse = false;

  /// Erases what a pen scribble crosses.
  late final ScribbleErase _scribble = ScribbleErase(viewport: viewport, tools: tools, live: live)
    ..onMissed = () => events.scribbleMissed?.call();

  /// The pen's speed at the lift, for an end taper that follows it.
  final LiftSpeed _liftSpeed = LiftSpeed();
  bool _endFollowsSpeed = false;

  /// The end taper (world units) of the stroke just committed.
  double _committedTaper = 0;

  int? _drawPointer;
  PointerDeviceKind? _drawKind;
  Duration _drawStartTime = Duration.zero;

  /// Wall time (epoch ms) the pen touched down: a stroke's `createdAt`, so
  /// audio replay shows it from when writing it began.
  int _drawStartedAt = 0;
  Offset _drawStartScreen = Offset.zero;
  double _drawTravel = 0;
  bool _erasing = false;
  bool _eraseStarted = false;

  /// Where a finger erasing has been while it may still turn out a resting
  /// palm or the start of a pinch: erased once it moves past the touch slop
  /// or lifts, dropped if the contact is cancelled.
  List<Offset>? _heldErase;
  Offset? _lastScreen;

  /// The drawing pointer, if a contact is in progress.
  int? get pointer => _drawPointer;

  /// The drawing pointer's device kind, if a contact is in progress.
  PointerDeviceKind? get kind => _drawKind;

  /// Whether the contact in progress is a stylus.
  bool get byStylus => isStylusKind(_drawKind);

  /// The contact's latest screen position.
  Offset? get lastScreen => _lastScreen;

  /// Starts a contact; [erase] erases (the eraser tool, a stylus button or
  /// end), [lasso] selects (the side button set to the lasso).
  void start(PointerDownEvent e, {required bool erase, bool lasso = false}) {
    // Zoomed far out the view may show stored rasters only: what is
    // erased, selected or written over must be in memory.
    model.loadVisible(view: viewport);
    _drawPointer = e.pointer;
    _drawKind = e.kind;
    _drawStartTime = e.timeStamp;
    _drawStartedAt = clock.nowMs();
    _drawStartScreen = e.localPosition;
    _drawTravel = 0;
    _sampler.reset();
    _liftSpeed.reset();
    _erasing = erase;
    _eraseStarted = false;
    _lastScreen = e.localPosition;
    final tool = erase ? null : content?.toolAt(tools.tool, e.localPosition, lasso: lasso);
    if (tool != null) {
      _tool = tool..down(_toolPointer(e));
    } else if (erase) {
      showEraser(e.localPosition);
      if (e.kind == PointerDeviceKind.touch) {
        _heldErase = [e.localPosition];
      } else {
        _eraseTo(e.localPosition);
      }
    } else {
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
    // After the live stroke began: a low-latency overlay can start with it.
    samples?.begin(e);
  }

  void move(PointerMoveEvent e) {
    final tool = _tool;
    if (tool != null) {
      _lastScreen = e.localPosition;
      tool.move(_toolPointer(e));
      return;
    }
    if (_erasing) {
      showEraser(e.localPosition);
      _eraseOrHold(e.localPosition);
      return;
    }
    if (_byMouse) return _mouse.add(e.localPosition, StrokeSampler.msOf(e.timeStamp));
    _addSamplesBefore(e);
    _inkTo(e.localPosition, StrokeSampler.pressureOf(e), e.timeStamp, synthesized: e.synthesized);
  }

  /// Ends the contact at [e] (the pen lifted).
  void up(PointerUpEvent e) {
    if (_inking) _addSamplesBefore(e);
    finish(liftTime: e.timeStamp);
  }

  /// Whether the drawing pointer is making ink (not erasing or a tool).
  bool get _inking => _drawPointer != null && _tool == null && !_erasing;

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

  /// Ends the current contact. [liftTime] is the pen-up timestamp, when known.
  void finish({Duration? liftTime}) {
    final tool = _tool;
    if (tool != null) {
      _tool = null;
      tool.up();
    } else if (_erasing) {
      _releaseErase();
      showEraser(_drawKind == PointerDeviceKind.touch ? null : _lastScreen);
    } else {
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
      if (points.isNotEmpty && !_isBounce(liftTime) && !_scribble.erase(model, snapped: snapped)) {
        _commit(points, liftTime, snapped: snapped, shape: shape);
      }
      _recordLift(liftTime);
    }
    _reset();
  }

  /// Abandons the current contact without committing it.
  void cancel() {
    final tool = _tool;
    _tool = null;
    if (tool != null) {
      tool.cancel();
    } else if (_drawPointer != null && !_erasing) {
      live.finish();
    }
    showEraser(null);
    _reset();
  }

  void _reset() {
    _straighten.end();
    _scribble.end();
    samples?.end(taperEnd: _committedTaper);
    _committedTaper = 0;
    _drawPointer = null;
    _drawKind = null;
    _byMouse = false;
    _erasing = false;
    _heldErase = null;
    _lastScreen = null;
  }

  // ---------------------------------------------------------------------------
  // Erasing

  /// Erases to [screen], or holds it while a finger may not be erasing.
  void _eraseOrHold(Offset screen) {
    final held = _heldErase;
    if (held == null) return _eraseTo(screen);
    held.add(screen);
    _lastScreen = screen;
    if ((screen - _drawStartScreen).distance > kTouchSlop) _releaseErase();
  }

  /// Erases along the held finger path: it is erasing after all.
  void _releaseErase() {
    final held = _heldErase;
    if (held == null) return;
    _heldErase = null;
    _lastScreen = held.first;
    held.forEach(_eraseTo);
  }

  void _eraseTo(Offset screen) {
    final from = viewport.toWorld(_lastScreen ?? screen);
    final to = viewport.toWorld(screen);
    // Hits within one drag merge into a single undo step — but only after
    // the first hit, so we never merge into an unrelated earlier edit.
    final erased = model.eraseAlong(
      from,
      to,
      tools.eraserRadius / viewport.scale,
      continueEdit: _eraseStarted,
      mode: tools.eraser.mode,
      highlighterOnly: tools.eraser.highlighterOnly,
    );
    _eraseStarted = _eraseStarted || erased;
    _lastScreen = screen;
  }

  /// Shows the eraser outline at [screen], or hides it.
  void showEraser(Offset? screen) {
    live.showEraser(
      screen == null ? null : viewport.toWorld(screen),
      tools.eraserRadius / viewport.scale,
    );
  }

  ToolPointer _toolPointer(PointerEvent e) => ToolPointer(
    screen: e.localPosition,
    world: viewport.toWorld(e.localPosition),
    pressure: StrokeSampler.pressureOf(e),
  );
}
