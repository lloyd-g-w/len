import 'dart:developer' as developer;
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import '../../core/clock.dart';
import '../../domain/preferences.dart';
import '../../domain/stroke.dart';
import '../lab/perf_probe.dart';
import '../navigation/kinetic_pan.dart';
import '../render/live_stroke.dart';
import '../render/stroke_renderer.dart';
import '../surface_model.dart';
import '../tool_settings.dart';
import '../tools/content_tools.dart';
import '../tools/pointer_tool.dart';
import '../viewport.dart';
import 'bounce_filter.dart';
import 'canvas_gestures.dart';
import 'hold_to_straighten.dart';
import 'live_ink.dart';
import 'point_spacing.dart';
import 'pressure_filter.dart';
import 'sample_source.dart';
import 'stylus_buttons.dart';

/// Turns raw pointer events into drawing, erasing and navigation.
///
/// Routing rules:
///  * **Stylus** always draws. The eraser end (inverted stylus) erases; a
///    barrel button held (S Pen side button) does [penButtonAction] (erase,
///    lasso or nothing). A stylus landing cancels a stroke a palm may have
///    started and stops any finger navigation.
///  * **Touch** is ignored while a stylus is down (it is almost certainly
///    the palm). Otherwise it navigates when palm rejection
///    ([ToolSettings.stylusOnly]) is on; if off, one finger draws and a
///    second finger turns the gesture into pan/zoom.
///  * **Mouse**: left button draws, middle/right drag pans, wheel scrolls,
///    Ctrl/⌘+wheel zooms.
///  * **Trackpad**: two-finger pan and pinch zoom.
///
/// Resting the pen at the end of a stroke snaps it to a line or shape (see
/// [HoldToStraighten]). The lasso, shape, text and laser tools receive the
/// drawing pointer through [content] instead of drawing ink. Every event is
/// also shown to [gestures] (multi-finger taps, long press, right click).
class InkInputController {
  InkInputController({
    required this._model,
    required this.viewport,
    required this.tools,
    required this.live,
    this.clock = const Clock(),
    this.onStylusDetected,
    this.content,
    this.kinetic,
    this.gestures,
    this.samples,
    PenButtonAction Function()? penButtonAction,
  }) : _straighten = HoldToStraighten(live),
       _penButtonAction = penButtonAction ?? (() => PenButtonAction.eraser);

  SurfaceModel _model;

  /// The surface being edited. Can be swapped (e.g. when turning pages);
  /// a stroke in progress is abandoned rather than committed to the wrong
  /// surface.
  SurfaceModel get model => _model;
  set model(SurfaceModel value) {
    if (identical(value, _model)) return;
    _cancelDraw();
    _model = value;
    content?.model = value;
  }

  final ViewportController viewport;
  final ToolSettings tools;
  final LiveInk live;
  final Clock clock;

  /// Called the first time a stylus is used.
  final void Function()? onStylusDetected;

  /// Inertial panning after navigation gestures (optional).
  final KineticPan? kinetic;

  final HoldToStraighten _straighten;

  /// Non-inking tools (lasso, shapes, text, laser), if the editor has them.
  final ContentTools? content;

  /// Canvas gestures recognised alongside input, if the editor wants them.
  final CanvasGestures? gestures;

  /// Stylus samples the platform reported between pointer events (Android
  /// batches several per frame; Flutter forwards only the newest), if any.
  final SampleSource? samples;

  final PenButtonAction Function() _penButtonAction;

  /// What the stylus side button currently does.
  PenButtonAction get penButtonAction => _penButtonAction();

  /// The pointer tool handling the current drawing pointer, if any.
  PointerTool? _tool;

  /// Points dropped since the last kept one (screen position, point).
  final List<(Offset, StrokePoint)> _dropped = [];

  /// Drops accidental stylus re-contacts right after a lift.
  final BounceFilter _bounces = BounceFilter();

  /// Smooths stylus pressure and suppresses spikes at pen-up.
  final PressureFilter _pressure = PressureFilter();

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
  Offset? _lastScreen;

  final Map<int, Offset> _navPointers = {};
  double _lastPanZoomScale = 1;
  bool _stylusSeen = false;

  // ---------------------------------------------------------------------------
  // Pointer lifecycle

  void handleDown(PointerDownEvent e) {
    kinetic?.begin();
    gestures?.down(e, navigates: tools.stylusOnly ?? false);
    switch (e.kind) {
      case PointerDeviceKind.stylus || PointerDeviceKind.invertedStylus:
        _stylusDown(e);
      case PointerDeviceKind.mouse:
        if (e.buttons & kPrimaryMouseButton != 0 && _drawPointer == null) {
          _startDraw(e, erase: tools.tool == EditorTool.eraser);
        } else {
          _navPointers[e.pointer] = e.localPosition;
        }
      case PointerDeviceKind.touch:
        _touchDown(e);
      case PointerDeviceKind.trackpad || PointerDeviceKind.unknown:
        break;
    }
  }

