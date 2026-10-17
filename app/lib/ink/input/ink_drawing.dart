import 'dart:developer' as developer;
import 'dart:math' as math;

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
part 'ink_drawing_erase.dart';
part 'ink_drawing_ink.dart';

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
  }) : _straighten = HoldToStraighten(live) {
    // A resting mouse's ink catches up with it before the stroke is read.
    _straighten.beforeSnap = () {
      if (_byMouse) _mouse.flush();
    };
  }

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

  /// The stroke the contact just ended left, if any.
  Stroke? _committed;

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

  /// Whether this contact dropped a live selection (one kept under the pen
  /// after an insert, a paste or the side button's lasso): a tap that only
  /// meant to dismiss it leaves no dot. Null otherwise; else how far the
  /// contact has moved from where it touched down.
  double? _dropReach;

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

  /// Whether a finger's erasing is held back (it may be a palm).
  bool get holdsErase => _heldErase != null;

  /// The contact's latest screen position.
  Offset? get lastScreen => _lastScreen;

  /// Starts a contact; [erase] erases (the eraser tool, a stylus button or
  /// end), [lasso] selects (the side button set to the lasso).
  void start(PointerDownEvent e, {required bool erase, bool lasso = false}) {
    events.contact?.call();
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
    live.showPen(null); // The nib is down: its ink, not a preview.
    live.keepCursors(); // An eraser ring stays while it erases (the pen rests).
    final selection = content?.selection;
    final hadSelection = selection != null && !selection.isEmpty;
    final tool = erase ? null : content?.toolAt(tools.tool, e.localPosition, lasso: lasso);
    _dropReach = hadSelection && tool == null && !erase && selection.isEmpty ? 0 : null;
    if (tool != null) {
      _tool = tool..down(_toolPointer(e));
    } else if (erase) {
      _beginErase(e);
    } else {
      _beginInk(e);
    }
    // After the live stroke began: a low-latency overlay can start with it.
    samples?.begin(e);
  }

  void move(PointerMoveEvent e) {
    if (_dropReach case final reach?) {
      final d = (e.localPosition - _drawStartScreen).distance;
      if (d > reach) _dropReach = d;
    }
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
    if (inking) _addSamplesBefore(e);
    finish(liftTime: e.timeStamp);
  }

  /// Whether the drawing pointer is making ink (not erasing or a tool).
  bool get inking => _drawPointer != null && _tool == null && !_erasing;

  /// Whether the last contact that ended left a stroke (not erasing, a
  /// scribble that erased, a bounce or a tool).
  bool get inked => _inked;
  bool _inked = false;

  /// Ends a pen's ink contact the platform cancelled at [time]: the ink is
  /// kept as written, but never erases (a scribble already dimming what it
  /// would erase is dropped instead, as before: nothing goes without a
  /// lift). The cancel counts as the lift, so a bounce still goes.
  void keep(Duration time) {
    if (!inking || _scribble.previewing) return cancel();
    finish(liftTime: time, mayErase: false);
  }

  /// Ends the current contact. [liftTime] is the pen-up timestamp, when
  /// known; a scribble erases only if [mayErase].
  void finish({Duration? liftTime, bool mayErase = true}) {
    _inked = false;
    final tool = _tool;
    if (tool != null) {
      _tool = null;
      tool.up();
    } else if (_erasing) {
      _releaseErase();
      showEraser(_drawKind == PointerDeviceKind.touch ? null : _lastScreen);
      if (byStylus) live.expireCursorsSoon(); // The pen may leave unannounced.
    } else {
      _finishInk(liftTime, mayErase: mayErase);
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
    samples?.end(committed: _committed);
    _committed = null;
    _drawPointer = null;
    _drawKind = null;
    _byMouse = false;
    _erasing = false;
    _heldErase = null;
    _lastScreen = null;
    _dropReach = null;
  }

  /// Shows the eraser outline at [screen], or hides it.
  void showEraser(Offset? screen) {
    live.showEraser(
      screen == null ? null : viewport.toWorld(screen),
      tools.eraserRadius / viewport.scale,
    );
  }

  /// Shows the hovering pen's preview at [screen] (the active ink's colour
  /// and medium-pressure width, at most half opaque so it never reads as
  /// ink), or hides it.
  void showPen(Offset? screen) {
    if (screen == null) return live.showPen(null);
    final ink = tools.activeInk;
    final config = tools.configOf(ink);
    final color = StrokeRenderer.paintFor(config.color, tools.styleFor(ink)).color;
    live.showPen(
      viewport.toWorld(screen),
      radius: config.width / 2,
      color: color.withValues(alpha: math.min(color.a, previewOpacity)),
    );
  }

  /// The pen preview's opacity at most.
  static const double previewOpacity = 0.5;

  ToolPointer _toolPointer(PointerEvent e) => ToolPointer(
    screen: e.localPosition,
    world: viewport.toWorld(e.localPosition),
    pressure: StrokeSampler.pressureOf(e),
    kind: e.kind,
  );
}
