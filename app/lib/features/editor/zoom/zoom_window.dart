import 'dart:async';
import 'dart:math' as math;
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import '../../../ink/input/ink_input_controller.dart';
import '../../../ink/surface_model.dart';
import '../../../ui/design_tokens.dart';
import 'zoom_box_viewport.dart';
import 'zoom_frame.dart';
import 'zoom_host.dart';
import 'zoom_window_state.dart';

export 'zoom_window_state.dart';

part 'zoom_window_moves.dart';

/// The zoom window (GoodNotes-style): a magnified box at the bottom of the
/// screen that writes into a frame on the page. Ink written in the box goes
/// through the real pen pipeline ([input], an `InkInputController` over the
/// box's viewport [view]), so it is smoothed, pressure-shaped, shown live
/// and undone per stroke like any other.
///
/// Ink lifted in the frame's advance zone moves the frame on along the
/// line, and at the end of the line back to its start, a line down; at the
/// bottom of a page, to the next page (see [ZoomRules]). The main view
/// follows the frame. The frame is placed by dragging it on the page and
/// sized with its handle; nothing else is set.
class ZoomWindow extends ChangeNotifier with _ZoomMoves {
  ZoomWindow({
    required this.host,
    required InkInputController Function(SurfaceModel model, ZoomBoxViewport view) input,
  }) : _inputFor = input;

  @override
  final ZoomHost host;
  final InkInputController Function(SurfaceModel, ZoomBoxViewport) _inputFor;

  /// The box as a viewport onto the frame's surface.
  @override
  late final ZoomBoxViewport view = ZoomBoxViewport(onPan: _panBox, onZoom: _zoomBox);

  /// Routes the box's pointers (created when first opened).
  InkInputController? get input => _input;
  InkInputController? _input;

  SurfaceModel? _model;

  /// The model of the frame's surface while open.
  @override
  SurfaceModel? get model => _model;

  /// How long ink lifted in the advance zone waits for the pen to come
  /// back before the frame moves on (a dot, a cross stroke, the next
  /// letter of the word).
  static const Duration pause = Duration(milliseconds: 450);

  /// Touches on the page this soon after the pen was in the box are a palm.
  static const Duration palmQuiet = InkInputController.palmQuiet;

  /// Whether the page view should ignore new touches (a hand writing in
  /// the box rests on it).
  final ValueNotifier<bool> blocksPage = ValueNotifier(false);
  Timer? _unblock;

  bool get isOpen => _frame != null;

  /// Whether the window is open; notifies only when it opens or closes
  /// (the editor's layout makes room for the box).
  final ValueNotifier<bool> opened = ValueNotifier(false);

  /// The box's height as dragged by its top edge (logical pixels), or null
  /// for the editor's choice; the editor keeps it within limits.
  final ValueNotifier<double?> boxHeight = ValueNotifier(null);

  /// Opens the window on the page in view (or the canvas), framing the
  /// start of the visible lines once the box is laid out; or [at] a frame
  /// kept from before (when its page is still there), kept on its page.
  void open({ZoomFrame? at}) {
    if (isOpen) return;
    final resume = at != null && host.has(at.surfaceId);
    final id = resume ? at.surfaceId : host.current;
    _frame = resume ? at : ZoomFrame(surfaceId: id, origin: Offset.zero, scale: 1);
    _placed = false;
    _resume = resume;
    _attach(id);
    host.changes.addListener(_onHost);
    if (!_box.isEmpty) _layOut();
    opened.value = true;
    notifyListeners();
  }

  /// What a notebook keeps of the window for the next time it opens.
  ZoomWindowState get state {
    final frame = _frame;
    final settled = frame == null || _glide == null ? frame : frame.copyWith(origin: _glideEnd);
    return ZoomWindowState(frame: settled, boxHeight: boxHeight.value);
  }

  /// Takes up a [state] kept from before: the box's height, and the frame
  /// if the window was open.
  void restore(ZoomWindowState state) {
    boxHeight.value = state.boxHeight;
    if (state.frame case final frame?) open(at: frame);
  }

