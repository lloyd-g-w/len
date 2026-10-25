import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../core/clock.dart';
import '../../domain/stroke.dart';
import '../input/live_ink.dart';
import '../selection/selection_chrome.dart';
import '../shapes/kappa_curve.dart';
import '../shapes/shape_builder.dart';
import '../surface_model.dart';
import '../viewport.dart';
import 'pointer_tool.dart';

/// The Shape tool drawing a curve, a gesture at a time, through the points
/// tapped (a κ-curve, [KappaCurve]: it passes through each and bends most
/// there, smoothly in between): a tap places a point, a press-drag places
/// one where the drag ends (the curve follows it), a tap on the last point
/// makes it a corner (or smooth again; a drag from it moves it), a tap on
/// the first point closes the curve (three points at least) and finishes
/// it, a double tap (a second tap on the last point) finishes it open, as
/// do Enter and a change of tool ([finish]); Escape drops it ([cancel]).
/// The curve so far is the live stroke between gestures; it is committed as
/// one stroke (one undo step), closed ones with the [fill] given at the
/// start.
///
/// Until then the curve has a history of its own, which the editor's undo
/// and redo act on while it is drawn ([canUndo], [undo], [redo]): undo
/// takes back the last point placed or changed (the one being placed,
/// mid-gesture), redo puts it back; undoing the first point drops the
/// curve, and redo brings it back as long as nothing else was drawn
/// ([forget]). Listeners hear when that history changes.
class CurveDrawing extends ChangeNotifier {
  CurveDrawing({required this.live, required this.viewport, this.clock = const Clock()});

  final LiveInk live;
  final ViewportController viewport;
  final Clock clock;

  /// Taps closer together than this (ms) on the last point finish.
  static const int doubleTapMs = 400;

  /// Movement (screen pixels) that turns a press into a drag.
  static const double slop = 4;

  SurfaceModel? _model;
  int? _fill;
  int _startedAt = 0;

  /// The points so far, and which are corners.
  List<Offset> _points = [];
  List<int> _corners = [];

  /// The state before the gesture in progress, to go back to if it is
  /// abandoned.
  _Spline? _before;

  /// The states before each change after the first point (undo), and
  /// those undone (redo).
  final List<_Spline> _placed = [], _undone = [];

  /// The curve whose first point was undone, for redo to bring back.
  _Dropped? _dropped;

  void Function()? _begin;

  Offset _pressScreen = Offset.zero;
  bool _dragged = false;
  bool _closing = false;
  bool _finishing = false;

  /// The press is on the last point: a tap makes it a corner (or smooth),
  /// a drag moves it.
  bool _onLast = false;
  int _lastUp = -doubleTapMs - 1;
  bool _pressed = false;

  /// Whether a curve is being drawn.
  bool get active => _model != null;

  /// What to show over the curve being drawn (its points, the close
  /// target, its corners); null when none is.
  final ValueNotifier<CurveGuide?> guide = ValueNotifier(null);

  /// A press at [p]: the first point of a new curve on [model] (whose
  /// live stroke [begin] starts), or the next one, closing or finishing.
  void down(
    ToolPointer p, {
    required SurfaceModel model,
    required void Function() begin,
    int? fill,
  }) {
    _pressed = true;
    _pressScreen = p.screen;
    _dragged = false;
    _closing = _finishing = _onLast = false;
    if (!active) {
      _dropped = null;
      _model = model;
      _fill = fill;
      _startedAt = clock.nowMs();
      (_begin = begin)();
      _before = null;
      _restore((points: [p.world], corners: const []));
      notifyListeners();
      return;
    }
    _before = _state;
    final reach = SelectionChrome.shapeHitRadius(p.kind);
    final last = viewport.toScreen(_points.last);
    if ((p.screen - last).distance <= reach) {
      if (clock.nowMs() - _lastUp <= doubleTapMs) {
        _finishing = true;
      } else {
        _onLast = true;
      }
      return;
    }
    if (closesAt(p.screen, p.kind)) {
      _closing = true;
      _show();
      return;
    }
    _points = [..._points, p.world];
    _show();
  }

  /// Whether a press at [screen] by a [kind] of pointer would close the
  /// curve (on its first point, with three placed).
  bool closesAt(Offset screen, [PointerDeviceKind kind = PointerDeviceKind.touch]) =>
      active &&
      _points.length >= 3 &&
      (viewport.toScreen(_points.first) - screen).distance <= SelectionChrome.shapeHitRadius(kind);

  /// The pointer at [p]: after the slop, the point pressed (placed by
  /// this press, or the last one) follows it.
  void move(ToolPointer p) {
    if (!_pressed || !active || _finishing || _closing) return;
    if (!_dragged && (p.screen - _pressScreen).distance < slop) return;
    _dragged = true;
    _points = [..._points]..[_points.length - 1] = p.world;
    _show();
  }

  /// The pointer lifted: a closing press closes and finishes the curve, a
  /// finishing one finishes it, a tap on the last point makes it a corner
  /// (or smooth again).
  void up() {
    if (!_pressed) return;
    _pressed = false;
    _lastUp = _dragged ? -doubleTapMs - 1 : clock.nowMs();
    if (_closing) {
      _commit(closed: true);
      return;
    }
    if (_finishing) {
      _commit(closed: false);
      return;
    }
    if (_onLast && !_dragged) {
      final last = _points.length - 1;
      _corners = _corners.contains(last)
          ? [..._corners.where((c) => c != last)]
          : [..._corners, last];
      _show();
    }
    if (_before case final before?) {
      _placed.add(before);
      _undone.clear();
      notifyListeners();
    }
  }

