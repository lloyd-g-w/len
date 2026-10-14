import 'dart:async';

import 'package:flutter/services.dart';

import '../../domain/stroke.dart';
import '../../domain/surface_element.dart';
import '../selection/lasso.dart';
import '../selection/lasso_path.dart';
import '../selection/selection_chrome.dart';
import '../selection/selection_controller.dart';
import '../selection/selection_frame.dart';
import '../shapes/shape_handles.dart';
import '../viewport.dart';
import 'content_hit_test.dart';
import 'pointer_tool.dart';
import 'shape_tool.dart';

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

/// The lasso: draw a loop to select, tap to select one item, drag the
/// selection to move it, drag its handles to resize or rotate it — or,
/// for a single shape, its own points to reshape it (one undo step per
/// drag; Shift keeps a line's end on 15° steps). A long
/// press on empty space asks to paste ([onLongPress]); a double tap on a
/// text box edits it ([onEditText]).
///
/// On [text] (PDF text) where no ink or element is hit: a tap selects the
/// word; a press held still selects it and dragging on extends it; a quick
/// open drag (not a loop) that selects no ink selects the text it spans.
/// A loop starting on text still selects the ink it circles.
class LassoTool implements PointerTool {
  LassoTool({
    required this.selection,
    required this.viewport,
    required this.path,
    int Function()? nowMs,
  }) : _now = nowMs ?? _wallClock;

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

  /// The press started on [text], with no ink (but highlights) or element
  /// there.
  bool _onText = false;

  @override
  void down(ToolPointer p) {
    _startScreen = _lastScreen = p.screen;
    _startWorld = _lastWorld = p.world;
    _dragged = false;
    final frame = selection.frame;
    final shape = selection.shape;
    if (shape != null) {
      if (SelectionChrome.shapeHandleAt(shape, viewport, p.screen) case final point?) {
        _mode = _Mode.reshape;
        _shape = shape;
        _point = point;
        _grab = ShapeHandles.of(shape)[point] - p.world;
        return;
      }
    }
    if (frame != null && !selection.isEmpty) {
      final handle = SelectionChrome.hit(frame, viewport, p.screen, shape: shape);
      if (handle != null || frame.contains(p.world)) {
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
      case _Mode.lasso:
        path.add(p.world);
      case _Mode.text:
        text!.selectBetween(_startScreen, p.screen, done: false);
      case _Mode.transform:
        final frame = _startFrame!;
        final result = switch (_handle) {
          null => frame.moved(p.world - _startWorld),
          SelectionHandle.rotate => frame.rotatedTowards(p.world),
          final handle => frame.resized(handle, p.world + _grab),
        };
        selection.setPreview(result.transform, result.frame);
        if (_handle == null) dragOut?.dragging(p.screen, _centreOnScreen);
      case _Mode.reshape:
        selection.reshape(ShapeHandles.drag(_shape!, _point, _reshapeTarget(p.world + _grab)));
      case _Mode.idle:
        break;
    }
  }

  /// Where a dragged shape point goes for the pointer at [world]: a
  /// line's or arrow's end keeps to 15° steps around the other with Shift.
  Offset _reshapeTarget(Offset world) {
    final shape = _shape!;
    if (shape.kind.isClosed || !HardwareKeyboard.instance.isShiftPressed) return world;
    return ShapeTool.constrain(shape.kind, shape.points[1 - _point], world);
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
          _tap(_lastWorld, keepSelection: true);
        }
      case _Mode.reshape:
        _dragged ? selection.commitReshape() : selection.cancelReshape();
      case _Mode.idle:
        break;
    }
    _mode = _Mode.idle;
    _shape = null;
  }

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
      ..cancelPreview()
      ..cancelReshape();
    _mode = _Mode.idle;
    _shape = null;
  }

  /// Whether ink or an element lies under [world]. Highlights don't count:
  /// highlighted PDF text stays selectable (a lasso loop still takes them).
  bool _hitsContent(Offset world) {
    final model = selection.model;
    return ContentHitTest.elementAt(model, world) != null ||
        ContentHitTest.strokeAt(model, world, 8 / viewport.scale, highlighter: false) != null;
  }

  /// A tap on text: its word, and the ink selection goes.
  void _tapText() {
    _lastTap = null;
    selection.clear();
    text!.selectWordAt(_startScreen);
  }

  /// Whether the lasso path came back near its start (a loop): its ends are
  /// closer than half its extent. An open drag over text selects text.
  bool get _closed {
    final points = path.points;
    if (points.length < 3) return false;
    final bounds = Rect.fromPoints(points.first, points.first);
    final extent = points.fold(bounds, (r, p) => r.expandToInclude(Rect.fromPoints(p, p)));
    return (points.last - points.first).distance < extent.longestSide / 2;
  }

  void _selectLasso() {
    final lasso = Lasso([...path.points]);
    if (!lasso.isValid) {
      selection.clear();
      return;
    }
    selection.selectLasso(lasso);
  }

  /// Selects what is under a tap; a second tap on a text box edits it.
  void _tap(Offset world, {bool keepSelection = false}) {
    final model = selection.model;
    var element = ContentHitTest.elementAt(model, world);
    // Ink lies above elements beneath it: a tap on that ink selects the ink.
    if (element != null && element.belowInk && !keepSelection) {
      if (ContentHitTest.strokeAt(model, world, 8 / viewport.scale) != null) element = null;
    }
    final now = _now();
    if (element != null) {
      final last = _lastTap;
      _lastTap = (id: element.id, time: now);
      if (last != null &&
          last.id == element.id &&
          now - last.time <= doubleTapMs &&
          element.knownType == ElementType.text) {
        _lastTap = null;
        selection.clear();
        onEditText?.call(element);
        return;
      }
      if (!keepSelection) selection.select(const [], [element]);
      return;
    }
    _lastTap = null;
    if (keepSelection) return;
    final stroke = ContentHitTest.strokeAt(model, world, 8 / viewport.scale);
    if (stroke != null) {
      selection.select([stroke], const []);
    } else {
      selection.clear();
    }
  }
}

enum _Mode { idle, lasso, text, transform, reshape }
