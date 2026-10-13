import 'package:flutter/gestures.dart';

import '../../core/clock.dart';
import '../../domain/preferences.dart';
import '../navigation/kinetic_pan.dart';
import '../surface_model.dart';
import '../tool_settings.dart';
import '../tools/content_tools.dart';
import '../viewport.dart';
import 'canvas_gestures.dart';
import 'highlight_snap.dart';
import 'hold_to_straighten.dart';
import 'ink_drawing.dart';
import 'ink_events.dart';
import 'live_ink.dart';
import 'pointer_navigation.dart';
import 'sample_source.dart';
import 'stylus_buttons.dart';
import 'stylus_proximity.dart';

/// Turns raw pointer events into drawing, erasing and navigation.
///
/// Routing rules:
///  * **Stylus** always draws. The eraser end (inverted stylus) erases; a
///    barrel button held (S Pen side button) does [penButtonAction] (erase,
///    lasso or nothing). A stylus landing cancels a stroke a palm may have
///    started and stops any finger navigation.
///  * **Touch** is ignored while a stylus is down or was near within
///    [palmQuiet] (it is almost certainly the palm: between strokes the
///    pen lifts only briefly). Otherwise it navigates when palm rejection
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
///
/// The drawing contact (ink, erasing, pointer tools) lives in [InkDrawing],
/// pan and zoom in [PointerNavigation]; this class routes events to them.
class InkInputController {
  InkInputController({
    required SurfaceModel model,
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
  }) : _penButtonAction = penButtonAction ?? (() => PenButtonAction.eraser),
       _draw = InkDrawing(
         model: model,
         viewport: viewport,
         tools: tools,
         live: live,
         clock: clock,
         content: content,
         samples: samples,
       ),
       _nav = PointerNavigation(viewport: viewport, kinetic: kinetic);

  /// The surface being edited. Can be swapped (e.g. when turning pages);
  /// a stroke in progress is abandoned rather than committed to the wrong
  /// surface.
  SurfaceModel get model => _draw.model;
  set model(SurfaceModel value) {
    if (identical(value, _draw.model)) return;
    _draw.cancel();
    _draw.model = value;
    content?.model = value;
  }

  /// Snaps highlighter strokes over PDF text to it (paged editors).
  set highlightSnap(HighlightSnap? value) => _draw.highlightSnap = value;

  /// Moments of ink input the editor may react to (tips, notices).
  InkEvents get events => _draw.events;

  final ViewportController viewport;
  final ToolSettings tools;
  final LiveInk live;
  final Clock clock;

  /// Called the first time a stylus is used.
  final void Function()? onStylusDetected;

  /// Inertial panning after navigation gestures (optional).
  final KineticPan? kinetic;

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

  /// The drawing contact (ink, erasing or a pointer tool).
  final InkDrawing _draw;

  /// Pointers that pan/zoom, the wheel and the trackpad.
  final PointerNavigation _nav;

  bool _stylusSeen = false;

  /// Touches landing this soon after the pen was touching or hovering are
  /// taken for the writing hand's palm: they neither navigate nor draw.
  static const Duration palmQuiet = Duration(milliseconds: 300);

  final StylusProximity _stylus = StylusProximity();

  // ---------------------------------------------------------------------------
  // Pointer lifecycle

  void handleDown(PointerDownEvent e) {
    _stylus.note(e);
    kinetic?.begin();
    gestures?.down(e, navigates: tools.stylusOnly ?? false);
    switch (e.kind) {
      case PointerDeviceKind.stylus || PointerDeviceKind.invertedStylus:
        _stylusDown(e);
      case PointerDeviceKind.mouse:
        if (e.buttons & kPrimaryMouseButton != 0 && _draw.pointer == null) {
          _draw.start(e, erase: tools.tool == EditorTool.eraser);
        } else {
          _nav.add(e.pointer, e.localPosition);
        }
      case PointerDeviceKind.touch:
        _touchDown(e);
      case PointerDeviceKind.trackpad || PointerDeviceKind.unknown:
        break;
    }
  }

  void handleMove(PointerMoveEvent e) {
    _stylus.note(e);
    gestures?.move(e);
    if (e.pointer == _draw.pointer) {
      _draw.move(e);
    } else if (_nav.contains(e.pointer)) {
      _nav.move(e);
      // A gesture that moves the view is no tap, double tap or long press.
      if (_nav.moving) gestures?.navigated();
    }
  }

