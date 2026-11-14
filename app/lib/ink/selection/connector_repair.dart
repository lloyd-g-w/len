import 'dart:convert';

import 'package:crypto/crypto.dart';

import '../../data/connector_queries.dart';
import '../../data/stroke_repository.dart';
import '../../domain/shaped.dart';
import '../../domain/stroke.dart';
import '../../sync/remote_changes.dart';
import '../surface_model.dart';
import 'connectors.dart';
import 'shape_merge.dart';

/// Brings connectors back onto their shapes, and merges a shape's edits
/// made at once on several devices, after a sync (see [Connectors],
/// [ShapeMerge]); and after an undo or redo, which can bring back a line
/// whose shape moved since, or a stroke of a shape edited since.
///
/// An edit of a shape moves the lines attached to it in the same change,
/// so one device alone never leaves an end off its shape. Two devices
/// editing at once can: one moves the box (and its arrow), the other
/// recolours the arrow, and the recoloured arrow still lies where the box
/// was. Both replaced the same arrow, so it now has two live strokes
/// ("twins"). Every device that applies other devices' changes looks at
/// the surfaces they touched, merges each shape's twins into one stroke
/// carrying both edits ([ShapeMerge]), and replaces each line with an end
/// off the shape it names by one whose ends lie on it ([Connectors.follow]),
/// as a local edit (synced, not undoable: nobody made it here).
///
/// A merge's id is made from the twins' ids ([mergeIdOf]) and a repair's
/// from the line's and its targets' ids ([idOf]), and their geometry from
/// theirs alone, so devices doing it at once write the same stroke (one
/// record, not two arrows); a merge leaves one stroke of its shape and a
/// repaired line sits on its shapes: nothing does it again.
class ConnectorRepair {
  ConnectorRepair(this.strokes);

  final StrokeRepository strokes;

  late final ConnectorQueries _queries = ConnectorQueries(strokes.database);

  /// Repairs the lines on the surfaces whose strokes [changes] (applied
  /// from other devices) touched, adding what it changed to [changes]
  /// (open editors refresh it). Returns how many strokes it wrote
  /// (merges and repairs) on each surface, else how many it removed
  /// (versions superseded, [ShapeMerge.staleIn]).
  ///
  /// Only the strokes a change can have left apart are read: the changed
  /// shapes' strokes, the changed lines and those attached to changed
  /// shapes ([ConnectorQueries.touchedBy]; nothing when only ink
  /// changed). Where the changes are not named (too many), every shape on
  /// the surface.
  int repair(RemoteChanges changes) {
    if (changes.strokeSurfaces.isEmpty) return 0;
    SurfaceModel.flushAll(); // Reads must see every edit.
    var repaired = 0;
    for (final surface in changes.strokeSurfaces.toList()) {
      final (:removed, :added) = fixesFor(surface, changes.itemsOf(surface));
      if (added.isEmpty && removed.isEmpty) continue;
      strokes.database.transaction(() {
        strokes.delete([for (final s in removed) s.id]);
        // Written by another device already (one record); a known one
        // deleted since is written again: what it replaced came back.
        strokes.save([
          for (final s in added)
            if (!strokes.queries.hasLiveStroke(s.id)) s,
        ]);
      });
      for (final s in [...removed, ...added]) {
        changes.addItem(surface, s.id);
      }
      repaired += added.isEmpty ? removed.length : added.length;
    }
    return repaired;
  }

  /// What brings the strokes on [surface] that a change to [changed] (all
  /// of them: null) can have left apart back together, as stored: the
  /// strokes to remove (twins merged, lines repaired) and those replacing
  /// them (merges, repaired lines). Nothing is written.
  ({List<Stroke> removed, List<Stroke> added}) fixesFor(String surface, Iterable<String>? changed) {
    final read = changed == null ? _queries.all(surface) : _queries.touchedBy(surface, changed);
    final removed = <String, Stroke>{};
    final merged = _merge(surface, read.edited, removed);
    final shapes = <Shaped>[
      for (final s in read.shapes)
        if (!removed.containsKey(s.id)) s,
      ...merged.values,
    ];
    final lines = <Shaped>[
      for (final s in read.lines)
        if (!removed.containsKey(s.id)) s,
      for (final m in merged.values)
        if (m.shape!.isAttached) m,
    ];
    final found = fixesOn(shapes, lines: lines);
    // Only the lines repaired are read whole (their points).
    final read2 = {
      for (final s in strokes.queries.strokesByIds(surface, [
        for (final (line, _, _) in found)
          if (!merged.containsKey(line.id)) line.id,
      ]))
        s.id: s,
    };
    final added = <Stroke>[];
    for (final (line, shape, id) in found) {
      // A merged line repaired is written repaired only.
      final stroke = merged.remove(line.id) ?? read2[line.id];
      if (stroke == null) continue;
      if (read2.containsKey(line.id)) removed[line.id] = stroke;
      added.add(Connectors.rebuilt(stroke, shape, id: id));
    }
    return (removed: removed.values.toList(), added: [...merged.values, ...added]);
  }

  /// The twins among [edited] (live strokes of the shapes changed on
  /// [surface]) merged, by the merge's id; the twins go to [removed].
  Map<String, Stroke> _merge(String surface, List<Shaped> edited, Map<String, Stroke> removed) {
    final twins = ShapeMerge.twinsOf(edited);
    if (twins.isEmpty) return {};
    final whole = {
      for (final s in strokes.queries.strokesByIds(surface, [
        for (final group in twins)
          for (final t in group) t.id,
      ]))
        s.id: s,
    };
    final groups = <List<Stroke>>[];
    for (final group in twins) {
      final read = [for (final t in group) ?whole[t.id]];
      // Versions another one replaced are gone: no merge needs them.
      final stale = ShapeMerge.staleIn(read);
      for (final s in read) {
        if (stale.contains(s.id)) removed[s.id] = s;
      }
      read.removeWhere((s) => stale.contains(s.id));
      if (read.length > 1) groups.add(read);
    }
    final bases = _queries.versions({for (final group in groups) ?ShapeMerge.baseOf(group)});
    final out = <String, Stroke>{};
    for (final group in groups) {
      final base = ShapeMerge.baseOf(group);
      final m = ShapeMerge.merged(group, bases[base], id: mergeIdOf(group));
      for (final s in group) {
        removed[s.id] = s;
      }
      out[m.id] = m;
    }
    return out;
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
  static String idOf(Shaped line, Shaped? tail, Shaped? tip) =>
      _uuidOf('${line.id}>${tail?.id ?? ''}|${tip?.id ?? ''}');

  /// The id of the merge of [twins] (strokes of one shape, in id order):
  /// the same on every device.
  static String mergeIdOf(List<Shaped> twins) =>
      _uuidOf('merge:${[for (final t in twins) t.id].join('+')}');

  static String _uuidOf(String name) {
    final bytes = sha1.convert([..._namespaceBytes, ...utf8.encode(name)]).bytes.sublist(0, 16);
    bytes[6] = (bytes[6] & 0x0f) | 0x50;
    bytes[8] = (bytes[8] & 0x3f) | 0x80;
    final hex = [for (final b in bytes) b.toRadixString(16).padLeft(2, '0')].join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-'
        '${hex.substring(16, 20)}-${hex.substring(20)}';
  }
}
