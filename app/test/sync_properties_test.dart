import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:len/app_services.dart';
import 'package:len/core/clock.dart';
import 'package:len/data/app_database.dart';
import 'package:len/data/stroke_codec.dart';
import 'package:len/data/syncable.dart';
import 'package:len/data/syncable_table.dart';
import 'package:len/domain/notebook.dart';
import 'package:len/domain/paper.dart';
import 'package:len/domain/stroke.dart';

import 'support/fake_server.dart';
import 'support/property.dart';

// Properties of sync merging (docs/SYNC_PROTOCOL.md: "Conflict rule (LWW)",
// "Deletion conflicts"): whatever order or batches devices see changes in,
// they end up in the same state, and no edit is silently lost.

/// Wall-clock time shared by the devices of a run.
class _Time {
  int now = 1000;
}

/// A device clock running [skew] ms off the shared time.
class _Clock extends Clock {
  _Clock(this.time, this.prefix, this.skew);

  final _Time time;
  final String prefix;
  final int skew;
  int _ids = 0;

  @override
  int nowMs() => time.now + skew;

  @override
  String newId() => '$prefix${_ids++}';
}

AppServices _services(Clock clock) {
  final s = AppServices.create(AppDatabase.inMemory(), clock: clock);
  addTearDown(s.dispose);
  return s;
}

const _tables = [
  'folders',
  'templates',
  'notebook_styles',
  'notebooks',
  'pages',
  'outline',
  'strokes',
  'elements',
  'recordings',
  'recognised_text',
];

/// Every synced row (and the stroke chunk index), comparable across
/// devices: without the `dirty` flag, and tombstones without their payload
/// (a device keeps the payload of rows it saw live, by design: see
/// "Payloads are kept for 30 days").
Map<String, Object?> _state(AppServices s) => {
  for (final table in _tables)
    table: {
      for (final row in s.database.db.select('SELECT * FROM $table ORDER BY id'))
        row['id'] as String: row['deleted'] == 1
            ? '${row['updated_at']}/${row['device_id']}/deleted'
            : {
                for (final e in row.entries)
                  if (e.key != 'dirty')
                    e.key: e.value is List<int> ? base64Encode(e.value as List<int>) : e.value,
              },
    },
  'stroke_chunks': [
    for (final r in s.database.db.select(
      'SELECT * FROM stroke_chunks ORDER BY surface_id, cx, cy, stroke_id',
    ))
      '${r['surface_id']}:${r['cx']},${r['cy']}:${r['stroke_id']}',
  ],
};

// -----------------------------------------------------------------------------
// The apply layer: last-writer-wins, order independence, idempotence.

/// A remote change of a folder or a stroke (ids from a small pool, so they
/// collide).
SyncRecord _record(math.Random r) {
  final stroke = r.nextBool();
  final id = '${stroke ? 's' : 'f'}${r.nextInt(3)}';
  final deleted = r.nextDouble() < 0.3;
  Map<String, Object?> data() => stroke
      ? {
          'surfaceId': 'page${r.nextInt(2)}',
          'tool': 'ballpoint',
          'color': r.nextInt(0xFFFFFF),
          'width': 1 + r.nextInt(5),
          'points': base64Encode(
            StrokeCodec.encode([
              for (var i = 1 + r.nextInt(4); i > 0; i--)
                StrokePoint(r.nextDouble() * 2000 - 1000, r.nextDouble() * 2000, r.nextDouble()),
            ]),
          ),
          'createdAt': r.nextInt(100),
          'style': StrokeStyle.defaultsFor(InkTool.ballpoint).toJson(),
        }
      : {'name': 'n${r.nextInt(1000)}', 'parentId': null, 'color': r.nextInt(8), 'createdAt': 1};
  return SyncRecord(
    collection: stroke ? 'strokes' : 'folders',
    id: id,
    updatedAt: 1 + r.nextInt(4),
    deviceId: ['a', 'b', 'c'][r.nextInt(3)],
    deleted: deleted,
    data: deleted ? null : data(),
  );
}

/// Records with distinct versions per row: one device never writes two
/// versions of a row with the same `updatedAt` (see "Local versions").
Gen<List<SyncRecord>> _records = (r) {
  final seen = <String>{};
  return [
    for (final rec in Gens.listOf(_record, Gens.intIn(1, 14))(r))
      if (seen.add('${rec.collection}/${rec.id}@${rec.updatedAt}/${rec.deviceId}')) rec,
  ];
};

