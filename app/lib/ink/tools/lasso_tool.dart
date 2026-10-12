import 'dart:async';
import 'dart:ui';

import '../../domain/surface_element.dart';
import '../selection/lasso.dart';
import '../selection/lasso_path.dart';
import '../selection/selection_chrome.dart';
import '../selection/selection_controller.dart';
import '../selection/selection_frame.dart';
import '../viewport.dart';
import 'content_hit_test.dart';
import 'pointer_tool.dart';

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

/// The lasso: draw a loop to select, tap to select one item, drag the
/// selection to move it, drag its handles to resize or rotate it. A long
/// press on empty space asks to paste ([onLongPress]); a double tap on a
/// text box edits it ([onEditText]).
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
  Timer? _longPressTimer;
  ({String id, int time})? _lastTap;

  @override
  void down(ToolPointer p) {
    _startScreen = _lastScreen = p.screen;
    _startWorld = _lastWorld = p.world;
    _dragged = false;
    final frame = selection.frame;
    if (frame != null && !selection.isEmpty) {
      final handle = SelectionChrome.hit(frame, viewport, p.screen);
      if (handle != null || frame.contains(p.world)) {
        _mode = _Mode.transform;
        _handle = handle;
        _startFrame = frame;
        return;
      }
    }
    _mode = _Mode.lasso;
    path.begin(p.world);
    _longPressTimer = Timer(longPress, () {
      if (_dragged || _mode != _Mode.lasso) return;
      _mode = _Mode.idle;
      path.clear();
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
      case _Mode.transform:
        final frame = _startFrame!;
        final result = switch (_handle) {
          null => frame.moved(p.world - _startWorld),
          SelectionHandle.rotate => frame.rotatedTowards(p.world),
          final handle => frame.resized(handle, p.world),
        };
        selection.setPreview(result.transform, result.frame);
        if (_handle == null) dragOut?.dragging(p.screen, _centreOnScreen);
      case _Mode.idle:
        break;
    }
  }

  @override
  void up() {
    _longPressTimer?.cancel();
    switch (_mode) {
      case _Mode.lasso:
        _dragged ? _selectLasso() : _tap(_startWorld);
        path.clear();
      case _Mode.transform:
        if (_dragged && _droppedElsewhere()) {
          selection.cancelPreview();
        } else if (_dragged) {
          selection.commitPreview();
        } else {
          selection.cancelPreview();
          _tap(_lastWorld, keepSelection: true);
        }
      case _Mode.idle:
        break;
    }
    _mode = _Mode.idle;
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
    selection.cancelPreview();
    _mode = _Mode.idle;
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

enum _Mode { idle, lasso, transform }
