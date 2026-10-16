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
import 'palm_guard.dart';
import 'pointer_navigation.dart';
import 'sample_source.dart';
import 'stylus_buttons.dart';
import 'stylus_proximity.dart';

part 'ink_input_routing.dart';

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
///    ([ToolSettings.stylusOnly]) is on or the editor is in reading
///    ([ToolSettings.reading]); if not, one finger draws and a
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
    this.palms,
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
  set model(SurfaceModel value) => switchTo(value);

  /// Sets [model]; [laserShift] moves the laser's trail into the new
  /// surface's coordinates (see `ContentTools.switchTo`).
  void switchTo(SurfaceModel value, {Offset? laserShift}) {
    if (identical(value, _draw.model)) return;
    _draw.cancel();
    _draw.model = value;
    content?.switchTo(value, laserShift: laserShift);
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

  /// The app-wide palm guard, if attached: a pen near another canvas (the
  /// other split pane, the zoom window's box) makes touches here palms too.
  final PalmGuard? palms;

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
    gestures?.down(e, navigates: tools.fingersNavigate);
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

  /// The platform took the pointer back (the window lost focus, rotated, a
  /// system gesture). A pen's ink is kept as written — the line was seen —
  /// while erasing, a scribble, tools and fingers (a pinch's start, a palm)
  /// cancel.
  void handleCancel(PointerCancelEvent e) {
    _stylus.note(e);
    if (e.pointer == _draw.pointer) {
      _draw.byStylus ? _draw.keep(e.timeStamp) : _draw.cancel();
    }
    _nav.cancel(e);
    gestures?.cancel(e);
  }

  /// Shows the eraser outline while hovering (mouse or hovering stylus),
  /// a hovering pen's preview of its ink, and the laser's dot under a
  /// hovering mouse (presenting with a mouse needs no button held).
  void handleHover(PointerHoverEvent e) {
    _stylus.note(e);
    gestures?.hover(e);
    // A finger whose erasing is held back while it may be a palm is one:
    // the pen hovers.
    if (isStylusKind(e.kind) && _draw.holdsErase) _draw.cancel();
    if (_draw.pointer != null) return; // Don't fight the active pointer.
    samples?.hover(e);
    _draw.showEraser(_wantsErase(e) ? e.localPosition : null);
    _draw.showPen(_previewsInk(e) ? e.localPosition : null);
    if (isStylusKind(e.kind)) live.expireCursorsSoon(); // It may leave unannounced.
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
    _draw.showPen(null);
    content?.laser.hover(null);
  }

  // ---------------------------------------------------------------------------
  // Wheel / trackpad

  void handleSignal(PointerSignalEvent e) => _nav.signal(e);

  void handlePanZoomStart(PointerPanZoomStartEvent e) => _nav.panZoomStart(e);

  void handlePanZoomUpdate(PointerPanZoomUpdateEvent e) => _nav.panZoomUpdate(e);

  void handlePanZoomEnd(PointerPanZoomEndEvent e) => _nav.panZoomEnd(e);

  /// Whether the last contact that ended left a stroke.
  bool get inked => _draw.inked;

  /// Whether [pointer] currently pans/zooms the view (rather than drawing,
  /// or being ignored as a palm).
  bool navigates(int pointer) => _nav.contains(pointer);

  /// Abandons the current stroke without committing it.
  void cancelDraw() => _draw.cancel();

  /// The stylus [e] is on another view of the same editor (the zoom
  /// window's box): fingers on this one are the writing hand's palm, so
  /// they stop drawing and panning, and new ones are ignored as between
  /// strokes.
  void stylusElsewhere(PointerEvent e) {
    _stylus.note(e);
    if (_draw.holdsErase) _draw.cancel(); // A palm, as when the pen hovers here.
    if (e is! PointerDownEvent) return;
    _noteStylus();
    if (_draw.pointer != null && !_draw.byStylus) _draw.cancel();
    _nav.clear();
  }
}
