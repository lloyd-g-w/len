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
  bool _dragged = false;
  Timer? _longPressTimer;
  ({String id, int time})? _lastTap;

  @override
  void down(ToolPointer p) {
    _startScreen = p.screen;
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
        if (_dragged) {
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

  @override
  void cancel() {
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
    final model = selection.model;
    selection.select(
      model.strokesNear(lasso.bounds).where(lasso.selectsStroke),
      model.elementsNear(lasso.bounds).where(lasso.selectsElement),
    );
  }

  /// Selects what is under a tap; a second tap on a text box edits it.
  void _tap(Offset world, {bool keepSelection = false}) {
    final model = selection.model;
    final element = ContentHitTest.elementAt(model, world);
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
