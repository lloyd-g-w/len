import 'dart:async';

import 'package:flutter/services.dart';

import '../../domain/stroke.dart';
import '../../domain/surface_element.dart';
import '../selection/connectors.dart';
import '../selection/lasso.dart';
import '../selection/lasso_config.dart';
import '../selection/lasso_path.dart';
import '../selection/selection_chrome.dart';
import '../selection/selection_controller.dart';
import '../selection/selection_frame.dart';
import '../shapes/bezier.dart';
import '../shapes/kappa_curve.dart';
import '../shapes/shape_handles.dart';
import '../viewport.dart';
import 'content_hit_test.dart';
import 'pointer_tool.dart';

part 'lasso_tool_picking.dart';

/// Where a selection dragged by the lasso may be dropped besides its own
/// surface: another editor of a split view. Positions are in the lasso's
/// screen coordinates.
abstract interface class SelectionDragOut {
  /// The selection is being moved with the pointer at [pointer] and its
  /// centre at [centre].
  void dragging(Offset pointer, Offset centre);

  /// The pointer lifted at [pointer] with the selection's centre at
  /// [centre]. Returns true when another editor took a copy there; the
  /// selection then stays where it was.
  bool drop(Offset pointer, Offset centre);

  /// The drag ended (dropped or cancelled).
  void end();
}

/// Text the lasso selects besides ink: PDF text in a paged editor.
/// Positions are in the lasso's screen coordinates.
abstract interface class LassoText {
  /// Whether there is text right under [screen].
  bool hasTextAt(Offset screen);

  /// Selects the word under [screen], with its menu.
  void selectWordAt(Offset screen);

  /// Selects the text from [from] to [to]; offers the menu when [done].
  void selectBetween(Offset from, Offset to, {required bool done});
}

/// The lasso: draw a loop (or drag a rectangle, [LassoShape.rectangle]) to
/// select, tap to select one item, drag the selection to move it, drag its
/// handles to resize or rotate it (Shift: 15° steps) — or, for a single
/// shape, its own handles to reshape it ([ShapeHandles.drag]: one undo
/// step per drag, Shift constrains, snaps within [snapReach]). On a
/// selected curve, a tap on the line adds an anchor there and a double tap
/// on an anchor removes it. A long press on empty space asks to paste ([onLongPress]); a
/// double tap on a text box edits it ([onEditText]). What it selects
/// follows the [LassoConfig] read at each press: its shape, how much of an
/// item it must cover, and which kinds of item (taps too).
///
/// On [text] (PDF text) where no ink or element is hit: a tap selects the
/// word; a press held still selects it and dragging on extends it; a quick
/// open drag (not a loop; any rectangle) that selects no ink selects the
/// text it spans.
/// A loop starting on text still selects the ink it circles.
class LassoTool implements PointerTool {
  LassoTool({
    required this.selection,
    required this.viewport,
    required this.path,
    this._config,
    int Function()? nowMs,
  }) : _now = nowMs ?? _wallClock;

  final LassoConfig Function()? _config;

  /// The options of the current gesture.
  LassoConfig _options = const LassoConfig();

  final SelectionController selection;
  final ViewportController viewport;
  final LassoPath path;
  final int Function() _now;

  static int _wallClock() => DateTime.now().millisecondsSinceEpoch;

  /// Asked to edit a text box (double tap).
  void Function(SurfaceElement element)? onEditText;

  /// A long press on empty space at ([screen], [world]).
  void Function(Offset screen, Offset world)? onLongPress;

  /// Lets a moved selection be dropped into another editor (split view).
  SelectionDragOut? dragOut;

  /// PDF text under the ink, if any (paged editors).
  LassoText? text;

  /// Movement (pixels) that turns a press into a drag.
  static const double slop = 6;

  /// How near (pixels) a dragged shape handle snaps to lines, angles and
  /// other points.
  static const double snapReach = 8;
  static const Duration longPress = Duration(milliseconds: 500);
  static const int doubleTapMs = 400;

  _Mode _mode = _Mode.idle;
  SelectionHandle? _handle;
  SelectionFrame? _startFrame;
  Offset _startScreen = Offset.zero;
  Offset _startWorld = Offset.zero;
  Offset _lastWorld = Offset.zero;
  Offset _lastScreen = Offset.zero;
  bool _dragged = false;

  /// From the pointer to the grabbed resize handle's true spot (world).
  Offset _grab = Offset.zero;

  /// The shape whose point [_point] is being dragged.
  ShapeGeometry? _shape;
  int _point = 0;
  Timer? _longPressTimer;
  ({String id, int time})? _lastTap;

  /// The last tap on a shape's handle: a second one on a curve's anchor
  /// removes it.
  ({int point, int time})? _lastHandleTap;

  /// The press started on [text], with no ink (but highlights) or element
  /// there.
  bool _onText = false;

