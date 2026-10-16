import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/sync/background_pull_worker.dart';
import 'package:len/sync/pull_applier.dart';
import 'package:len/sync/sync_controller.dart';
import 'package:len/sync/sync_engine.dart';

import 'support/fault_devices.dart';
import 'support/faulty_network.dart';
import 'support/random_edits.dart';
import 'support/real_server.dart';
import 'support/sync_ledger.dart';

// Sync under a bad network and failures, against the real server
// (`server/`): devices edit at random while requests are delayed, dropped
// (before, while sending, the answer lost or broken off), duplicated,
// truncated and answered 5xx / 429, the server restarts, clocks are skewed
// and jump, apps are killed mid-sync and pull workers die. After a final
// clean sync every device must hold what a fresh device pulls from the
// server, with nothing lost (docs/SYNC_PROTOCOL.md: last-write-wins and
// "Deletion conflicts"), no unpushed rows, every referenced file on the
// server and no sync left "syncing".
//
// Seeded: LEN_FAULT_SEED=<n> starts at another seed, LEN_FAULT_RUNS=<n>
// runs more (or fewer) scenarios, LEN_FAULT_STATS=1 prints what each did.
// (Timing still varies: latency, isolates and kills are real.)

/// A worker isolate that dies [afterUs] µs after it starts (between two
/// turns of its event loop: while it waits, or between slices).
void Function() _dieAfter(int afterUs) =>
    () => Timer(Duration(microseconds: afterUs), () => Isolate.current.kill());

/// One run: [steps] random edits, syncs and failures on [deviceCount]
/// devices, then a clean sync of all; returns what went wrong.
Future<List<String>> _run(int seed, {int deviceCount = 3, int steps = 300}) async {
  final r = math.Random(seed);
  final server = RealServer();
  final network = FaultyNetwork(server, r)..rate = const [0.15, 0.3, 0.5][seed % 3];
  final time = SharedTime();
  final devices = [
    for (var i = 0; i < deviceCount; i++)
      await FaultDevice.start(network, time, 'abcdefg'[i], skew: _skew(r)),
  ];
  final reference = <FaultDevice>[];
  final ledger = SyncLedger();
  try {
    for (var step = 0; step < steps; step++) {
      time.now += r.nextInt(3000);
      final d = devices[r.nextInt(devices.length)];
      final roll = r.nextInt(100);
      if (roll < 52) {
        final s = d.app;
        final before = SyncLedger.snapshot(s);
        await RandomEdits(s, r).any();
        ledger.record(before, s);
      } else if (roll < 88) {
        SyncEngine.workerFromBytes = r.nextBool() ? 0 : 64 * 1024;
        BackgroundPullWorker.debugOnServe = r.nextInt(6) == 0 ? _dieAfter(r.nextInt(20000)) : null;
        await d.sync(killAfter: roll >= 84 ? Duration(microseconds: r.nextInt(30000)) : null);
      } else if (roll < 90) {
        // Shows something whose file is elsewhere: fetched over the faulty
        // network (a failure leaves it to the next time).
        final s = d.app;
        final missing = [
          for (final sha in s.sync.engine.blobReferences.all())
            if (!await s.blobs.has(sha)) sha,
        ];
        if (missing.isNotEmpty) await s.sync.fetchBlob(missing[r.nextInt(missing.length)]);
      } else if (roll < 92) {
        d.restart();
      } else if (roll < 95) {
        // The clock jumps (forwards or back) by up to an hour.
        d.clock.skew += r.nextInt(7200000) - 3600000;
      } else {
        server.restart();
      }
    }

    // A clean network: every device syncs until all agree.
    network.rate = 0;
    BackgroundPullWorker.debugOnServe = null;
    SyncEngine.workerFromBytes = 64 * 1024;
    for (var round = 0; round < 6; round++) {
      for (final d in devices) {
        time.now += 10;
        await d.sync();
      }
      final first = jsonEncode(syncedState(devices.first.s));
      if (devices.every((d) => _clean(d) && jsonEncode(syncedState(d.s)) == first)) break;
    }
    // What the server holds, as a new device sees it.
    final ref = await FaultDevice.start(network, time, 'z');
    reference.add(ref);
    await ref.sync();
    // One more round, which finds nothing to do (a device that pushed what
    // its last pull revived has not pulled its own echo yet).
    for (final d in devices) {
      await d.sync();
    }
    if (Platform.environment['LEN_FAULT_STATS'] != null) {
      debugPrint('seed $seed: ${_stats(network, devices, ref)}');
    }
    return await _problems(server, [...devices, ref], ledger);
  } finally {
    for (final d in [...devices, ...reference]) {
      d.dispose();
    }
    server.dispose();
  }
}

/// What a run did, to tune the mix of steps.
String _stats(FaultyNetwork network, List<FaultDevice> devices, FaultDevice ref) {
  int live(String table) =>
      ref.s.database.db.select('SELECT COUNT(*) AS n FROM $table WHERE deleted = 0').single['n']
          as int;
  return '${network.requests} requests, faults ${network.counts}, '
      'server restarts ${network.server.restarts}, app runs ${[for (final d in devices) d.runs]}, '
      'live rows ${{for (final t in syncedTables) t: live(t)}}';
}

int _skew(math.Random r) => switch (r.nextInt(4)) {
  0 => 0,
  1 => r.nextInt(2000) - 1000,
  2 => r.nextInt(600000) - 300000,
  _ => r.nextInt(7 * 24 * 3600000) - 3 * 24 * 3600000,
};

bool _clean(FaultDevice d) => d.s.sync.engine.stores.every((st) => st.dirtyRecords(1).isEmpty);

/// Everything wrong with the converged devices (the last is the reference).
Future<List<String>> _problems(
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
    if (!_clean(d)) out.add('$name: unpushed rows');
    if (s.settings.syncLastSeq != seq) {
      out.add(
        '$name: pulled up to ${s.settings.syncLastSeq} of $seq: '
        '${[for (final r in server.records())
          if (r.seq! > s.settings.syncLastSeq) '${r.collection}/${r.id}@${r.updatedAt}/${r.deviceId}${r.deleted ? ' deleted' : ''}']}',
      );
    }
    if (d != ref) out.addAll(_diff(name, syncedState(s), expected));
  }
  out.addAll(ledger.losses(ref.s).map((loss) => 'lost $loss'));
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

void main() {
  setUp(() => PullApplier.debugSliceRecords = 7);
  tearDown(() {
    PullApplier.debugSliceRecords = null;
    BackgroundPullWorker.debugOnServe = null;
    SyncEngine.workerFromBytes = 64 * 1024;
  });

  test('devices converge under faults and lose nothing', () async {
    final runs = int.tryParse(Platform.environment['LEN_FAULT_RUNS'] ?? '') ?? 8;
    final seed = int.tryParse(Platform.environment['LEN_FAULT_SEED'] ?? '') ?? 1;
    for (var run = 0; run < runs; run++) {
      final problems = await _run(seed + run, deviceCount: 2 + (seed + run) % 3);
      if (problems.isNotEmpty) {
        fail('Seed ${seed + run}: ${problems.length} problems:\n${problems.take(40).join('\n')}');
      }
    }
  }, timeout: const Timeout(Duration(minutes: 5)));
}
