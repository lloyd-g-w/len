import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:len/domain/stroke.dart';
import 'package:len/sync/sync_engine.dart';

import 'support/fault_devices.dart';
import 'support/faulty_network.dart';
import 'support/random_edits.dart';
import 'support/real_server.dart';
import 'support/sync_checks.dart';
import 'support/sync_ledger.dart';

// Live sync (`/v1/live`) against the real server in this process, with
// the apps running as they do in the foreground: devices edit at random
// (the edits of the sync faults test: notebooks, ink, text, fonts,
// versions saved and restored, connectors, backups, …, and large edits
// written in steps across turns) while their changes travel over live
// connections and are applied in between; connections are cut, the
// server restarts, apps are killed (mid stepped write, mid restore) and
// sent to the background. After a final sync every device must hold what
// a fresh device pulls from the server and nothing written is lost
// (`syncProblems`).
//
// Seeded: LEN_LIVE_SEED=<n> starts at another seed, LEN_LIVE_RUNS=<n>
// runs more (or fewer). Timing is real, so a seed is not a replay.

/// A large edit as the editor commits one (a drag of many strokes): the
/// strokes of a surface replaced by moved copies, written in steps across
/// turns ([SteppedWrites]).
void _steppedEdit(FaultDevice d, math.Random r) {
  final s = d.s;
  final rows = s.database.db.select(
    'SELECT surface_id, COUNT(*) AS n FROM strokes WHERE deleted = 0 '
    "AND (style IS NULL OR json_extract(style, '\$.sh') IS NULL) "
    'GROUP BY surface_id ORDER BY n DESC, surface_id LIMIT 3',
  );
  if (rows.isEmpty) return;
  final surface = rows[r.nextInt(rows.length)]['surface_id'] as String;
  final strokes = [
    for (final row in s.database.db.select(
      'SELECT id FROM strokes WHERE surface_id = ? AND deleted = 0 '
      "AND (style IS NULL OR json_extract(style, '\$.sh') IS NULL) ORDER BY id",
      [surface],
    ))
      row['id'] as String,
  ];
  final old = s.strokes.queries.strokesByIds(surface, strokes);
  final dx = r.nextDouble() * 40 - 20;
  final moved = [
    for (final x in old)
      x.withPoints([
        for (final p in x.points) StrokePoint(p.x + dx, p.y, p.pressure),
      ], id: s.clock.newId()),
  ];
  // One stroke per step and a slow step: the edit spans turns.
  final steps = s.strokes.editSteps([for (final x in old) x.id], moved);
  s.database.steps.add([
    for (final step in steps)
      () {
        final watch = Stopwatch()..start();
        while (watch.elapsedMicroseconds < 3000) {}
        step();
      },
  ]);
}

