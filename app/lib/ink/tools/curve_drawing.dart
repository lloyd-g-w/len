import 'dart:ui';

import 'package:flutter/foundation.dart';

import '../../core/clock.dart';
import '../../domain/stroke.dart';
import '../input/live_ink.dart';
import '../selection/selection_chrome.dart';
import '../shapes/shape_builder.dart';
import '../surface_model.dart';
import '../viewport.dart';
import 'pointer_tool.dart';

/// The Shape tool drawing a curve, a gesture at a time: a tap places an
/// anchor (a corner: straight on to the next), a press-drag places one and
/// pulls its tangents out symmetrically (smooth), a tap on the first anchor
/// closes the curve (a drag there pulls its tangents too) and finishes it,
/// a double tap (a second tap on the last anchor) finishes it open, as do
/// Enter and a change of tool ([finish]); Escape drops it ([cancel]). The
/// curve so far is the live stroke between gestures; it is committed as
/// one stroke (one undo step), closed ones with the [fill] given at the
/// start.
///
/// Until then the curve has a history of its own, which the editor's undo
/// and redo act on while it is drawn ([canUndo], [undo], [redo]): undo
/// takes back the last anchor placed (the one being placed, mid-gesture),
/// redo puts it back; undoing the first anchor drops the curve, and redo
/// brings it back as long as nothing else was drawn ([forget]). Listeners
/// hear when that history changes.
class CurveDrawing extends ChangeNotifier {
  CurveDrawing({required this.live, required this.viewport, this.clock = const Clock()});

  final LiveInk live;
  final ViewportController viewport;
  final Clock clock;

  /// Taps closer together than this (ms) on the last anchor finish.
  static const int doubleTapMs = 400;

  /// Movement (screen pixels) that turns a press into a tangent pull.
  static const double slop = 4;

  SurfaceModel? _model;
  int? _fill;
  int _startedAt = 0;

  /// The open spline so far: anchor, out, in, anchor, … (the last anchor's
  /// out handle is [_lastOut], the first one's in handle [_firstIn]).
  List<Offset> _points = [];
  Offset _lastOut = Offset.zero;
  Offset? _firstIn;

  /// The state before the gesture in progress, to go back to if it is
  /// abandoned.
  _Spline? _before;

  /// The states before each anchor placed after the first (undo), and
  /// those undone (redo).
  final List<_Spline> _placed = [], _undone = [];

  /// The curve whose first anchor was undone, for redo to bring back.
  _Dropped? _dropped;

  void Function()? _begin;

  Offset _pressScreen = Offset.zero;
  bool _dragged = false;
  bool _closing = false;
  bool _finishing = false;
  int _lastUp = -doubleTapMs - 1;
  bool _pressed = false;

  /// Whether a curve is being drawn.
  bool get active => _model != null;

  /// What to show over the curve being drawn (its anchors, the close
  /// target, the tangents being pulled); null when none is.
  final ValueNotifier<CurveGuide?> guide = ValueNotifier(null);

  int get _anchors => (_points.length + 2) ~/ 3;