String _show(List<SyncRecord> records) => records
    .map((r) => '${r.collection}/${r.id}@${r.updatedAt}/${r.deviceId}${r.deleted ? ' ✝' : ''}')
    .join('\n');

void _applyAll(AppServices s, List<SyncRecord> records) {
  final stores = {for (final st in s.sync.engine.stores) st.collection: st};
  s.database.transaction(() {
    for (final rec in records) {
      stores[rec.collection]!.applyRemote(rec);
    }
  });
}

/// The last writer of each row: highest `updatedAt`, then device id.
Map<String, SyncRecord> _winners(List<SyncRecord> records) {
  final winners = <String, SyncRecord>{};
  for (final rec in records) {
    final key = '${rec.collection}/${rec.id}';
    final w = winners[key];
    if (w == null || rec.supersedes(updatedAt: w.updatedAt, deviceId: w.deviceId)) {
      winners[key] = rec;
    }
  }
  return winners;
}

// -----------------------------------------------------------------------------
// Whole devices: random edits and deletions, random sync order.

class _Device {
  _Device(_Time time, String prefix, int skew) : s = _services(_Clock(time, prefix, skew));

  final AppServices s;

  List<String> ids(String sql, [List<Object?> args = const []]) => [
    for (final row in s.database.db.select(sql, args)) row['id'] as String,
  ];

  List<String> get notebooks => ids('SELECT id FROM notebooks WHERE deleted = 0 ORDER BY id');
  List<String> get pages => ids('SELECT id FROM pages WHERE deleted = 0 ORDER BY id');
  List<String> strokesOn(List<String> surfaces) => ids(
    'SELECT id FROM strokes WHERE deleted = 0 AND surface_id IN '
    '(${List.filled(surfaces.length, '?').join(',')}) ORDER BY id',
    surfaces,
  );
  bool get clean => s.sync.engine.stores.every((st) => st.dirtyRecords(1).isEmpty);
}

/// One step of a scenario: an edit on a device, or a sync of one.
typedef _Step = ({int device, int op, int pick, int ms});

Gen<({List<int> skews, List<_Step> steps})> _scenario = (r) => (
  skews: [for (var i = 0; i < 3; i++) r.nextInt(41) - 20],
  steps: [
    for (var i = 8 + r.nextInt(25); i > 0; i--)
      (device: r.nextInt(3), op: r.nextInt(8), pick: r.nextInt(1 << 20), ms: r.nextInt(15)),
  ],
);

/// Runs [steps] on three devices of one server, then syncs them until
/// they settle. Returns the devices and strokes no device deleted knowing
/// them (which must survive).
Future<(List<_Device>, Set<String>)> _run(List<int> skews, List<_Step> steps) async {
  final time = _Time();
  final server = FakeServer();
  final devices = [for (var i = 0; i < 3; i++) _Device(time, 'abc'[i], skews[i])];
  final written = <String>{}, knowinglyDeleted = <String>{};
  var strokeNo = 0;
  T pick<T>(List<T> from, int n) => from[n % from.length];
  for (final step in steps) {
    time.now += step.ms;
    final d = devices[step.device];
    final s = d.s;
    final notebooks = d.notebooks, pages = d.pages;
    switch (step.op) {
      case 0 || 1 when notebooks.isEmpty || step.op == 0 && step.pick.isEven:
        s.notebooks.create(
          title: 'n',
          kind: NotebookKind.paged,
          paper: PaperStyle.blank,
          coverColor: 0,
        );
      case 0 || 1:
        s.pages.addPage(pick(notebooks, step.pick));
      case 2 || 3 when pages.isNotEmpty:
        final page = pick(pages, step.pick);
        final id = 'k${step.device}_${strokeNo++}';
        s.strokes.save([bigStroke(id, page, 1 + step.pick % 5)]);
        s.notebooks.touch(s.pages.notebookOf(page)!);
        written.add(id);
      case 4 when pages.isNotEmpty:
        final strokes = d.strokesOn(pages);
        if (strokes.isEmpty) break;
        final id = pick(strokes, step.pick);
        s.strokes.delete([id]);
        knowinglyDeleted.add(id);
      case 5 when pages.isNotEmpty:
        final page = pick(pages, step.pick);
        knowinglyDeleted.addAll(d.strokesOn([page]));
        s.notebooks.deletePage(page);
      case 6 when notebooks.isNotEmpty:
        final nb = pick(notebooks, step.pick);
        if (step.pick.isEven) {
          final n = s.notebooks.get(nb)!;
          s.notebooks.update(n.copyWith(title: 't${step.pick % 97}'));
          break;
        }
        knowinglyDeleted.addAll(d.strokesOn([nb, ...s.pages.pagesOf(nb).map((p) => p.id)]));
        s.notebooks.trash(nb);
        s.notebooks.delete(nb);
      default:
        await s.sync.engine.sync(apiFor(server));
    }
  }
  // Settle: every device syncs, round after round, until all agree and
  // have nothing left to push (a revival seen in the last round is pushed
  // by the device that made it and still has to reach the others).
  for (var round = 0; round < 8; round++) {
    for (final d in devices) {
      time.now += 7;
      await d.s.sync.engine.sync(apiFor(server));
    }
    final state = jsonEncode(_state(devices.first.s));
    if (devices.every((d) => d.clean && jsonEncode(_state(d.s)) == state)) break;
  }
  return (devices, written.difference(knowinglyDeleted));
}

