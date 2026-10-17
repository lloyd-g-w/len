import 'dart:ui';

import '../../domain/stroke.dart';
import '../shapes/shape_anchors.dart';
import '../shapes/shape_builder.dart';
import '../shapes/shape_drags.dart';
import '../surface_model.dart';

/// A shape a line's or arrow's end attaches to, and where: shown while
/// the end is dragged (the target's outline highlighted, a dot at the
/// point), kept as its [attachment].
class AttachHint {
  const AttachHint(this.target, this.at);

  /// The target shape stroke.
  final Stroke target;

  /// The point on its outline ([ShapeAttachment.at]).
  final double at;

  ShapeAttachment get attachment => ShapeAttachment(target.id, at);

  /// Where the end goes.
  Offset get point => ShapeAnchors.pointAt(target.shape!, at);
}

/// Lines and arrows whose ends stay attached to shapes (connectors): an
/// end dropped on a closed shape's outline, or inside it, remembers the
/// shape ([ShapeGeometry.tail], [ShapeGeometry.tip]); when the shape is
/// edited, the ends attached to it follow in the same edit
/// (`SelectionController`). A line moved without its target lets go.
abstract final class Connectors {
  /// The shape on [model] an end at [p] attaches to: the nearest closed
  /// outline within [reach] (world units), else the topmost closed shape
  /// containing [p], attached where it faces [towards] (the line's other
  /// end). Strokes in [exclude] (the line itself) and hidden ones are
  /// skipped.
  static AttachHint? find(
    SurfaceModel model,
    Offset p, {
    required double reach,
    Offset? towards,
    Set<String> exclude = const {},
  }) {
    AttachHint? near;
    var nearest = reach;
    Stroke? inside;
    for (final s in model.strokesNear(Rect.fromCircle(center: p, radius: reach))) {
      final shape = s.shape;
      if (!ShapeAnchors.isTarget(shape) || exclude.contains(s.id) || model.isHidden(s.id)) {
        continue;
      }
      final at = ShapeAnchors.nearest(shape!, p);
      final d = (ShapeAnchors.pointAt(shape, at) - p).distance;
      if (d <= nearest) (nearest, near) = (d, AttachHint(s, at));
      if (ShapeAnchors.contains(shape, p) && (inside == null || Stroke.paintOrder(s, inside) > 0)) {
        inside = s;
      }
    }
    if (near != null) return near;
    if (inside == null) return null;
    return AttachHint(inside, ShapeAnchors.facing(inside.shape!, towards ?? p));
  }

  /// [line] with end [index] at [hint]'s point and attached there (or
  /// detached, at [fallback], with no [hint]).
  static ShapeGeometry attach(ShapeGeometry line, int index, AttachHint? hint, Offset fallback) {
    final moved = _moveEnd(line, index, hint?.point ?? fallback);
    return moved.withAttachment(index, hint?.attachment);
  }

  static ShapeGeometry _moveEnd(ShapeGeometry line, int index, Offset to) =>
      line.points[index] == to ? line : ShapeDrags(line).drag(index, to);

  /// [line] with its ends attached to [targets] (by old id: the new id
  /// and shape) moved onto the targets' new outlines and attached to their
  /// new ids.
  static ShapeGeometry follow(ShapeGeometry line, Map<String, Followed> targets) {
    var out = line;
    for (final index in [0, 1]) {
      final a = line.attachmentOf(index);
      final target = a == null ? null : targets[a.id];
      if (target == null) continue;
      out = _moveEnd(out, index, ShapeAnchors.pointAt(target.shape, a!.at));
      out = out.withAttachment(index, a.withId(target.id));
    }
    return out;
  }

  /// Whether end [index] of [line] lies where its attachment to [target]
  /// puts it (within [tolerance] world units).
  static bool sits(ShapeGeometry line, int index, ShapeGeometry? shape, {double tolerance = 0.05}) {
    final a = line.attachmentOf(index);
    if (a == null || !ShapeAnchors.isTarget(shape)) return false;
    return (ShapeAnchors.pointAt(shape!, a.at) - line.points[index]).distance <= tolerance;
  }

  /// [line] stroke rebuilt as [shape], with id [id].
  static Stroke rebuilt(Stroke line, ShapeGeometry shape, {required String id}) =>
      ShapeBuilder.reshaped(line, shape, id: id);
}

/// A target shape as edited: its new stroke [id] and [shape].
typedef Followed = ({String id, ShapeGeometry shape});