  @override
  void down(ToolPointer p) {
    _startScreen = _lastScreen = p.screen;
    _startWorld = _lastWorld = p.world;
    _dragged = false;
    if (_config case final config?) _options = config();
    final frame = selection.frame;
    final shape = selection.shape;
    if (shape != null) {
      final point = SelectionChrome.shapeHandleAt(
        shape,
        viewport,
        p.screen,
        frame: frame,
        kind: p.kind,
      );
      if (point != null) {
        _mode = _Mode.reshape;
        _shape = shape;
        _point = point;
        _grab = ShapeHandles.of(shape)[point].at - p.world;
        return;
      }
    }
    if (frame != null && !selection.isEmpty) {
      final handle = SelectionChrome.hit(frame, viewport, p.screen, shape: shape);
      if (handle != null || SelectionChrome.grabs(frame, viewport, p.screen, shape: shape)) {
        _mode = _Mode.transform;
        _handle = handle;
        _startFrame = frame;
        // Resizing follows the pointer from where the handle really is: a
        // handle kept inside the view (or grabbed off-centre) doesn't jump.
        _grab = handle == null || handle == SelectionHandle.rotate
            ? Offset.zero
            : frame.at(handle.fraction) - p.world;
        return;
      }
    }
    _mode = _Mode.lasso;
    _onText = (text?.hasTextAt(p.screen) ?? false) && !_hitsContent(p.world);
    path.begin(p.world);
    _longPressTimer = Timer(longPress, () {
      if (_dragged || _mode != _Mode.lasso) return;
      path.clear();
      if (_onText) {
        // Held on text: select its word; dragging on extends it.
        _mode = _Mode.text;
        selection.clear();
        text!.selectWordAt(_startScreen);
        return;
      }
      _mode = _Mode.idle;
      onLongPress?.call(_startScreen, _startWorld);
    });
  }

  @override
  void move(ToolPointer p) {
    _lastWorld = p.world;
    _lastScreen = p.screen;
    if (!_dragged && (p.screen - _startScreen).distance < slop) return;
    _dragged = true;
    _longPressTimer?.cancel();
    switch (_mode) {
      case _Mode.lasso when _options.shape == LassoShape.rectangle:
        path.rectangle(_startWorld, p.world);
      case _Mode.lasso:
        path.add(p.world);
      case _Mode.text:
        text!.selectBetween(_startScreen, p.screen, done: false);
      case _Mode.transform:
        final frame = _startFrame!;
        final result = switch (_handle) {
          null => frame.moved(p.world - _startWorld),
          SelectionHandle.rotate => frame.rotatedTowards(
            p.world,
            steps: HardwareKeyboard.instance.isShiftPressed,
          ),
          final handle => frame.resized(handle, p.world + _grab),
        };
        selection.setPreview(result.transform, result.frame);
        if (_handle == null) dragOut?.dragging(p.screen, _centreOnScreen);
      case _Mode.reshape:
        selection.reshape(_reshaped(p.world + _grab));
      case _Mode.idle:
        break;
    }
  }

  @override
  void up() {
    _longPressTimer?.cancel();
    switch (_mode) {
      case _Mode.lasso:
        if (!_dragged) {
          _onText ? _tapText() : _tap(_startWorld);
        } else {
          _selectLasso();
          if (_onText && selection.isEmpty && !_closed) {
            text!.selectBetween(_startScreen, _lastScreen, done: true);
          }
        }
        path.clear();
      case _Mode.text:
        if (_dragged) {
          text!.selectBetween(_startScreen, _lastScreen, done: true);
        } else {
          text!.selectWordAt(_startScreen);
        }
      case _Mode.transform:
        if (_dragged && _droppedElsewhere()) {
          selection.cancelPreview();
        } else if (_dragged) {
          selection.commitPreview();
        } else {
          selection.cancelPreview();
          if (!_addAnchor(_lastWorld)) _tap(_lastWorld, keepSelection: true);
        }
      case _Mode.reshape:
        selection.attachHint = null;
        if (_dragged) {
          selection.commitReshape();
        } else {
          selection.cancelReshape();
          _tapHandle();
        }
      case _Mode.idle:
        break;
    }
    _mode = _Mode.idle;
    _shape = null;
  }

  /// The selected shape with its handle [_point] dragged to [to]; a line's
  /// or arrow's end attaches to a shape it is dropped on (or in), or lets
  /// go ([Connectors]).
  ShapeGeometry _reshaped(Offset to) {
    final shape = _shape!;
    final dragged = ShapeHandles.drag(
      shape,
      _point,
      to,
      shift: HardwareKeyboard.instance.isShiftPressed,
      snap: snapReach / viewport.scale,
    );
    final line = shape.kind == ShapeKind.line || shape.kind == ShapeKind.arrow;
    if (!line || _point > 1) return dragged;
    // At the end as dragged (snapped, Shift-stepped), not the pointer.
    final hint = selection.attachHint = Connectors.find(
      selection.model,
      dragged.points[_point],
      reach: attachReach / viewport.scale,
      towards: shape.points[1 - _point],
      exclude: {?selection.shapeStroke?.id},
    );
    return Connectors.attach(dragged, _point, hint, dragged.points[_point]);
  }

  /// How near (pixels) an outline a dragged line end attaches to it.
  static const double attachReach = 12;

  /// Where the centre of the selection being moved is on screen.
  Offset get _centreOnScreen => viewport.toScreen(_startFrame!.center + (_lastWorld - _startWorld));

  /// Offers a moved selection to [dragOut] (another editor).
  bool _droppedElsewhere() {
    final out = dragOut;
    if (out == null || _handle != null) return false;
    final dropped = out.drop(_lastScreen, _centreOnScreen);
    out.end();
    return dropped;
  }

  @override
  void cancel() {
    if (_mode == _Mode.transform) dragOut?.end();
    _longPressTimer?.cancel();
    path.clear();
    selection
      ..attachHint = null
      ..cancelPreview()
      ..cancelReshape();
    _mode = _Mode.idle;
    _shape = null;
  }
}

enum _Mode { idle, lasso, text, transform, reshape }
