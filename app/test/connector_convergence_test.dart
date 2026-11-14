import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/ink/selection/connector_repair.dart';
import 'package:len/ink/shapes/shape_anchors.dart';
import 'package:len/ink/surface_model.dart';
import 'package:len/sync/remote_changes.dart';

import 'support/connector_devices.dart';

// Property: whatever three devices do to a box and its arrows at once
// (move, recolour, delete, draw, undo, redo), syncing in any order, they
// end up holding the same strokes: one per shape, every attached end on
// its shape, nothing left to push, and no undo step nobody made. One of
// them may run the protocol before lineages and merges (`sh.r`,
// `ShapeMerge`): it writes no lineage and only repairs.

void main() {
  for (var seed = 0; seed < 24; seed++) {
    final old = seed.isOdd;
    test('seed $seed${old ? ', with an old client' : ''}', () async {
      final devices = await connectorDevices(3);
      if (old) _runOldProtocol(devices.last);
      final random = Random(seed);
      final log = <String>[];
      for (var step = 0; step < 16; step++) {
        final i = random.nextInt(devices.length);
        final d = devices[i];
        final what = _step(d, random, undoable: !(old && d == devices.last));
        log.add('${'abc'[i]}: $what');
        if (old && d == devices.last) _dropLineages(d);
      }
      await _settle(devices, log);
      for (final d in devices) {
        expectOneStrokeEach(d);
        expectConnected(d);
        expect(_contents(d), _contents(devices.first), reason: log.join('\n'));
        // The editor shows what is stored.
        for (final s in d.stored) {
          expect(d.model.strokeById(s.id), isNotNull, reason: '${s.id}\n${log.join('\n')}');
        }
      }
    });
  }
}

/// One random edit (or sync) on [d]; what it was.
String _step(ConnectorDevice d, Random random, {required bool undoable}) {
  Offset offset() => Offset(random.nextInt(9) * 20.0 - 80, random.nextInt(9) * 20.0 - 80);
  final boxes = _shapes(d, closed: true), arrows = _shapes(d, closed: false);
  final roll = random.nextInt(undoable ? 10 : 8);
  switch (roll) {
    case 0 || 1 when boxes.isNotEmpty:
      final box = boxes[random.nextInt(boxes.length)];
      d.edit(() => box, (c) => d.move(offset()));
      return 'move box';
    case 2 when boxes.isNotEmpty:
      final box = boxes[random.nextInt(boxes.length)];
      d.edit(() => box, (c) => c.selection.recolor(0xFF000000 | random.nextInt(0xFFFFFF)));
      return 'recolour box';
    case 3 when arrows.isNotEmpty:
      final arrow = arrows[random.nextInt(arrows.length)];
      d.edit(() => arrow, (c) => c.selection.recolor(0xFF000000 | random.nextInt(0xFFFFFF)));
      return 'recolour arrow';
    case 4 when arrows.isNotEmpty:
      final arrow = arrows[random.nextInt(arrows.length)];
      if (random.nextBool()) {
        d.edit(() => arrow, (c) => c.selection.delete());
        return 'delete arrow';
      }
      d.edit(() => arrow, (c) => d.move(offset())); // Lets go.
      return 'move arrow';
    case 5 when boxes.isNotEmpty:
      final box = boxes[random.nextInt(boxes.length)];
      final at = random.nextInt(8) / 8;
      final tip = ShapeAnchors.pointAt(box.shape!, at);
      d.model.addStroke(
        shapeOn(
          d.s.clock.newId(),
          d.page,
          ShapeGeometry(ShapeKind.arrow, [
            tip + offset(),
            tip,
          ], tip: ShapeAttachment(box.shapeId, at)),
        ),
      );
      d.model.flush();
      return 'draw arrow';
    case 8:
      d.model.undo();
      d.model.flush();
      return 'undo';
    case 9:
      d.model.redo();
      d.model.flush();
      return 'redo';
    default:
      return 'sync';
  }
}

/// [d]'s live boxes ([closed]) or arrows, as its editor holds them.
List<Stroke> _shapes(ConnectorDevice d, {required bool closed}) => [
  for (final s in d.stored)
    if (s.shape!.isClosed == closed) ?d.model.strokeById(s.id),
];

/// Syncs the devices round after round until a round changes nothing
/// (bounded: repairs and merges never loop), and checks no sync added an
/// undo step.
Future<void> _settle(List<ConnectorDevice> devices, List<String> log) async {
  for (var round = 0; ; round++) {
    expect(round, lessThan(6), reason: 'no settling\n${log.join('\n')}');
    var changed = false;
    for (final d in devices) {
      final steps = d.model.history.recorded;
      final changes = await d.sync();
      expect(d.model.history.recorded, steps);
      changed |= changes.strokeSurfaces.isNotEmpty || d.dirty.isNotEmpty;
    }
    if (!changed) return;
  }
}

/// The live strokes on [d]'s page: id, look and shape.
Map<String, String> _contents(ConnectorDevice d) => {
  for (final s in d.stored) s.id: '${s.color} ${s.shape!.toJson()}',
};

/// [d] behaves as a client before lineages and merges: after applying
/// other devices' changes it only repairs lines (as `ConnectorRepair`
/// did), and its own edits name no predecessors ([_dropLineages]).
void _runOldProtocol(ConnectorDevice d) {
  d.s.sync.engine.afterApply = (RemoteChanges changes) {
    if (!changes.strokeSurfaces.contains(d.page)) return;
    SurfaceModel.flushAll();
    final fixes = ConnectorRepair.repairsOn(d.stored);
    if (fixes.isEmpty) return;
    d.s.strokes.delete([for (final (line, _) in fixes) line.id]);
    d.s.strokes.save([
      for (final (_, fixed) in fixes)
        if (!d.s.strokes.queries.hasLiveStroke(fixed.id)) _withoutLineage(fixed),
    ]);
    for (final (line, fixed) in fixes) {
      changes
        ..addItem(d.page, line.id)
        ..addItem(d.page, fixed.id);
    }
  };
}

/// Rewrites what [d] wrote and has not pushed without lineages.
void _dropLineages(ConnectorDevice d) {
  final dirty = {for (final r in d.dirty) r.id};
  final named = [
    for (final s in d.stored)
      if (dirty.contains(s.id) && s.shape!.replaces.isNotEmpty) s,
  ];
  if (named.isEmpty) return;
  d.s.strokes.save([for (final s in named) _withoutLineage(s)]);
  d.model.refreshItems({for (final s in named) s.id});
}

Stroke _withoutLineage(Stroke s) =>
    s.withPoints(s.points, shape: s.shape!.withLineage(s.shape!.origin, const []));
