import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../data/connector_queries.dart';
import '../../data/stroke_repository.dart';
import '../../domain/shaped.dart';
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

  late final ConnectorQueries _queries = ConnectorQueries(strokes.database);

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
      final found = fixesOn(shapes, lines: lines);
      if (found.isEmpty) continue;
      // Only the lines repaired are read whole (their points).
      final read = {
        for (final s in strokes.queries.strokesByIds(surface, [
          for (final (line, _, _) in found) line.id,
        ]))
          s.id: s,
      };
      final fixes = [
        for (final (line, shape, id) in found)
          if (read[line.id] case final stroke?) (stroke, Connectors.rebuilt(stroke, shape, id: id)),
      ];
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
  static List<(Stroke, Stroke)> repairsOn(List<Stroke> shapes, {List<Stroke>? lines}) => [
    for (final (line, shape, id) in fixesOn(shapes, lines: lines))
      (line, Connectors.rebuilt(line, shape, id: id)),
  ];

  /// What [repairsOn] finds, without rebuilding the lines: each line to
  /// repair, the shape it is repaired to and the repair's id.
  static List<(T, ShapeGeometry, String)> fixesOn<T extends Shaped>(
    List<T> shapes, {
    List<T>? lines,
  }) {
    final named = <String, List<T>>{};
    for (final s in shapes) {
      (named[s.shapeId] ??= []).add(s);
    }
    final out = <(T, ShapeGeometry, String)>[];
    for (final line in lines ?? shapes) {
      final shape = line.shape!;
      if (!shape.isAttached) continue;
      T? target(int end) {
        final a = shape.attachmentOf(end);
        return a == null ? null : Connectors.targetOf(shape, end, named[a.id] ?? const []);
      }

      final tail = target(0), tip = target(1);
      bool off(int end, T? t) => t != null && !Connectors.sits(shape, end, t.shape);
      if (!off(0, tail) && !off(1, tip)) continue;
      // Each end onto the stroke picked for it (two ends on one shape
      // name the same pick).
      var followed = shape;
      for (final (end, t) in [(0, tail), (1, tip)]) {
        if (!off(end, t)) continue;
        final a = shape.attachmentOf(end)!;
        followed = Connectors.follow(followed, {a.id: t!.shape!});
      }
      out.add((line, followed, idOf(line, tail, tip)));
    }
    return out;
  }

  /// A fixed namespace for repaired lines' ids (UUID v5).
  static const _namespace = '6f1c2b0e-4f5d-5c8a-9a37-2d8e1c4b7a10';

  static final List<int> _namespaceBytes = [
    for (var i = 0; i < 32; i += 2)
      int.parse(_namespace.replaceAll('-', '').substring(i, i + 2), radix: 16),
  ];

  /// The id of [line] repaired onto [tail] and [tip] (the strokes its ends
  /// are attached to): the same on every device. A UUID v5 (RFC 4122)
  /// made here from SHA-1: the `uuid` package's took 0.3 ms a line, and
  /// 13 ms the first time.
  static String idOf(Shaped line, Shaped? tail, Shaped? tip) {
    final name = '${line.id}>${tail?.id ?? ''}|${tip?.id ?? ''}';
    final bytes = sha1.convert([..._namespaceBytes, ...utf8.encode(name)]).bytes.sublist(0, 16);
    bytes[6] = (bytes[6] & 0x0f) | 0x50;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
