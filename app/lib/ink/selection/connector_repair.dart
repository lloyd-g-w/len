import 'package:uuid/uuid.dart';

import '../../data/connector_queries.dart';
import '../../data/stroke_repository.dart';
import '../../domain/stroke.dart';
import '../../sync/remote_changes.dart';
import '../surface_model.dart';
import 'connectors.dart';

/// Brings connectors back onto their shapes after a sync (see
/// [Connectors]).
///
/// An edit of a shape moves the lines attached to it in the same change,
/// so one device alone never leaves an end off its shape. Two devices
/// editing at once can: one moves the box (and its arrow), the other
/// recolours the arrow, and the recoloured arrow still lies where the box
/// was. Every device that applies other devices' changes looks at the
/// surfaces they touched and replaces such a line by one whose ends lie on
/// the shapes they name ([Connectors.follow]), as a local edit (synced, not
/// undoable: nobody made it here).
///
/// The replacement's id is made from the line's and its targets' ids
/// ([idOf]), and its geometry from theirs alone, so devices repairing the
/// same line at once write the same stroke (one record, not two arrows),
/// and a repaired line sits on its shapes: nothing repairs it again.
class ConnectorRepair {
  ConnectorRepair(this.strokes);

  final StrokeRepository strokes;

  late final ConnectorQueries _queries = ConnectorQueries(strokes.db);

  /// Repairs the lines on the surfaces whose strokes [changes] (applied
  /// from other devices) touched, adding what it changed to [changes]
  /// (open editors refresh it). Returns how many lines were repaired.
  ///
  /// Only the lines a change can have left off their shapes are read: the
  /// changed ones and those attached to changed shapes
  /// ([ConnectorQueries.touchedBy]; nothing when only ink changed). Where
  /// the changes are not named (too many), every line on the surface.
  int repair(RemoteChanges changes) {
    if (changes.strokeSurfaces.isEmpty) return 0;
    SurfaceModel.flushAll(); // Reads must see every edit.
    var repaired = 0;
    for (final surface in changes.strokeSurfaces.toList()) {
      final ids = changes.itemsOf(surface);
      final (:shapes, :lines) = ids == null
          ? _queries.all(surface)
          : _queries.touchedBy(surface, ids);
      final fixes = repairsOn(shapes, lines: lines);
      if (fixes.isEmpty) continue;
      strokes.database.transaction(() {
        strokes.delete([for (final (line, _) in fixes) line.id]);
        // Written by another device's repair already (live or since edited).
        strokes.save([
          for (final (_, fixed) in fixes)
            if (!strokes.queries.knowsStroke(fixed.id)) fixed,
        ]);
      });
      for (final (line, fixed) in fixes) {
        changes
          ..addItem(surface, line.id)
          ..addItem(surface, fixed.id);
      }
      repaired += fixes.length;
    }
    return repaired;
  }

  /// The [lines] (by default all of the [shapes] of one surface) with an
  /// end off the shape it is attached to among [shapes], each with its
  /// repair. [shapes] must hold every stroke of each shape the lines name.
  static List<(Stroke, Stroke)> repairsOn(List<Stroke> shapes, {List<Stroke>? lines}) {
    final named = <String, List<Stroke>>{};
    for (final s in shapes) {
      (named[s.shapeId] ??= []).add(s);
    }
    final out = <(Stroke, Stroke)>[];
    for (final line in lines ?? shapes) {
      final shape = line.shape!;
      if (!shape.isAttached) continue;
      Stroke? target(int end) {
        final a = shape.attachmentOf(end);
        return a == null ? null : Connectors.targetOf(shape, end, named[a.id] ?? const []);
      }

      final tail = target(0), tip = target(1);
      bool off(int end, Stroke? t) => t != null && !Connectors.sits(shape, end, t.shape);
      if (!off(0, tail) && !off(1, tip)) continue;
      // Each end onto the stroke picked for it (two ends on one shape
      // name the same pick).
      var followed = shape;
      for (final (end, t) in [(0, tail), (1, tip)]) {
        if (!off(end, t)) continue;
        final a = shape.attachmentOf(end)!;
        followed = Connectors.follow(followed, {a.id: t!.shape!});
      }
      out.add((line, Connectors.rebuilt(line, followed, id: idOf(line, tail, tip))));
    }
    return out;
  }

  static const _uuid = Uuid();

  /// A fixed namespace for repaired lines' ids (UUID v5).
  static const _namespace = '6f1c2b0e-4f5d-5c8a-9a37-2d8e1c4b7a10';

  /// The id of [line] repaired onto [tail] and [tip] (the strokes its ends
  /// are attached to): the same on every device.
  static String idOf(Stroke line, Stroke? tail, Stroke? tip) =>
      _uuid.v5(_namespace, '${line.id}>${tail?.id ?? ''}|${tip?.id ?? ''}');
}