  /// Closes the window; the ink written stays.
  void close() {
    if (!isOpen) return;
    _disarm();
    _stopGlide();
    _input?.cancelDraw();
    host.changes.removeListener(_onHost);
    _detach();
    _frame = null;
    _placed = false;
    _contact(false);
    opened.value = false;
    notifyListeners();
  }

  void toggle() => isOpen ? close() : open();

  /// Scrolls the main view to show the frame clear of the chrome (after
  /// the box moved to the other edge).
  void showFrame() {
    if (isOpen) _reveal();
  }

  /// The box was laid out at [size] (rotation, resize): the frame keeps
  /// its place and magnification and takes the box's new shape.
  void setBox(Size size) {
    if (size == _box || size.isEmpty) return;
    _box = size;
    if (!isOpen) return;
    if (!_placed) return _layOut();
    _set(_frame!.copyWith(origin: _rules.clamp(_frame!, _frame!.origin)));
    _reveal();
  }

  /// Where the box's paper lies on the screen (for the platform's
  /// low-latency ink, which draws in screen pixels).
  Offset boxOrigin = Offset.zero;

  // ---------------------------------------------------------------------------
  // Input

  /// A contact began in the box: the frame stops moving, its page takes
  /// the editor's input (live ink shows on it) and the page view follows.
  void penDown() {
    _disarm();
    _finishGlide();
    _contact(true);
    final frame = _frame;
    if (frame == null) return;
    host.activate(frame.surfaceId);
    _reveal();
  }

  /// The contact ended; [ink] is what it wrote (surface coordinates), or
  /// null when it erased or did nothing. Ink in the advance zone moves the
  /// frame on: at once near its edge, else after a [pause].
  void penUp(Rect? ink) {
    _contact(false);
    final frame = _frame;
    if (frame == null || ink == null) return;
    _lineInk = _lineInk?.expandToInclude(ink) ?? ink;
    final rules = _rules;
    if (!rules.inZone(frame, ink.right)) return;
    if (rules.advancesNow(frame, ink.right)) return _advance(ink.right);
    _arm(ink.right, pause);
  }

  void _contact(bool down) {
    _unblock?.cancel();
    if (down) {
      blocksPage.value = true;
    } else {
      _unblock = Timer(palmQuiet, () => blocksPage.value = false);
    }
  }

  // ---------------------------------------------------------------------------
  // Surfaces

  void _attach(String id) {
    final model = _model = host.acquire(id);
    final input = _input;
    if (input == null) {
      _input = _inputFor(model, view);
    } else {
      input.model = model;
    }
  }

  void _detach() {
    final model = _model;
    final frame = _frame;
    if (model == null || frame == null) return;
    model.forgetView(view);
    host.release(frame.surfaceId);
    _model = null;
  }

  @override
  void _switchTo(String id) {
    _detach();
    _attach(id);
  }

  /// The page under the frame went (deleted, moved elsewhere): start again
  /// on the page in view.
  void _onHost() {
    final frame = _frame;
    if (frame == null || host.has(frame.surfaceId)) return;
    _disarm();
    _stopGlide();
    _detach();
    _frame = frame.copyWith(surfaceId: host.current);
    _attach(host.current);
    _resume = false;
    _place();
  }

  @override
  void _sync() {
    final frame = _frame;
    if (frame == null || _box.isEmpty) return;
    view.show(scale: frame.scale, offset: -frame.origin * frame.scale, size: _box);
    // The frame's ink, with some room around it for the advance.
    final rect = frame.rectFor(_box);
    _model?.ensureLoaded(rect.inflate(rect.width / 2), view: view);
  }

  @override
  void notify() => notifyListeners();

  @override
  void dispose() {
    close();
    _unblock?.cancel();
    blocksPage.dispose();
    opened.dispose();
    armed.dispose();
    boxHeight.dispose();
    view.dispose();
    super.dispose();
  }

  /// Frame geometry for tests and painters.
  @visibleForTesting
  double get lineStart => _lineStart;
  @visibleForTesting
  double get lineEnd => _lineEnd;
}
