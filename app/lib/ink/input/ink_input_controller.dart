import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import '../../core/clock.dart';
import '../../domain/stroke.dart';
import '../surface_model.dart';
import '../tool_settings.dart';
import '../tools/content_tools.dart';
import '../tools/pointer_tool.dart';
import '../viewport.dart';
import 'hold_to_straighten.dart';
import 'live_ink.dart';

/// Turns raw pointer events into drawing, erasing and navigation.
///
/// Routing rules:
///  * **Stylus** always draws. The eraser end (inverted stylus) or a barrel
///    button held (S Pen side button) erases. A stylus landing cancels a
///    stroke a palm may have started and stops any finger navigation.
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
/// drawing pointer through [content] instead of drawing ink.
class InkInputController {
  InkInputController({
    required this._model,
    required this.viewport,
    required this.tools,
    required this.live,
    this.clock = const Clock(),
    this.onStylusDetected,
    this.content,
  }) : _straighten = HoldToStraighten(live);

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

  final HoldToStraighten _straighten;

  /// Non-inking tools (lasso, shapes, text, laser), if the editor has them.
  final ContentTools? content;

  /// The pointer tool handling the current drawing pointer, if any.
  PointerTool? _tool;

  /// Points closer than this (in screen pixels) to the previous one are
  /// dropped; it removes jitter without visible loss of detail.
  static const double _minPointDistance = 0.75;

  /// Stylus buttons that turn the pen into an eraser while held. Android
  /// reports the S Pen side button as [kPrimaryStylusButton]
  /// (`MotionEvent.BUTTON_STYLUS_PRIMARY >> 4`); Windows reports the barrel
  /// button as primary and the eraser flag as [kSecondaryStylusButton].
  static const int _eraseButtons = kPrimaryStylusButton | kSecondaryStylusButton;

  int? _drawPointer;
  PointerDeviceKind? _drawKind;
  bool _erasing = false;
  bool _eraseStarted = false;
  Offset? _lastScreen;

  final Map<int, Offset> _navPointers = {};
  double _lastPanZoomScale = 1;
  bool _stylusSeen = false;

  // ---------------------------------------------------------------------------
  // Pointer lifecycle

  void handleDown(PointerDownEvent e) {
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
    if (e.pointer == _drawPointer) {
      _continueDraw(e);
    } else if (_navPointers.containsKey(e.pointer)) {
      _navigate(e.pointer, e.localPosition);
    }
  }

  void handleUp(PointerUpEvent e) {
    if (e.pointer == _drawPointer) {
      _finishDraw();
    }
    _navPointers.remove(e.pointer);
  }

  void handleCancel(PointerCancelEvent e) {
    if (e.pointer == _drawPointer) _cancelDraw();
    _navPointers.remove(e.pointer);
  }

  /// Shows the eraser outline while hovering (mouse or hovering stylus).
  void handleHover(PointerHoverEvent e) {
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

  void handlePanZoomStart(PointerPanZoomStartEvent e) => _lastPanZoomScale = 1;

  void handlePanZoomUpdate(PointerPanZoomUpdateEvent e) {
    viewport.panBy(e.localPanDelta);
    if (e.scale > 0 && e.scale != _lastPanZoomScale) {
      viewport.zoomAt(e.localPosition, e.scale / _lastPanZoomScale);
      _lastPanZoomScale = e.scale;
    }
  }

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
    _startDraw(e, erase: _wantsErase(e));
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

  void _startDraw(PointerDownEvent e, {required bool erase}) {
    _drawPointer = e.pointer;
    _drawKind = e.kind;
    _erasing = erase;
    _eraseStarted = false;
    _lastScreen = e.localPosition;
    final tool = erase ? null : content?.toolFor(tools.tool);
    if (tool != null) {
      _tool = tool..down(_toolPointer(e));
      return;
    }
    if (erase) {
      _showEraser(e.localPosition);
      _eraseTo(e.localPosition);
    } else {
      final ink = tools.activeInk;
      final config = tools.configOf(ink);
      live.begin(
        tool: ink,
        color: config.current.color,
        width: config.current.width,
        style: tools.styleFor(ink),
      );
      live.add(_pointOf(e));
      _straighten.begin(e.localPosition, enabled: tools.holdToStraighten, scale: viewport.scale);
    }
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
    if ((e.localPosition - _lastScreen!).distance < _minPointDistance) return;
    _lastScreen = e.localPosition;
    final point = _pointOf(e);
    if (_straighten.move(e.localPosition, point)) return;
    live.add(point);
  }

  void _finishDraw() {
    final tool = _tool;
    if (tool != null) {
      _tool = null;
      tool.up();
    } else if (_erasing) {
      _showEraser(_drawKind == PointerDeviceKind.touch ? null : _lastScreen);
    } else {
      final points = live.finish();
      if (points.isNotEmpty) {
        model.addStroke(
          Stroke(
            id: clock.newId(),
            surfaceId: model.surfaceId,
            tool: live.tool,
            color: live.color,
            width: live.width,
            style: live.style,
            points: points,
            createdAt: clock.nowMs(),
          ),
        );
      }
    }
    _resetDraw();
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
    return StrokePoint(world.dx, world.dy, _pressureOf(e));
  }

  static double _pressureOf(PointerEvent e) {
    if (!_isStylus(e.kind)) return 0.5;
    final range = e.pressureMax - e.pressureMin;
    if (range <= 0) return 0.5;
    return ((e.pressure - e.pressureMin) / range).clamp(0.05, 1.0);
  }

  bool _wantsErase(PointerEvent e) =>
      tools.tool == EditorTool.eraser ||
      e.kind == PointerDeviceKind.invertedStylus ||
      (e.kind == PointerDeviceKind.stylus && e.buttons & _eraseButtons != 0);

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