void main() {
  test('applying remote changes keeps the last writer of each row, in any order', () async {
    await forAll(
      _records,
      (records) {
        final r = math.Random(records.length);
        final clock = _Clock(_Time(), 'x', 0);
        final inOrder = _services(clock), shuffled = _services(clock), twice = _services(clock);
        _applyAll(inOrder, records);
        _applyAll(shuffled, Gens.shuffled(records, r));
        // Re-applying any change (an echo, a page pulled again) is a no-op.
        for (var i = 0; i < records.length; i += 1 + r.nextInt(3)) {
          _applyAll(twice, Gens.shuffled(records.sublist(i), r).take(1 + r.nextInt(3)).toList());
        }
        _applyAll(twice, Gens.shuffled([...records, ...records], r));
        final expected = _state(inOrder);
        expect(_state(shuffled), expected);
        expect(_state(twice), expected);

        final stores = {for (final st in inOrder.sync.engine.stores) st.collection: st};
        for (final w in _winners(records).values) {
          final row = inOrder.database.db.select('SELECT * FROM ${w.collection} WHERE id = ?', [
            w.id,
          ]).single;
          expect((row['updated_at'], row['device_id']), (w.updatedAt, w.deviceId));
          expect(row['deleted'] == 1, w.deleted);
          expect(row['dirty'], 0);
          if (w.deleted) continue;
          final data = (stores[w.collection]! as SyncableTable).rowToRecord(row).data!;
          for (final key in w.data!.keys) {
            expect(data[key], w.data![key], reason: key);
          }
        }
      },
      runs: 100,
      describe: _show,
    );
  });

  test('devices editing and deleting concurrently converge and lose no edit', () async {
    await forAll(
      _scenario,
      (scenario) async {
        final (devices, kept) = await _run(scenario.skews, scenario.steps);
        final first = _state(devices.first.s);
        for (final d in devices) {
          expect(d.clean, isTrue, reason: 'unpushed changes left');
          expect(_state(d.s), first);
        }
        // Content written without knowing about a deletion survives it.
        final db = devices.first.s.database.db;
        for (final id in kept) {
          final rows = db.select('SELECT deleted FROM strokes WHERE id = ?', [id]);
          expect(rows.single['deleted'], 0, reason: 'stroke $id was lost');
        }
        // No live content is left on a deleted page or in a deleted notebook.
        expect(
          db.select('''
            SELECT p.id FROM pages p WHERE p.deleted = 1 AND EXISTS
              (SELECT 1 FROM strokes WHERE surface_id = p.id AND deleted = 0)'''),
          isEmpty,
        );
        expect(
          db.select('''
            SELECT n.id FROM notebooks n WHERE n.deleted = 1 AND EXISTS
              (SELECT 1 FROM pages WHERE notebook_id = n.id AND deleted = 0)'''),
          isEmpty,
        );
      },
      runs: 40,
      describe: (s) => 'skews ${s.skews}\n${s.steps.join('\n')}',
    );
  });
}