  void handleMove(PointerMoveEvent e) {
    gestures?.move(e);
    if (e.pointer == _drawPointer) {
      _continueDraw(e);
    } else if (_navPointers.containsKey(e.pointer)) {
      _navigate(e.pointer, e.localPosition);
      kinetic?.track(e.timeStamp);
    }
  }

  void handleUp(PointerUpEvent e) {
    if (e.pointer == _drawPointer) {
      if (_inking) _addSamplesBefore(e);
      _finishDraw(liftTime: e.timeStamp);
    }
    if (_navPointers.remove(e.pointer) != null && _navPointers.isEmpty) {
      kinetic?.release(e.timeStamp);
    }
    gestures?.up(e);
  }

  void handleCancel(PointerCancelEvent e) {
    if (e.pointer == _drawPointer) _cancelDraw();
    _navPointers.remove(e.pointer);
    gestures?.cancel(e);
  }

  /// Shows the eraser outline while hovering (mouse or hovering stylus).
  void handleHover(PointerHoverEvent e) {
    gestures?.hover(e);
    if (_drawPointer != null) return; // Don't fight the active pointer.
    _showEraser(_wantsErase(e) ? e.localPosition : null);
  }

  void handleExit() => _showEraser(null);

  // ---------------------------------------------------------------------------
  // Wheel / trackpad

  void handleSignal(PointerSignalEvent e) {
    switch (e) {
      case PointerScrollEvent():
        final keys = HardwareKeyboard.instance;
        if (keys.isControlPressed || keys.isMetaPressed) {
          viewport.zoomAt(e.localPosition, math.exp(-e.scrollDelta.dy / 400));
        } else if (keys.isShiftPressed && e.scrollDelta.dx == 0) {
          viewport.panBy(Offset(-e.scrollDelta.dy, 0));
        } else {
          viewport.panBy(-e.scrollDelta);
        }
      case PointerScaleEvent():
        viewport.zoomAt(e.localPosition, e.scale);
      default:
        break;
    }
  }

  void handlePanZoomStart(PointerPanZoomStartEvent e) {
    _lastPanZoomScale = 1;
    kinetic?.begin();
  }

  void handlePanZoomUpdate(PointerPanZoomUpdateEvent e) {
    viewport.panBy(e.localPanDelta);
    if (e.scale > 0 && e.scale != _lastPanZoomScale) {
      viewport.zoomAt(e.localPosition, e.scale / _lastPanZoomScale);
      _lastPanZoomScale = e.scale;
    }
    kinetic?.track(e.timeStamp);
  }

  void handlePanZoomEnd(PointerPanZoomEndEvent e) => kinetic?.release(e.timeStamp);

  // ---------------------------------------------------------------------------
  // Drawing

  void _stylusDown(PointerDownEvent e) {
    _noteStylus();
    if (_drawPointer != null) {
      if (_isStylus(_drawKind)) {
        // There is only one pen: its previous contact lost its up event.
        _finishDraw();
      } else {
        _cancelDraw(); // Probably a palm touched down first.
      }
    }
    // Fingers resting on the screen are the palm now; stop them panning.
    _navPointers.clear();
    final route = routeStylus(e.kind, e.buttons, penButtonAction);
    _startDraw(
      e,
      erase: route == StylusRoute.eraser || (route == StylusRoute.tool && _wantsErase(e)),
      lasso: route == StylusRoute.lasso,
    );
  }

  void _touchDown(PointerDownEvent e) {
    if (_isStylus(_drawKind)) return; // Palm while writing.
    // Android reports no hover exit for a stylus leaving range, so a stale
    // eraser cursor would linger; a finger is a good moment to clear it.
    _showEraser(null);
    final palmRejection = tools.stylusOnly ?? false;
    if (palmRejection) {
      _navPointers[e.pointer] = e.localPosition;
      return;
    }
    final drawing = _drawPointer;
    if (drawing == null && _navPointers.isEmpty) {
      _startDraw(e, erase: tools.tool == EditorTool.eraser);
      return;
    }
    if (drawing != null && _drawKind == PointerDeviceKind.touch) {
      // A second finger: the first one was the start of a pinch, not ink.
      final firstPosition = _lastScreen!;
      _cancelDraw();
      _navPointers[drawing] = firstPosition;
    }
    _navPointers[e.pointer] = e.localPosition;
  }

