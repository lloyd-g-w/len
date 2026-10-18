import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:len/data/versions/versions.dart';
import 'package:len/sync/sync_controller.dart';

import 'fault_devices.dart';
import 'real_server.dart';
import 'sync_ledger.dart';

/// What sync property tests check once devices settled: they agree with
/// a fresh device's copy of the server, lost nothing ([SyncLedger]), and
/// every file and version is to be had.

/// Whether [d] has nothing left to push.
bool cleanDevice(FaultDevice d) => d.s.sync.engine.stores.every((st) => st.dirtyRecords(1).isEmpty);

/// Everything wrong with the converged devices (the last is the reference).
Future<List<String>> syncProblems(
  RealServer server,
  List<FaultDevice> devices,
  SyncLedger ledger,
) async {
  final out = <String>[];
  final ref = devices.last;
  final expected = syncedState(ref.s);
  final seq = server.store.currentSeq();
  for (final d in devices) {
    final s = d.s;
    final name = d.prefix;
    out.addAll(d.stuck.map((run) => '$run: left "syncing"'));
    if (s.sync.state != SyncState.idle) {
      out.add('$name: sync ${s.sync.state.name}: ${s.sync.lastError} ${s.sync.lastErrorDetails}');
    }
    if (!cleanDevice(d)) out.add('$name: unpushed rows');
    if (s.settings.syncLastSeq != seq) {
      out.add(
        '$name: pulled up to ${s.settings.syncLastSeq} of $seq: '
        '${[for (final r in server.records())
          if (r.seq! > s.settings.syncLastSeq) '${r.collection}/${r.id}@${r.updatedAt}/${r.deviceId}${r.deleted ? ' deleted' : ''}']}',
      );
    }
    if (d != ref) out.addAll(_diff(name, syncedState(s), expected));
  }
  out.addAll(
    ledger.losses(ref.s, witnesses: [for (final d in devices) d.s]).map((loss) => 'lost $loss'),
  );
  // Every file a live row references is on the server, intact, and every
  // device has it or can fetch it.
  for (final sha in ref.s.sync.engine.blobReferences.all()) {
    final path = server.blobs.pathFor(sha);
    if (!File(path).existsSync()) {
      out.add('blob $sha is not on the server');
      continue;
    }
    if (sha256.convert(File(path).readAsBytesSync()).toString() != sha) {
      out.add('blob $sha is damaged on the server');
    }
    for (final d in devices) {
      if (!await d.s.blobs.has(sha) && !await d.s.sync.fetchBlob(sha)) {
        out.add('${d.prefix}: cannot get blob $sha');
      } else if (sha256.convert((await d.s.blobs.read(sha))!).toString() != sha) {
        out.add('${d.prefix}: blob $sha is damaged');
      }
    }
  }
  // No live content on a surface that is not there (no page or canvas of
  // that id) or deleted.
  for (final table in ['strokes', 'elements']) {
    for (final row in ref.s.database.db.select('''
      SELECT id, surface_id FROM $table t WHERE deleted = 0
        AND NOT EXISTS (SELECT 1 FROM pages WHERE id = t.surface_id AND deleted = 0)
        AND NOT EXISTS (SELECT 1 FROM notebooks WHERE id = t.surface_id AND deleted = 0)''')) {
      out.add('$table/${row['id']}: live on missing or deleted surface ${row['surface_id']}');
    }
  }
  // Every live version can be read whole (its table blobs and packs to be
  // had) on every device.
  for (final d in devices) {
    final versions = d.s.versions;
    for (final row in d.s.database.db.select('SELECT id FROM versions WHERE deleted = 0')) {
      final version = versions.store.get(row['id'] as String);
      if (version == null) {
        out.add('${d.prefix}: version ${row['id']} is malformed');
        continue;
      }
      try {
        final body = await versions.content.body(version);
        await versions.content.ensure([for (final p in body.pages) p.content, ?body.canvas]);
      } on VersionUnavailable catch (e) {
        out.add('${d.prefix}: version ${version.id} unavailable: $e');
      }
    }
  }
  return out;
}

/// The differences between [actual] and [expected] (states of
/// [syncedState]), row by row.
List<String> _diff(String name, Map<String, Object?> actual, Map<String, Object?> expected) {
  final out = <String>[];
  for (final table in expected.keys) {
    final a = actual[table], e = expected[table];
    if (jsonEncode(a) == jsonEncode(e)) continue;
    if (a is Map && e is Map) {
      for (final id in {...a.keys, ...e.keys}) {
        if (jsonEncode(a[id]) != jsonEncode(e[id])) {
          out.add('$name: $table/$id is ${jsonEncode(a[id])}, server ${jsonEncode(e[id])}');
        }
      }
    } else {
      out.add('$name: $table differs');
    }
  }
  return out;
}