/// Waits about [ms] milliseconds of real time (timers, live messages and
/// stepped writes run meanwhile).
Future<void> _pause(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

/// One run: [steps] random edits and failures on [deviceCount] devices
/// connected live, then a final sync of all; returns what went wrong.
/// What each step of the last run did, and when on its device's clock
/// (printed when the run fails).
final _log = <String>[];

Future<List<String>> _run(int seed, {int deviceCount = 3, int steps = 150}) async {
  _log.clear();
  final r = math.Random(seed);
  RandomEdits.backups.clear();
  RandomEdits.fontFiles.clear();
  final server = RealServer();
  final network = FaultyNetwork(server, r)..rate = 0;
  final time = SharedTime();
  final devices = [
    for (var i = 0; i < deviceCount; i++) await FaultDevice.start(network, time, 'abcdefg'[i]),
  ];
  FaultDevice up(FaultDevice d) {
    if (!d.alive) {
      d.app.sync.start();
    }
    return d;
  }

  for (final d in devices) {
    d.s.sync.start();
  }
  final reference = <FaultDevice>[];
  final ledger = SyncLedger();
  // LEN_FAULT_TRACE=<table/id>: prints that row on each device as it changes.
  final trace = Platform.environment['LEN_FAULT_TRACE']?.split('/');
  final traced = <String, String>{};
  var what = '';
  FaultDevice? last;
  void traceRow(int step) {
    if (trace == null) return;
    for (final d in devices) {
      if (!d.alive) continue;
      final rows = d.s.database.db.select(
        'SELECT updated_at, device_id, deleted, dirty '
        'FROM ${trace[0]} WHERE id = ?',
        [trace[1]],
      );
      final now = rows.isEmpty ? '-' : rows.single.values.join(' ');
      if (traced[d.prefix] == now) continue;
      traced[d.prefix] = now;
      debugPrint('step $step ${d.prefix}: $now ($what)');
    }
  }

  try {
    await _pause(50);
    for (var step = 0; step < steps; step++) {
      if (step > 0) {
        traceRow(step - 1);
        _log.add('step ${step - 1} until ${last?.clock.nowMs()}: $what');
      }
      time.now += r.nextInt(2000);
      final d = up(devices[r.nextInt(devices.length)]);
      last = d;
      final roll = r.nextInt(100);
      what = '${d.prefix} roll $roll';
      if (roll < 60) {
        final s = d.s;
        final before = SyncLedger.snapshot(s);
        final edit = RandomEdits(s, r).any();
        // Sometimes killed while it runs (a version restored, a backup).
        final killer = r.nextInt(12) == 0
            ? Timer(Duration(milliseconds: r.nextInt(30)), d.kill)
            : null;
        try {
          await edit;
        } on StateError {
          if (d.alive && identical(s, d.s)) rethrow;
        } finally {
          killer?.cancel();
        }
        what = '${d.prefix} ${RandomEdits.lastEdit}';
        // Killed: what the edit wrote before is kept (the app started
        // again holds it, before it pulls anything).
        final now = d.alive && identical(s, d.s) ? s : up(d).s;
        final after = SyncLedger.snapshot(now);
        final saved = RandomEdits.lastEdit == 'version'
            ? await SyncLedger.savedBeforeRestores(now, before)
            : const <String>{};
        ledger.record(before, now, saved: saved, after: after);
      } else if (roll < 68) {
        final s = d.s;
        final before = SyncLedger.snapshot(s);
        _steppedEdit(d, r);
        if (r.nextInt(3) == 0) {
          // Killed in the middle: closing the database commits the steps
          // run so far with the rest (as the app's exit does), whole.
          await _pause(r.nextInt(5));
          d.kill();
          ledger.record(before, up(d).s);
          continue;
        }
        while (s.database.steps.isOpen) {
          await _pause(1);
        }
        ledger.record(before, s);
      } else if (roll < 88) {
        // Live messages and pushes go meanwhile.
        await _pause(r.nextInt(r.nextBool() ? 20 : 400));
      } else if (roll < 91) {
        network.cutLive();
      } else if (roll < 93) {
        d.kill();
      } else if (roll < 96) {
        d.s.sync.foreground = !d.s.sync.foreground;
      } else if (roll < 98) {
        server.restart();
      } else {
        await d.sync();
      }
    }

    // Settle: every device in the foreground syncs until all agree.
    for (final d in devices) {
      up(d).s.sync.foreground = true;
    }
    await _pause(300);
    for (var round = 0; round < 6; round++) {
      for (final d in devices) {
        time.now += 10;
        await d.sync();
      }
      final first = jsonEncode(syncedState(devices.first.s));
      if (devices.every((d) => cleanDevice(d) && jsonEncode(syncedState(d.s)) == first)) break;
    }
    final ref = await FaultDevice.start(network, time, 'z');
    reference.add(ref);
    await ref.sync();
    for (final d in devices) {
      await d.sync();
    }
    return await syncProblems(server, [...devices, ref], ledger);
  } finally {
    for (final d in [...devices, ...reference]) {
      d.dispose();
    }
    server.dispose();
  }
}

Future<void> _runs(int first, int count) async {
  for (var run = 0; run < count; run++) {
    // LEN_FAULT_REPEAT=1: the same seed every run (timing still varies).
    final seed = Platform.environment['LEN_FAULT_REPEAT'] == null ? first + run : first;
    final problems = await _run(seed, deviceCount: 2 + seed % 2);
    if (problems.isNotEmpty) {
      debugPrint(_log.join('\n'));
      fail('Seed $seed: ${problems.length} problems:\n${problems.take(40).join('\n')}');
    }
  }
}

void main() {
  setUp(() => SyncEngine.workerFromBytes = 64 * 1024);

  final env = Platform.environment;
  final seed = int.tryParse(env['LEN_LIVE_SEED'] ?? '') ?? 1;
  final runs = int.tryParse(env['LEN_LIVE_RUNS'] ?? '') ?? 3;
  test(
    'devices editing live converge and lose nothing',
    () => _runs(seed, runs),
    timeout: Timeout(Duration(minutes: 3 + runs)),
  );
  test(
    'devices editing live converge and lose nothing (more seeds)',
    () => _runs(seed + 1000, 12),
    tags: ['slow'],
    timeout: const Timeout(Duration(minutes: 20)),
  );
}