  /// Whether [undo] has anything to take back: a curve is being drawn.
  bool get canUndo => active;

  /// Whether [redo] has an anchor (or a dropped curve) to put back.
  bool get canRedo => active ? _undone.isNotEmpty : _dropped != null;

  /// Takes back the last anchor placed (the one being placed, if pressed);
  /// the first one drops the curve. False when no curve is drawn.
  bool undo() {
    if (!active) return false;
    if (_pressed) {
      cancelGesture();
    } else if (_placed.isEmpty) {
      final dropped = (
        model: _model!,
        fill: _fill,
        startedAt: _startedAt,
        spline: _state,
        undone: [..._undone],
      );
      cancel();
      _dropped = dropped;
    } else {
      _undone.add(_state);
      _restore(_placed.removeLast());
    }
    _lastUp = -doubleTapMs - 1; // A tap on the last anchor now isn't a double tap.
    notifyListeners();
    return true;
  }

  /// Puts back the last anchor undone (or the curve dropped); false when
  /// there is none.
  bool redo() {
    if (!canRedo) return false;
    if (_dropped case final dropped?) {
      _dropped = null;
      _model = dropped.model;
      _fill = dropped.fill;
      _startedAt = dropped.startedAt;
      _begin?.call();
      _undone.addAll(dropped.undone);
      _restore(dropped.spline);
    } else {
      _placed.add(_state);
      _restore(_undone.removeLast());
    }
    _lastUp = -doubleTapMs - 1;
    notifyListeners();
    return true;
  }

  /// Forgets a dropped curve (something else was drawn or undone): redo no
  /// longer brings it back.
  void forget() {
    if (_dropped == null) return;
    _dropped = null;
    notifyListeners();
  }

  _Spline get _state => (points: [..._points], corners: [..._corners]);

  /// Shows [spline] as the curve so far.
  void _restore(_Spline spline) {
    _points = spline.points;
    _corners = spline.corners;
    _show();
  }

  /// The gesture was abandoned (it became a pinch): the curve is as it was
  /// before it, or none if it was the first.
  void cancelGesture() {
    if (!_pressed) return;
    _pressed = false;
    _closing = _finishing = false;
    final before = _before;
    if (before == null) {
      cancel();
      return;
    }
    _restore(before);
  }

  /// Commits the curve drawn so far (open); false when none was drawn.
  bool finish() {
    forget();
    if (!active) return false;
    _commit(closed: false);
    return true;
  }

  /// Drops the curve drawn so far; false when none was drawn.
  bool cancel() {
    forget();
    if (!active) return false;
    live.finish();
    _end();
    return true;
  }

  /// No curve is drawn any more.
  void _end() {
    guide.value = null;
    _model = null;
    _pressed = false;
    _placed.clear();
    _undone.clear();
    notifyListeners();
  }

  /// The curve as drawn so far, closed or not; null with one point.
  ShapeGeometry? _geometry({required bool closed}) {
    if (_points.length < 2) return null;
    return KappaCurve.geometry(_points, closed: closed && _points.length >= 3, corners: _corners);
  }

  void _show() {
    final shape = live.shape = _geometry(closed: _closing);
    final spacing = 2 / viewport.scale;
    live.replaceAll(
      shape == null
          ? [StrokePoint(_points.first.dx, _points.first.dy, 0.5)]
          : ShapeBuilder.pointsOf(shape, spacing: spacing),
    );
    guide.value = CurveGuide(
      anchors: [..._points],
      closes: _points.length >= 3,
      tangents: const [],
      corners: [..._corners],
    );
  }

  void _commit({required bool closed}) {
    final model = _model!;
    final shape = _geometry(closed: closed);
    if (shape != null) live.shape = shape;
    final style = closed ? live.style.withFill(_fill) : live.style;
    final points = shape == null
        ? const <StrokePoint>[]
        : ShapeBuilder.pointsOf(shape, spacing: 2 / viewport.scale);
    final tool = live.tool, color = live.color, width = live.width;
    live.finish();
    _end();
    if (shape == null || _tiny(shape)) return;
    model.addStroke(
      Stroke(
        id: clock.newId(),
        surfaceId: model.surfaceId,
        tool: tool,
        color: color,
        width: width,
        style: style,
        points: points,
        createdAt: _startedAt,
        shape: shape,
      ),
    );
  }

  @override
  void dispose() {
    guide.dispose();
    super.dispose();
  }

  /// Whether [shape] spans less than a few pixels (taps on one spot).
  bool _tiny(ShapeGeometry shape) {
    var r = Rect.fromPoints(shape.points.first, shape.points.first);
    for (final p in shape.points) {
      r = r.expandToInclude(Rect.fromPoints(p, p));
    }
    return r.longestSide * viewport.scale < slop;
  }
}

/// A curve's points so far and its corners (see [CurveDrawing]).
typedef _Spline = ({List<Offset> points, List<int> corners});

/// A curve whose first anchor was undone.
typedef _Dropped = ({
  SurfaceModel model,
  int? fill,
  int startedAt,
  _Spline spline,
  List<_Spline> undone,
});

/// What is shown over a curve being drawn (world coordinates): its
/// [anchors] (the points it passes through), whether the first one
/// [closes] it, which are [corners] (indices), and [tangents] to show as
/// arms (none for a curve through points).
@immutable
class CurveGuide {
  const CurveGuide({
    required this.anchors,
    required this.closes,
    this.tangents = const [],
    this.corners = const [],
  });

  final List<Offset> anchors;
  final bool closes;
  final List<({Offset anchor, Offset handle})> tangents;
  final List<int> corners;
}
