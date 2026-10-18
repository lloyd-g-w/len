import 'dart:ui';

import '../../domain/shaped.dart';
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

  ShapeAttachment get attachment => ShapeAttachment(target.shapeId, at);

  /// Where the end goes.
  Offset get point => ShapeAnchors.pointAt(target.shape!, at);
}

/// Lines and arrows whose ends stay attached to shapes (connectors): an
/// end dropped on a closed shape's outline, or inside it, remembers the
/// shape ([ShapeGeometry.tail], [ShapeGeometry.tip]) by its identity
/// across edits ([Stroke.shapeId]); when the shape is edited, the ends
/// attached to it follow in the same edit (`SelectionController`), and
/// after a sync ends left behind by edits on two devices are brought onto
/// it ([ConnectorRepair]). A line moved without its target lets go.
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

  /// [line] with its ends attached to [targets] (by shape id: their
  /// shapes now) moved onto the targets' outlines.
  static ShapeGeometry follow(ShapeGeometry line, Map<String, ShapeGeometry> targets) {
    var out = line;
    for (final index in [0, 1]) {
      final a = line.attachmentOf(index);
      final target = a == null ? null : targets[a.id];
      if (target == null) continue;
      out = _moveEnd(out, index, ShapeAnchors.pointAt(target, a!.at));
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

  /// The shape end [index] of [line] is attached to, among the strokes
  /// [named] by its attachment (those with its shape id: one, or more
  /// after edits of the shape on two devices at once): one it sits on
  /// ([sits]) if any, else the stroke of that very id, else the one of
  /// the least id — the same pick on every device. Null when detached or
  /// none is a target.
  static T? targetOf<T extends Shaped>(ShapeGeometry line, int index, Iterable<T> named) {
    final a = line.attachmentOf(index);
    if (a == null) return null;
    T? pick;
    for (final s in named) {
      if (s.shapeId != a.id || !ShapeAnchors.isTarget(s.shape)) continue;
      if (sits(line, index, s.shape)) return s;
      if (pick == null || s.id == a.id || (pick.id != a.id && s.id.compareTo(pick.id) < 0)) {
        pick = s;
      }
    }
    return pick;
  }

  /// [line] stroke rebuilt as [shape], with id [id]: an edit of it, so it
  /// keeps its shape id ([Stroke.shapeId]; docs/SYNC_PROTOCOL.md, `sh.o`).
  static Stroke rebuilt(Stroke line, ShapeGeometry shape, {required String id}) =>
      ShapeBuilder.reshaped(line, shape.withOrigin(line.shapeId), id: id);
}