  void handleUp(PointerUpEvent e) {
    _stylus.note(e);
    if (e.pointer == _draw.pointer) _draw.up(e);
    _nav.up(e);
    gestures?.up(e);
  }

  void handleCancel(PointerCancelEvent e) {
    _stylus.note(e);
    if (e.pointer == _draw.pointer) _draw.cancel();
    _nav.cancel(e);
    gestures?.cancel(e);
  }

  /// Shows the eraser outline while hovering (mouse or hovering stylus),
  /// and the laser's dot under a hovering mouse (presenting with a mouse
  /// needs no button held).
  void handleHover(PointerHoverEvent e) {
    _stylus.note(e);
    gestures?.hover(e);
    if (_draw.pointer != null) return; // Don't fight the active pointer.
    samples?.hover(e);
    _draw.showEraser(_wantsErase(e) ? e.localPosition : null);
    final laser = content?.laser;
    if (laser == null) return;
    if (e.kind == PointerDeviceKind.mouse && tools.tool == EditorTool.laser) {
      laser.config = tools.laser;
      laser.hover(viewport.toWorld(e.localPosition));
    } else {
      laser.hover(null);
    }
  }

  void handleExit() {
    _draw.showEraser(null);
    content?.laser.hover(null);
  }

  // ---------------------------------------------------------------------------
  // Wheel / trackpad

  void handleSignal(PointerSignalEvent e) => _nav.signal(e);

  void handlePanZoomStart(PointerPanZoomStartEvent e) => _nav.panZoomStart(e);

  void handlePanZoomUpdate(PointerPanZoomUpdateEvent e) => _nav.panZoomUpdate(e);

  void handlePanZoomEnd(PointerPanZoomEndEvent e) => _nav.panZoomEnd(e);

  // ---------------------------------------------------------------------------
  // Routing

  void _stylusDown(PointerDownEvent e) {
    _noteStylus();
    if (_draw.pointer != null) {
      if (_draw.byStylus) {
        // There is only one pen: its previous contact lost its up event.
        _draw.finish();
      } else {
        _draw.cancel(); // Probably a palm touched down first.
      }
    }
    // Fingers resting on the screen are the palm now; stop them panning.
    _nav.clear();
    final route = routeStylus(e.kind, e.buttons, penButtonAction);
    final eraserTool = route == StylusRoute.tool && tools.tool == EditorTool.eraser;
    _draw.start(
      e,
      erase: route == StylusRoute.eraser || eraserTool,
      lasso: route == StylusRoute.lasso,
    );
  }

  void _touchDown(PointerDownEvent e) {
    // A palm while writing, or between strokes.
    if (_draw.byStylus || _stylus.isNear(e.timeStamp, within: palmQuiet)) return;
    // Android reports no hover exit for a stylus leaving range, so a stale
    // eraser cursor would linger; a finger is a good moment to clear it.
    _draw.showEraser(null);
    final palmRejection = tools.stylusOnly ?? false;
    if (palmRejection) {
      _nav.add(e.pointer, e.localPosition, slop: kTouchSlop);
      return;
    }
    final drawing = _draw.pointer;
    if (drawing == null && _nav.isEmpty) {
      _draw.start(e, erase: tools.tool == EditorTool.eraser);
      return;
    }
    if (drawing != null && _draw.kind == PointerDeviceKind.touch) {
      // A second finger: the first one was the start of a pinch, not ink.
      final firstPosition = _draw.lastScreen!;
      _draw.cancel();
      _nav.add(drawing, firstPosition, slop: kTouchSlop);
    }
    _nav.add(e.pointer, e.localPosition, slop: kTouchSlop);
  }

  /// Whether [pointer] currently pans/zooms the view (rather than drawing,
  /// or being ignored as a palm).
  bool navigates(int pointer) => _nav.contains(pointer);

  /// Abandons the current stroke without committing it.
  void cancelDraw() => _draw.cancel();

  bool _wantsErase(PointerEvent e) =>
      tools.tool == EditorTool.eraser ||
      routeStylus(e.kind, e.buttons, penButtonAction) == StylusRoute.eraser;

  void _noteStylus() {
    if (_stylusSeen) return;
    _stylusSeen = true;
    onStylusDetected?.call();
  }
}