  /// A press at [p]: the first anchor of a new curve on [model] (whose
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
    _closing = _finishing = false;
    if (!active) {
      _dropped = null;
      _model = model;
      _fill = fill;
      _startedAt = clock.nowMs();
      (_begin = begin)();
      _before = null;
      _restore((points: [p.world], lastOut: p.world, firstIn: null));
      notifyListeners();
      return;
    }
    _before = _state;
    final reach = SelectionChrome.shapeHitRadius(p.kind);
    final last = viewport.toScreen(_points.last);
    if ((p.screen - last).distance <= reach && clock.nowMs() - _lastUp <= doubleTapMs) {
      _finishing = true;
      return;
    }
    if (closesAt(p.screen, p.kind)) {
      _closing = true;
      _show();
      return;
    }
    _points = [..._points, _lastOut, p.world, p.world];
    _lastOut = p.world;
    _show();
  }

  /// Whether a press at [screen] by a [kind] of pointer would close the
  /// curve (on its first anchor, with a second placed).
  bool closesAt(Offset screen, [PointerDeviceKind kind = PointerDeviceKind.touch]) =>
      active &&
      _anchors >= 2 &&
      (viewport.toScreen(_points.first) - screen).distance <= SelectionChrome.shapeHitRadius(kind);

  /// The pointer at [p]: after the slop, the anchor pressed gets tangents
  /// pulled out to [p] (and opposite).
  void move(ToolPointer p) {
    if (!_pressed || !active || _finishing) return;
    if (!_dragged && (p.screen - _pressScreen).distance < slop) return;
    _dragged = true;
    final q = p.world;
    if (_closing) {
      final a = _points.first;
      _points = [..._points]..[1] = q;
      _firstIn = a * 2 - q;
    } else {
      final i = _points.length - 1, a = _points[i];
      _lastOut = q;
      if (i == 0) {
        _firstIn = a * 2 - q;
      } else {
        _points = [..._points]..[i - 1] = a * 2 - q;
      }
    }
    _show();
  }

  /// The pointer lifted: a closing press closes and finishes the curve, a
  /// finishing one finishes it.
  void up() {
    if (!_pressed) return;
    _pressed = false;
    _lastUp = _dragged ? -doubleTapMs - 1 : clock.nowMs();
    if (_closing) {
      _commit(closed: true);
    } else if (_finishing) {
      _commit(closed: false);
    } else if (_before case final before?) {
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

  _Spline get _state => (points: [..._points], lastOut: _lastOut, firstIn: _firstIn);

  /// Shows [spline] as the curve so far.
  void _restore(_Spline spline) {
    _points = spline.points;
    _lastOut = spline.lastOut;
    _firstIn = spline.firstIn;
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

  /// The curve as drawn so far, closed or not; null with one anchor.
  ShapeGeometry? _geometry({required bool closed}) {
    if (_anchors < 2) return null;
    if (!closed) return ShapeGeometry(ShapeKind.curve, _points);
    return ShapeGeometry(ShapeKind.curve, [..._points, _lastOut, _firstIn ?? _points.first]);
  }

  void _show() {
    final shape = live.shape = _geometry(closed: _closing);
    final spacing = 2 / viewport.scale;
    live.replaceAll(
      shape == null
          ? [StrokePoint(_points.first.dx, _points.first.dy, 0.5)]
          : ShapeBuilder.pointsOf(shape, spacing: spacing),
    );
    guide.value = _guide();
  }

  /// The anchors so far, and the tangents of the last one (the first while
  /// closing): where the next segment leaves from.
  CurveGuide _guide() {
    final p = _points, i = p.length - 1;
    final a = _closing ? p.first : p[i];
    final into = _closing ? _firstIn : (i == 0 ? _firstIn : p[i - 1]);
    final out = _closing ? (p.length > 1 ? p[1] : null) : _lastOut;
    return CurveGuide(
      anchors: [for (var j = 0; j < p.length; j += 3) p[j]],
      closes: _anchors >= 2,
      tangents: [
        for (final t in [into, out])
          if (t != null && t != a) (anchor: a, handle: t),
      ],
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

/// A curve's control points so far (see [CurveDrawing]).
typedef _Spline = ({List<Offset> points, Offset lastOut, Offset? firstIn});

/// A curve whose first anchor was undone.
typedef _Dropped = ({
  SurfaceModel model,
  int? fill,
  int startedAt,
  _Spline spline,
  List<_Spline> undone,
});

/// What [CurveDrawing] shows over a curve being drawn (world coordinates):
/// its [anchors], whether the first one [closes] it, and the [tangents]
/// of the anchor placed last (or being pulled).
@immutable
class CurveGuide {
  const CurveGuide({required this.anchors, required this.closes, required this.tangents});

  final List<Offset> anchors;
  final bool closes;
  final List<({Offset anchor, Offset handle})> tangents;
}
