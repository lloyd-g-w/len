import 'dart:math' as math;
import 'dart:ui';

import '../geometry/affine.dart';

/// The grab points of a selection frame.
enum SelectionHandle {
  topLeft(Offset(0, 0)),
  top(Offset(0.5, 0)),
  topRight(Offset(1, 0)),
  right(Offset(1, 0.5)),
  bottomRight(Offset(1, 1)),
  bottom(Offset(0.5, 1)),
  bottomLeft(Offset(0, 1)),
  left(Offset(0, 0.5)),
  rotate(Offset(0.5, 0));

  const SelectionHandle(this.fraction);

  /// Position within the frame rect (0..1 on each axis).
  final Offset fraction;

  bool get isCorner => fraction.dx != 0.5 && fraction.dy != 0.5;

  /// The handle on the opposite side (the fixed point while resizing).
  Offset get oppositeFraction => Offset(1 - fraction.dx, 1 - fraction.dy);
}

/// The box drawn around a selection: [rect] rotated by [angle] radians
/// about its centre (world coordinates). It keeps its rotation across
/// gestures, so a rotated selection is resized along its own axes.
class SelectionFrame {
  const SelectionFrame(this.rect, [this.angle = 0]);

  final Rect rect;
  final double angle;

  /// Smallest size (world units) a resize may shrink an axis to.
  static const double minExtent = 4;

  Offset get center => rect.center;

  /// World position of a point given as a fraction of the frame rect.
  Offset at(Offset fraction) =>
      _toWorld(Offset(rect.left + rect.width * fraction.dx, rect.top + rect.height * fraction.dy));

  List<Offset> get corners => [
    for (final f in const [Offset(0, 0), Offset(1, 0), Offset(1, 1), Offset(0, 1)]) at(f),
  ];

  /// Unit vector pointing "up" out of the frame's top edge.
  Offset get up => Offset(math.sin(angle), -math.cos(angle));

  Offset _toWorld(Offset local) => Affine.rotation(angle, pivot: center).apply(local);
  Offset _toLocal(Offset world) => Affine.rotation(-angle, pivot: center).apply(world);

  /// Whether world point [p] is inside the frame.
  bool contains(Offset p) => rect.contains(_toLocal(p));

  // ---------------------------------------------------------------------------
  // Gestures: each returns the world transform plus the resulting frame.

  ({Affine transform, SelectionFrame frame}) moved(Offset delta) =>
      (transform: Affine.translation(delta), frame: SelectionFrame(rect.shift(delta), angle));

  /// Rotation so that the rotate handle points from the centre towards
  /// [pointer]; with [snap], angles within 5° of a multiple of 45° snap.
  ({Affine transform, SelectionFrame frame}) rotatedTowards(Offset pointer, {bool snap = true}) {
    final v = pointer - center;
    var target = math.atan2(v.dx, -v.dy); // 0 = pointing up
    if (snap) {
      const step = math.pi / 4, tolerance = 5 * math.pi / 180;
      final nearest = (target / step).round() * step;
      if ((target - nearest).abs() < tolerance) target = nearest;
    }
    final delta = target - angle;
    return (transform: Affine.rotation(delta, pivot: center), frame: SelectionFrame(rect, target));
  }

  /// Resizing by dragging [handle] to world point [pointer]. Corners keep
  /// the aspect ratio; edges stretch one axis. The opposite handle stays put.
  ({Affine transform, SelectionFrame frame}) resized(SelectionHandle handle, Offset pointer) {
    final anchor = Offset(
      rect.left + rect.width * handle.oppositeFraction.dx,
      rect.top + rect.height * handle.oppositeFraction.dy,
    );
    final grabbed = Offset(
      rect.left + rect.width * handle.fraction.dx,
      rect.top + rect.height * handle.fraction.dy,
    );
    final p = _toLocal(pointer);
    final from = grabbed - anchor;
    final to = p - anchor;
    double sx = 1, sy = 1;
    if (handle.isCorner) {
      // Project onto the diagonal so the aspect ratio is kept.
      final lenSq = from.distanceSquared;
      final s = lenSq == 0 ? 1.0 : (to.dx * from.dx + to.dy * from.dy) / lenSq;
      final minS = minExtent / math.max(1e-9, math.min(rect.width, rect.height));
      sx = sy = math.max(s, minS);
    } else if (handle.fraction.dx != 0.5) {
      sx = from.dx == 0 ? 1 : math.max(to.dx / from.dx, minExtent / math.max(rect.width, 1e-9));
    } else {
      sy = from.dy == 0 ? 1 : math.max(to.dy / from.dy, minExtent / math.max(rect.height, 1e-9));
    }
    final local = Affine.scaling(sx, sy, anchor: anchor);
    final transform = Affine.rotation(
      -angle,
      pivot: center,
    ).then(local).then(Affine.rotation(angle, pivot: center));
    final scaled = Rect.fromPoints(local.apply(rect.topLeft), local.apply(rect.bottomRight));
    // Re-centre: the new rect rotates about its own centre.
    final newCentre = _toWorld(scaled.center);
    return (
      transform: transform,
      frame: SelectionFrame(scaled.shift(newCentre - scaled.center), angle),
    );
  }

  /// The frame after an arbitrary [t] that keeps the frame rectangular.
  SelectionFrame transformed(Affine t) {
    final centre = t.apply(center);
    final xAxis = t.applyVector(Offset(math.cos(angle), math.sin(angle)));
    final yAxis = t.applyVector(Offset(-math.sin(angle), math.cos(angle)));
    return SelectionFrame(
      Rect.fromCenter(
        center: centre,
        width: rect.width * xAxis.distance,
        height: rect.height * yAxis.distance,
      ),
      math.atan2(xAxis.dy, xAxis.dx),
    );
  }
}