  void _startDraw(PointerDownEvent e, {required bool erase, bool lasso = false}) {
    _drawPointer = e.pointer;
    _drawKind = e.kind;
    _drawStartTime = e.timeStamp;
    _drawStartedAt = clock.nowMs();
    _drawStartScreen = e.localPosition;
    _drawTravel = 0;
    _pressure.reset();
    _erasing = erase;
    _eraseStarted = false;
    _lastScreen = e.localPosition;
    final tool = erase ? null : content?.toolAt(tools.tool, e.localPosition, lasso: lasso);
    if (tool != null) {
      _tool = tool..down(_toolPointer(e));
    } else if (erase) {
      _showEraser(e.localPosition);
      _eraseTo(e.localPosition);
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
      _dropped.clear();
      live.add(_pointOf(e));
      _straighten.begin(e.localPosition, enabled: tools.holdToStraighten, scale: viewport.scale);
    }
    // After the live stroke began: a low-latency overlay can start with it.
    samples?.begin(e);
  }

  void _continueDraw(PointerMoveEvent e) {
    final tool = _tool;
    if (tool != null) {
      _lastScreen = e.localPosition;
      tool.move(_toolPointer(e));
      return;
    }
    if (_erasing) {
      _showEraser(e.localPosition);
      _eraseTo(e.localPosition);
      return;
    }
    _addSamplesBefore(e);
    _inkTo(e.localPosition, _pressureOf(e), synthesized: e.synthesized);
  }

  /// Whether the drawing pointer is making ink (not erasing or a tool).
  bool get _inking => _drawPointer != null && _tool == null && !_erasing;

  /// Adds the samples the platform saw since the previous event of [e]'s
  /// contact (dense stylus input), in order, before [e] itself.
  void _addSamplesBefore(PointerEvent e) {
    final extra = samples?.between(e);
    if (extra == null) return;
    for (final s in extra) {
      _inkTo(s.localPosition, _normalisedPressure(e, s.pressure));
    }
  }

  /// Extends the live stroke to [screen] (unless it is too close to the
  /// previous point, or "hold to straighten" has taken over).
  void _inkTo(Offset screen, double pressure, {bool synthesized = false}) {
    final from = _lastScreen!;
    final step = (screen - from).distance;
    final world = viewport.toWorld(screen);
    final point = StrokePoint(
      world.dx,
      world.dy,
      _pressure.next(pressure, synthesized: synthesized),
    );
    if (step < PointSpacing.minDistance) {
      _dropped.add((screen, point));
      return;
    }
    _keepExtremeDropped(from, screen);
    _drawTravel += step;
    _lastScreen = screen;
    if (_straighten.move(screen, point)) return;
    live.add(point);
  }

  /// Keeps the dropped point furthest from the line [from] → [to], if it
  /// is far enough off it to be a detail (a cusp tip).
  void _keepExtremeDropped(Offset from, Offset to) {
    if (_dropped.isEmpty) return;
    var best = PointSpacing.keepExtreme;
    (Offset, StrokePoint)? keep;
    for (final dropped in _dropped) {
      final d = _distanceToSegment(dropped.$1, from, to);
      if (d > best) {
        best = d;
        keep = dropped;
      }
    }
    _dropped.clear();
    if (keep == null) return;
    final (at, point) = keep;
    _drawTravel += (at - from).distance;
    if (_straighten.move(at, point)) return;
    live.add(point);
  }

  static double _distanceToSegment(Offset p, Offset a, Offset b) {
    final ab = b - a;
    final l2 = ab.dx * ab.dx + ab.dy * ab.dy;
    if (l2 == 0) return (p - a).distance;
    final t = (((p - a).dx * ab.dx + (p - a).dy * ab.dy) / l2).clamp(0.0, 1.0);
    return (p - (a + ab * t)).distance;
  }

  /// Ends the current contact. [liftTime] is the pen-up timestamp, when known.
  void _finishDraw({Duration? liftTime}) {
    final tool = _tool;
    if (tool != null) {
      _tool = null;
      tool.up();
    } else if (_erasing) {
      _showEraser(_drawKind == PointerDeviceKind.touch ? null : _lastScreen);
    } else {
      final points = _settleEnd(live.finish());
      // A bounce was shown while it touched (under the nib, where the pen
      // just lifted, for less than `BounceFilter.maxContact`) and goes now.
      if (points.isNotEmpty && !_isBounce(liftTime)) {
        final stroke = Stroke(
          id: clock.newId(),
          surfaceId: model.surfaceId,
          tool: live.tool,
          color: live.color,
          width: live.width,
          style: live.style,
          points: points,
          createdAt: _drawStartedAt,
        );
        // The live outline's builder completes it (cheaply) at pen-up.
        final path = LiveStrokeBuilder.finishLive(
          live,
          points,
          tool: stroke.tool,
          width: stroke.width,
          style: stroke.style,
        );
        if (path != null) StrokeRenderer.adopt(stroke, path);
        PerfProbe.lift(liftTime);
        developer.Timeline.timeSync('len.commitStroke', () => model.addStroke(stroke));
      }
      _recordLift(liftTime);
    }
    _resetDraw();
  }

