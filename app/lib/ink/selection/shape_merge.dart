import 'dart:ui';

import '../../data/connector_queries.dart';
import '../../domain/shaped.dart';
import '../../domain/stroke.dart';
import '../shapes/shape_builder.dart';

/// Merges the live strokes one shape has after edits made at once on
/// several devices ("twins": each device replaced the same stroke by its
/// own edit, so both edits arrived), into one stroke carrying the changes
/// of each, the same on every device (docs/SYNC_PROTOCOL.md, `sh.r`).
///
/// The twins' lineages ([ShapeGeometry.replaces]) name the version they
/// started from ([baseOf]). Against it, each part of the shape takes the
/// value a twin changed it to: the look (tool, colour, width, opacity,
/// fill, the rest of the style), and the geometry — for lines and arrows
/// each end (its point with its attachment) and the bend apart, else the
/// outline whole. Two twins changing one part differently: the twin of
/// the least id wins it. Without a base (edits by clients that write no
/// lineage, or its record unknown here: a device that never held it) the
/// twin of the least id wins whole; two devices merging the same twins at
/// once, one knowing the base and one not, write one record (its id made
/// from the twins' ids) with different contents: the last write wins.
abstract final class ShapeMerge {
  /// The groups of two or more strokes of one shape ([Shaped.shapeId])
  /// among [shapes], each in id order.
  static List<List<T>> twinsOf<T extends Shaped>(Iterable<T> shapes) {
    final named = <String, Map<String, T>>{};
    for (final s in shapes) {
      (named[s.shapeId] ??= {})[s.id] = s;
    }
    return [
      for (final group in named.values)
        if (group.length > 1) group.values.toList()..sort((a, b) => a.id.compareTo(b.id)),
    ];
  }

  /// The ids of the [twins] another one of them replaced (named in its
  /// lineage): versions an edit, or a merge, superseded that came back or
  /// arrived before the deletion of them (a merge made and edited again
  /// on one device, its strokes pushed before its deletions).
  static Set<String> staleIn(List<Shaped> twins) =>
      {for (final t in twins) ...t.shape!.replaces}.intersection({for (final t in twins) t.id});

  /// The id of the version [twins] (in id order) started from: the
  /// nearest of the first one's own id and lineage that every other one
  /// is or descends from. Null when they name none in common (edited by
  /// clients that write no lineage, or lineages too long).
  static String? baseOf(List<Shaped> twins) {
    final first = twins.first;
    for (final id in [first.id, ...first.shape!.replaces]) {
      if (twins.every((t) => t.id == id || t.shape!.replaces.contains(id))) return id;
    }
    return null;
  }

  /// [twins] (live strokes of one shape, in id order) merged against
  /// [base] (the version they started from, if known) into a new stroke
  /// [id] of the same shape, whose lineage names the twins, then the
  /// base's.
  static Stroke merged(List<Stroke> twins, ShapeVersion? base, {required String id}) {
    final versions = [for (final t in twins) ShapeVersion.of(t)];
    // The value of a part: the first twin's that changed it, else the base's.
    T pick<T>(T Function(ShapeVersion v) part) {
      final was = base == null ? null : part(base);
      for (final v in versions) {
        final value = part(v);
        if (base == null || value != was) return value;
      }
      return was as T;
    }

    final first = twins.first;
    final rest = pick((v) => v.style.copyWith(opacity: 1).withFill(null));
    final style = rest
        .copyWith(opacity: pick((v) => v.style.opacity))
        .withFill(pick((v) => v.style.fill));
    final lines = [...versions, ?base].every((v) => _isLine(v.shape));
    final shape = (lines ? _mergedLine(pick) : pick((v) => _outline(v.shape))).withLineage(
      first.shapeId,
      [
        for (final t in twins) t.id,
        if (base != null) ...[base.id, ...base.shape.replaces] else ...first.shape!.replaces,
      ],
    );
    final look = Stroke(
      id: id,
      surfaceId: first.surfaceId,
      tool: pick((v) => v.tool),
      color: pick((v) => v.color),
      width: pick((v) => v.width),
      points: first.points,
      createdAt: twins.map((t) => t.createdAt).reduce((a, b) => a < b ? a : b),
      style: style,
      shape: first.shape,
    );
    return ShapeBuilder.reshaped(look, shape, id: id);
  }

  static bool _isLine(ShapeGeometry s) => s.kind == ShapeKind.line || s.kind == ShapeKind.arrow;

  /// A shape's outline alone (no identity or lineage), compared whole.
  static ShapeGeometry _outline(ShapeGeometry s) => s.withLineage(null, const []);

  /// A line or arrow from its parts picked apart: its kind, each end (its
  /// point and attachment) and its bend.
  static ShapeGeometry _mergedLine(T Function<T>(T Function(ShapeVersion v) part) pick) {
    final kind = pick((v) => v.shape.kind);
    final (tail, tailAt) = pick((v) => (v.shape.points[0], v.shape.tail));
    final (tip, tipAt) = pick((v) => (v.shape.points[1], v.shape.tip));
    final Offset? bend = pick((v) => v.shape.isBent ? v.shape.points[2] : null);
    return ShapeGeometry(kind, [tail, tip, ?bend], tail: tailAt, tip: tipAt);
  }
}
