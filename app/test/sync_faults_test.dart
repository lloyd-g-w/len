import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/sync/background_pull_worker.dart';
import 'package:len/sync/pull_applier.dart';
import 'package:len/sync/sync_engine.dart';
import 'package:len_sync_server/len_sync_server.dart' show BlobGc;

import 'support/fault_devices.dart';
import 'support/faulty_network.dart';
import 'support/random_edits.dart';
import 'support/real_server.dart';
import 'support/sync_checks.dart';
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
  RandomEdits.backups.clear();
  final server = RealServer()..maxPage = r.nextInt(3) == 0 ? null : 2 + r.nextInt(15);
  final network = FaultyNetwork(server, r);
  final faultRate = const [0.15, 0.3, 0.5][seed % 3];
  final time = SharedTime();
  final devices = [
    for (var i = 0; i < deviceCount; i++)
      await FaultDevice.start(network, time, 'abcdefg'[i], skew: _skew(r)),
  ];
  final reference = <FaultDevice>[];
  final ledger = SyncLedger();
  var serverGcRuns = 0;
  // LEN_FAULT_TRACE=<table/id>: prints that row on each device as it changes.
  final trace = Platform.environment['LEN_FAULT_TRACE']?.split('/');
  final traced = <String, String>{};
  void traceRow(int step, int roll) {
    if (trace == null) return;
    for (final d in devices) {
      if (!d.alive) continue;
      final rows = d.s.database.db.select(
        'SELECT updated_at, device_id, deleted, dirty FROM ${trace[0]} WHERE id = ?',
        [trace[1]],
      );
      final now = rows.isEmpty ? '-' : rows.single.values.join(' ');
      if (traced[d.prefix] == now) continue;
      traced[d.prefix] = now;
      debugPrint('step $step ${d.prefix}: $now (${RandomEdits.lastEdit})');
    }
  }

  try {
    for (var step = 0; step < steps; step++) {
      if (step > 0) traceRow(step - 1, -1);
      time.now += r.nextInt(3000);
      final d = devices[r.nextInt(devices.length)];
      final roll = r.nextInt(100);
      if (roll < 52) {
        final s = d.app;
        final before = SyncLedger.snapshot(s);
        try {
          RandomEdits.lastEdit = '';
          await RandomEdits(s, r).any();
        } on StateError {
          // Killed while a backup fetched files: the edit stopped with it.
          if (d.alive && identical(s, d.s)) rethrow;
          continue;
        }
        // Killed while fetching files (a version restored): the edit stopped.
        if (!d.alive || !identical(s, d.s)) continue;
        ledger.record(before, s);
      } else if (roll < 88) {
        // Some syncs see a good network, so more get through to the end.
        network.rate = r.nextInt(3) == 0 ? 0 : faultRate;
        SyncEngine.workerFromBytes = r.nextBool() ? 0 : 64 * 1024;
        BackgroundPullWorker.debugOnServe = r.nextInt(6) == 0 ? _dieAfter(r.nextInt(20000)) : null;
        RandomEdits.lastEdit = 'sync ${d.prefix}';
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
      } else if (roll < 97) {
        server.restart();
      } else if (roll < 98) {
        // The server collects blobs no live record references (as if a
        // month passed since the last run: no grace).
        serverGcRuns++;
        BlobGc(
          server.store,
          server.blobs,
        ).run(now: DateTime.now().add(Duration(days: 31 * serverGcRuns)));
      } else if (roll < 99) {
        // A week passes; the device collects its unreferenced blobs.
        time.now += const Duration(days: 8).inMilliseconds;
        await _collect(d, ledger);
      } else {
        await _collect(d, ledger);
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
      if (devices.every((d) => cleanDevice(d) && jsonEncode(syncedState(d.s)) == first)) break;
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
    if (trace != null) {
      for (final d in [...devices, ref]) {
        for (final row in d.s.database.db.select('SELECT * FROM ${trace[0]} WHERE id = ?', [
          trace[1],
        ])) {
          final m = {...row}..remove('points');
          debugPrint('end ${d.prefix}: $m');
          final surface = row['surface_id'];
          for (final t in ['pages', 'notebooks']) {
            for (final p in d.s.database.db.select(
              'SELECT id, updated_at, device_id, deleted FROM $t WHERE id = ?',
              [surface],
            )) {
              debugPrint('  $t: $p');
            }
          }
        }
      }
    }
    return await syncProblems(server, [...devices, ref], ledger);
  } finally {
    for (final d in [...devices, ...reference]) {
      d.dispose();
    }
    server.dispose();
  }
}

/// Runs [d]'s blob garbage collection, which first thins version
/// histories (deletions the device makes knowingly).
Future<void> _collect(FaultDevice d, SyncLedger ledger) async {
  final s = d.app;
  final before = SyncLedger.snapshot(s);
  await s.blobGc.run();
  if (d.alive && identical(s, d.s)) ledger.record(before, s);
}

/// What a run did, to tune the mix of steps.
String _stats(FaultyNetwork network, List<FaultDevice> devices, FaultDevice ref) {
  int live(String table) =>
      ref.s.database.db.select('SELECT COUNT(*) AS n FROM $table WHERE deleted = 0').single['n']
          as int;
  return '${network.requests} requests ${network.kinds}, faults ${network.counts}, '
      'server restarts ${network.server.restarts}, app runs ${[for (final d in devices) d.runs]}, '
      'live rows ${{for (final t in syncedTables) t: live(t)}}';
}

int _skew(math.Random r) => switch (r.nextInt(4)) {
  0 => 0,
  1 => r.nextInt(2000) - 1000,
  2 => r.nextInt(600000) - 300000,
  _ => r.nextInt(7 * 24 * 3600000) - 3 * 24 * 3600000,
};

void main() {
  setUp(() => PullApplier.debugSliceRecords = 7);
  tearDown(() {
    PullApplier.debugSliceRecords = null;
    BackgroundPullWorker.debugOnServe = null;
    SyncEngine.workerFromBytes = 64 * 1024;
  });

  final runs = int.tryParse(Platform.environment['LEN_FAULT_RUNS'] ?? '') ?? 8;
  test('devices converge under faults and lose nothing', () async {
    final seed = int.tryParse(Platform.environment['LEN_FAULT_SEED'] ?? '') ?? 1;
    for (var run = 0; run < runs; run++) {
      // LEN_FAULT_REPEAT=1: the same seed every run (timing still varies).
      final at = Platform.environment['LEN_FAULT_REPEAT'] == null ? seed + run : seed;
      final problems = await _run(at, deviceCount: 2 + at % 3);
      if (problems.isNotEmpty) {
        fail('Seed $at: ${problems.length} problems:\n${problems.take(40).join('\n')}');
      }
    }
  }, timeout: Timeout(Duration(minutes: 5 + runs ~/ 4)));
}