  /// Whether the contact that just ended was an accidental stylus bounce.
  bool _isBounce(Duration? liftTime) =>
      liftTime != null &&
      _isStylus(_drawKind) &&
      _bounces.isBounce(
        down: _drawStartTime,
        up: liftTime,
        start: _drawStartScreen,
        travel: _drawTravel,
      );

  void _recordLift(Duration? liftTime) {
    if (liftTime != null && _isStylus(_drawKind) && _lastScreen != null) {
      _bounces.recordLift(liftTime, _lastScreen!);
    }
  }

  /// Abandons the current stroke without committing it.
  void cancelDraw() => _cancelDraw();

  void _cancelDraw() {
    final tool = _tool;
    _tool = null;
    if (tool != null) {
      tool.cancel();
    } else if (_drawPointer != null && !_erasing) {
      live.finish();
    }
    _showEraser(null);
    _resetDraw();
  }

  void _resetDraw() {
    _straighten.end();
    samples?.end();
    _drawPointer = null;
    _drawKind = null;
    _erasing = false;
    _lastScreen = null;
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

  ToolPointer _toolPointer(PointerEvent e) => ToolPointer(
    screen: e.localPosition,
    world: viewport.toWorld(e.localPosition),
    pressure: _pressureOf(e),
  );

  StrokePoint _pointOf(PointerEvent e) {
    final world = viewport.toWorld(e.localPosition);
    final pressure = _pressure.next(_pressureOf(e), synthesized: e.synthesized);
    return StrokePoint(world.dx, world.dy, pressure);
  }

  /// Keeps the stroke's last samples from swelling into an end blob.
  static List<StrokePoint> _settleEnd(List<StrokePoint> points) {
    final settled = PressureFilter.settleEnd([for (final p in points) p.pressure]);
    return [
      for (var i = 0; i < points.length; i++) StrokePoint(points[i].x, points[i].y, settled[i]),
    ];
  }

  static double _pressureOf(PointerEvent e) => _normalisedPressure(e, e.pressure);

  /// [raw] pressure (in [e]'s device range) as 0.05..1; 0.5 without a stylus.
  static double _normalisedPressure(PointerEvent e, double raw) {
    if (!_isStylus(e.kind)) return 0.5;
    final range = e.pressureMax - e.pressureMin;
    if (range <= 0) return 0.5;
    return ((raw - e.pressureMin) / range).clamp(0.05, 1.0);
  }

  bool _wantsErase(PointerEvent e) =>
      tools.tool == EditorTool.eraser ||
      routeStylus(e.kind, e.buttons, penButtonAction) == StylusRoute.eraser;

  // ---------------------------------------------------------------------------
  // Navigation

  void _navigate(int pointer, Offset position) {
    final before = _navPointers.values.toList();
    _navPointers[pointer] = position;
    final after = _navPointers.values.toList();

    final focalBefore = _centroid(before);
    final focalAfter = _centroid(after);
    viewport.panBy(focalAfter - focalBefore);

    if (after.length >= 2) {
      final spreadBefore = _spread(before, focalBefore);
      final spreadAfter = _spread(after, focalAfter);
      if (spreadBefore > 0) viewport.zoomAt(focalAfter, spreadAfter / spreadBefore);
    }
  }

  static Offset _centroid(List<Offset> points) =>
      points.reduce((a, b) => a + b) / points.length.toDouble();

  static double _spread(List<Offset> points, Offset centre) =>
      points.map((p) => (p - centre).distance).reduce((a, b) => a + b) / points.length;

  // ---------------------------------------------------------------------------
  // Helpers

  void _showEraser(Offset? screen) {
    live.showEraser(
      screen == null ? null : viewport.toWorld(screen),
      tools.eraserRadius / viewport.scale,
    );
  }

  void _noteStylus() {
    if (_stylusSeen) return;
    _stylusSeen = true;
    onStylusDetected?.call();
  }

  static bool _isStylus(PointerDeviceKind? kind) =>
      kind == PointerDeviceKind.stylus || kind == PointerDeviceKind.invertedStylus;
}
